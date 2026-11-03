import time
from pathlib import Path
from .case import Case,canonical,sha
from .tools import Tools
from .rtl import RTLRunner
from .audit import Journal,atomic_json,verify

MECHANISMS={'normal':'ab_integrity','replica_divergence':'ab_integrity','link_degradation':'ab_integrity',
 'time_anomaly':'time_response','loader_stall':'loader_phase','fragment_pressure':'fragment_budget',
 'congestion':'rate_baseline','management_burst':'rate_baseline'}
PRIORITY={'replica_divergence':['frame_pair','frame','events','log','time_samples','loader_trace'],
 'time_anomaly':['time_samples','events','frame_pair','frame','log','loader_trace'],
 'loader_stall':['loader_trace','frame','events','log','frame_pair','time_samples']}

class Agent:
    def __init__(self,root=None,iverilog=None,vvp=None,ivl_base=None,rtl_mode='auto',max_steps=16):
        self.root=Path(root or Path(__file__).resolve().parents[1]).resolve()
        if type(max_steps) is not int or not 1<=max_steps<=24:raise ValueError('max_steps must be 1..24')
        self.options=dict(iverilog=iverilog,vvp=vvp,ivl_base=ivl_base,mode=rtl_mode);self.max_steps=max_steps

    def run(self,case_directory,output_directory):
        case=Case(case_directory);out=Path(output_directory).resolve()
        if out.exists() or out.is_relative_to(case.root):raise ValueError('output must be a new directory outside the evidence case')
        out.mkdir(parents=True);journal=Journal(out)
        rtl=RTLRunner(self.root,out/'experiments/rtl',**self.options);tools=Tools(case,self.root,out,rtl)
        self.case=case;self.tools=tools;self.journal=journal;self.out=out;self.done=set();self.outputs=[];self.findings=[];self.prior={};self.boost={};self.cause='normal'
        stopped='complete'
        for _ in range(self.max_steps):
            action=self.next_action()
            if action is None:break
            name,args,reason=action;key=self.key(name,args)
            if key in self.done:raise RuntimeError('planner repeated an already completed action')
            before=time.monotonic()
            try:result=tools.dispatch(name,args)
            except Exception as e:result=dict(status='error',error_type=type(e).__name__,reason=str(e)[:400])
            self.done.add(key);record=journal.append(name,args,result,time.monotonic()-before)
            self.outputs.append(dict(tool=name,args=args,reason=reason,record=record,result=result))
            self.update(name,args,result,record)
            atomic_json(out/'state.json',dict(case_id=case.id,steps=len(self.outputs),current_focus=self.cause,trace_tail=journal.previous))
        else:
            if self.next_action() is not None:stopped='budget_exhausted'
        # Recheck the frozen evidence inventory before publishing any conclusion.
        evidence_ok=True
        try:
            for p in list(case.files):case.read(p)
        except Exception as e:evidence_ok=False;stopped='evidence_changed';self.findings.append(dict(kind='evidence_changed',detail=str(e),domain='integrity_failure',supports_current_window=False))
        report=self.report(stopped,evidence_ok)
        atomic_json(out/'report.json',report);(out/'report.md').write_text(render_markdown(report),encoding='utf8')
        atomic_json(out/'completion.json',dict(trace_tail=journal.previous,report_sha256=sha((out/'report.json').read_bytes()),markdown_sha256=sha((out/'report.md').read_bytes())))
        atomic_json(out/'audit_verification.json',verify(out))
        return report

    @staticmethod
    def key(name,args):return name+':'+sha(canonical(args))
    def did(self,name,**args):return self.key(name,args) in self.done

    def next_action(self):
        if not self.did('inventory'):return 'inventory',{},'先固定证据清单、来源和测量覆盖。'
        if not self.did('diagnose'):return 'diagnose',{},'调用三个固定模型，建立候选与时延/异常参考。'
        # Direct evidence can change the next action even when the model disagrees.
        for output in self.outputs:
            if output['tool']=='compare_pairs' and output['result'].get('finding')=='valid_replica_content_conflict':
                ident=output['args']['artifact_id']
                if not self.did('mutate_replica',artifact_id=ident):return 'mutate_replica',dict(artifact_id=ident),'发现合法校验的内容分歧，增加受控注入和负对照。'
                if not self.did('replay_capture',artifact_id=ident):return 'replay_capture',dict(artifact_id=ident),'将这两份捕获帧重放到隔离RTL，核对实际事件与转发字节。'
        priority=PRIORITY.get(self.cause,['events','frame_pair','frame','time_samples','loader_trace','log'])
        for type_ in ['counters',*priority]:
            for ident,item in self.case.artifacts.items():
                if item['type']!=type_:continue
                tool={'frame_pair':'compare_pairs','frame':'parse_frames','events':'summarize_events','time_samples':'inspect_time','loader_trace':'inspect_loader','counters':'inspect_counters'}.get(type_)
                if tool and not self.did(tool,artifact_id=ident):return tool,dict(artifact_id=ident),'按当前候选和可用证据选择独立检查：'+self.cause
        if any(a['type']=='log' for a in self.case.artifacts.values()) and not any(o['tool']=='search_logs' for o in self.outputs):
            words={'loader_stall':['timeout','TID','load'],'time_anomaly':['clock','NTP','offset'],
                   'replica_divergence':['replica','CRC','content']}.get(self.cause,['queue','timeout','error'])
            return 'search_logs',dict(keywords=words),'定位日志原文、文件哈希和行号。'
        measurement=self.case.observation.get('metrics',{}) if self.case.observation else {}
        overflow=measurement.get('queue_overflow_ratio',0) if isinstance(measurement,dict) else 0
        queue_focus=self.cause in ('congestion','management_burst') or (type(overflow) in (int,float) and overflow>0)
        if queue_focus and 'model' in self.tools.results:
            if not self.did('simulate_queue',scale=.5,repetitions=12):return 'simulate_queue',dict(scale=.5,repetitions=12),'进行成对种子的负载降低反事实实验，检查时延与丢弃变化。'
            if not self.did('counterfactual_diagnosis'):return 'counterfactual_diagnosis',{},'将实验后指标重新送入三个模型，与原候选比较；不混同当前测量。'
        profile=MECHANISMS[self.cause]
        if not self.did('rtl_experiment',profile=profile):return 'rtl_experiment',dict(profile=profile),'针对当前焦点执行固定RTL机制实验及正常恢复对照。'
        if not any(o['tool']=='propose_policy' for o in self.outputs):return 'propose_policy',dict(cause=self.cause),'根据证据及实验生成可审查建议，并校验允许修改范围。'
        return None

    def update(self,name,args,r,record):
        if name=='diagnose' and r.get('status')=='ok':
            self.prior={c['cause']:c['vote_share'] for c in r['candidates']}
        provenance=r.get('provenance',{});same=provenance.get('binding')=='same_window'
        finding=None;cause=None
        if name=='compare_pairs' and r.get('finding')=='valid_replica_content_conflict':finding='已核对同一逻辑消息的两份合法校验帧存在内容差异';cause='replica_divergence'
        elif name=='inspect_time' and r.get('finding')=='time_exchange_outside_declared_limit':finding='时间戳计算结果违反给定偏移/往返约束';cause='time_anomaly'
        elif name=='inspect_loader' and r.get('finding')=='loader_trace_anomaly':finding='加载记录存在无进展超时、块序或重传内容异常';cause='loader_stall'
        elif name=='parse_frames' and any('fcs' in f.get('issues',[]) for f in r.get('frames',[])):finding='捕获帧的独立CRC计算不符';cause='link_degradation'
        if name=='inspect_counters' and r.get('finding')=='queue_drop_counter_increased':finding='同一启动与策略窗口内，输入帧队列丢弃计数增加';cause='congestion'
        if finding:
            item=dict(kind=cause,detail=finding,domain=provenance.get('source'),supports_current_window=same,
                      provenance=provenance,tool_result=record['result_file'])
            self.findings.append(item)
            if same:self.boost[cause]=self.boost.get(cause,0)+1.1
        ranking={c:self.prior.get(c,0)+self.boost.get(c,0) for c in MECHANISMS}
        self.cause=max(ranking,key=ranking.get)

    def report(self,stopped,evidence_ok):
        model=self.tools.results.get('model');policy=[o['result'] for o in self.outputs if o['tool']=='propose_policy']
        errors=[dict(tool=o['tool'],reason=o['result'].get('reason')) for o in self.outputs if o['result'].get('status')=='error']
        experiments=[]
        for o in self.outputs:
            if o['tool'] in ('rtl_experiment','replay_capture','mutate_replica','simulate_queue','counterfactual_diagnosis'):
                experiments.append(dict(tool=o['tool'],status=o['result'].get('status'),domain=o['result'].get('domain','model_counterfactual'),result_file=o['record']['result_file']))
            if o['tool']=='propose_policy':
                for e in o['result'].get('experiments',[]):experiments.append(dict(tool=e.get('profile'),status=e.get('status'),domain=e.get('domain'),result_file=o['record']['result_file']))
        pending=[]
        if stopped=='budget_exhausted':pending.append('达到工具步数预算，剩余调查未执行。')
        if errors:pending.append('存在工具失败，失败步骤不计为验证通过。')
        if any(e['status']=='unavailable' for e in experiments):pending.append('本次未运行全部RTL实验；缺少工具或已关闭。')
        if model is None:pending.append('缺少完整有效测量，未运行模型诊断；未补零。')
        if model and model.get('status_model')!='candidate':pending.append('模型低把握或超出支持范围，保留候选。')
        pending.extend(['真实设备根因仍需现场测量确认。','三个模型来自合成数据，异常召回及复合故障识别仍有限。'])
        return dict(schema=1,agent_version='1.0.0',agent_type='model_guided_bounded_tool_agent',
          case_id=self.case.id,case_sha256=self.case.fingerprint,stop_reason=stopped,steps=len(self.outputs),
          integrity_ok=evidence_ok,trace_tail=self.journal.previous,current_focus=self.cause,
          model=model,verified_local_findings=self.findings if evidence_ok else [],invalidated_findings=self.findings if not evidence_ok else [],confirmed_physical_root_cause=None,
          experiments=experiments,policy=policy[0] if policy else None,
          validation_status='integrity_failure' if not evidence_ok else 'tool_failure' if errors else 'budget_limited' if stopped=='budget_exhausted' else 'partial' if any(e['status']=='unavailable' for e in experiments) else 'evidence_only' if model is None else 'lab_checks_completed',
          tool_trace=[dict(seq=o['record']['seq'],tool=o['tool'],args=o['args'],reason=o['reason'],status=o['result'].get('status'),result_file=o['record']['result_file']) for o in self.outputs],
          unresolved=pending,errors=errors,configuration_writes_applied=False,board_validation=False,
          source_files=self.case.files,completion='completed_with_limits' if stopped!='complete' or errors else 'completed')

def render_markdown(report):
    esc=lambda x:str(x).replace('\n',' ').replace('|','\\|').replace('`','\\`')
    text=f"# AFDX 智能体诊断报告：{esc(report['case_id'])}\n\n调查状态：{report['completion']}；停止原因：{report['stop_reason']}；工具调用：{report['steps']}。\n\n"
    text+='## 现象与模型候选\n\n'
    if report['model']:
        text+=f"模型状态：{report['model']['status_model']}。森林投票份额不是校准概率；当前调查焦点为 `{report['current_focus']}`。\n\n"
        text+='| 候选 | 投票份额 |\n|---|---:|\n'
        for c in report['model']['candidates']:text+=f"| {esc(c['name'])} | {c['vote_share']:.4f} |\n"
    else:text+='完整测量不足，模型未运行。\n'
    text+='\n## 已核对的局部证据\n\n'
    if not report['verified_local_findings']:text+='本次没有足以形成局部确定事实的捕获证据。\n'
    for f in report['verified_local_findings']:
        text+=f"- {esc(f['detail'])}。来源：{esc(f.get('domain'))}；与当前窗口绑定：{f.get('supports_current_window',False)}；[结果]({f.get('tool_result','trace.jsonl')})。\n"
    text+='\n## 主动验证过程\n\n| 工具/实验 | 状态 | 证据域 | 输出 |\n|---|---|---|---|\n'
    for e in report['experiments']:text+=f"| {esc(e['tool'])} | {esc(e['status'])} | {esc(e['domain'])} | [JSON]({e['result_file']}) |\n"
    text+='\n## 策略建议\n\n'
    if report['policy']:
        p=report['policy'];text+=esc(p.get('advice',p.get('reason','建议未生成')))+'\n\n'
        for c in p.get('changes',[]):text+=f"- `{c['field']}`：{c['old']} → {c['new']}，影子寄存器 `0x{c['shadow_register']:04x}`。\n"
        text+='\n候选需要完整影子表复制、epoch/原值重查、正常流量影子试运行及既有可信配置流程应用。本智能体未写入设备配置。\n'
    else:text+='本次未完成策略建议。\n'
    text+='\n## 结论与待验证事项\n\n本次结果区分模型候选、局部捕获事实、受控注入与隔离RTL机制实验；尚未确认为真实设备物理根因。\n\n'
    for item in report['unresolved']:text+='- '+esc(item)+'\n'
    text+='\n## 可追溯调用\n\n| 序号 | 工具 | 选择原因 | 状态 |\n|---|---|---|---|\n'
    for t in report['tool_trace']:text+=f"| {t['seq']} | [{t['tool']}]({t['result_file']}) | {esc(t['reason'])} | {esc(t['status'])} |\n"
    return text
