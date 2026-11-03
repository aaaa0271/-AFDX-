import json,time
from pathlib import Path
from .contract import ContractError,canonical,case,sha
from .controller import MimicPlugin
from .evidence import Journal,seal,write_json
from .workers import WorkerPool

SCENARIOS=('healthy_rotation','single_fault','timeout','stale_epoch','stale_generation','wrong_semantics','pool_exhaustion','recovery','common_mode','baseline_hard_deny')
FAULT_BY_SCENARIO={'single_fault':{'c_offsets':'forged_allow'},'timeout':{'c_offsets':'timeout'},'stale_epoch':{'c_offsets':'stale_epoch'},'stale_generation':{'c_offsets':'stale_generation'},'wrong_semantics':{'c_offsets':'wrong_semantics'},'pool_exhaustion':{'c_offsets':'crash','cpp_cursor':'crash'},'recovery':{'c_offsets':'forged_allow'},'common_mode':{'c_offsets':'forged_allow','cpp_cursor':'forged_allow'}}

def render(report):
    lines=['# AFDX 拟态防御插件报告','',f"案例：{report['case_id']}；场景：{report['scenario'] or '原始输入'}；模式：{report['mode']}。",'',
      '## 现象与范围','',
      '本次运行独立的Python/C/C++执行器，复核完整帧解析和静态白名单语义；没有向实际设备发送报文或写入配置。',
      '进程隔离与资源限制不构成抵抗同用户或内核攻击的安全沙箱。','',
      '## 逐帧裁决','', '| 请求 | 输入 | 裁决 | 原因 | 少数/失败 | 最终门控 |','|---|---|---|---|---|---|']
    if not report['input_integrity_ok']:lines.insert(4,'输入证据在调查期间发生变化，本次结论已撤销；以下仅保留过程记录。\n')
    for f in report['frames']:
        q=f['quorum'];s=q['semantic'];lines.append(f"| {f['request_id']} | {f['frame_id']} | {s['verdict'] if s else 'no_quorum'} | {s['reason'] if s else '未形成裁决'} | {','.join(q['dissenters']+q['errors']) or '-'} | {f['final_allow']} |")
    lines+=['','## 隔离、替换与恢复','']
    for e in report['scheduler_events']:lines.append('- '+json.dumps(e,ensure_ascii=False))
    if not report['scheduler_events']:lines.append('本次未触发执行器变更。')
    lines+=['','## 结论与待验证事项','',
      '- 少数分歧只证明实现输出不一致，不能单凭多数结果认定某执行器已遭攻击。',
      '- 多个执行器共享缺陷时，多数裁决仍可能错误；common_mode案例专门演示该边界。',
      '- 仅受控demo可注入固定故障；普通case文件不接受故障、程序路径或命令。',
      '- final_allow为null时，未取得原安全引擎结果，不声称已完成最终设备准入。',
      '- 影子模式不增加拦截；enforce仅是本机门控API，原引擎拒绝时始终拒绝。',
      '- 未验证完整AFDX联调、实时吞吐、目标器件时序或板级互通。','',
      '完整输入、各执行器原始输出、策略版本、调度代次和哈希链均随本报告保存。']
    return '\n'.join(lines)+'\n'

def run_case(root,case_directory,output_directory,build_dir,scenario=None,mode='shadow',deadline_ms=None,pool=None):
    root=Path(root).resolve();c=case(case_directory);out=Path(output_directory).resolve()
    if out.exists() or out.is_relative_to(c['root']):raise ContractError('choose new output outside input case')
    if scenario is not None and (scenario not in SCENARIOS or c['manifest']['source']!='synthetic_lab'):raise ContractError('only fixed synthetic laboratory scenarios allowed')
    out.mkdir(parents=True);journal=Journal(out);pool=pool or WorkerPool(root,build_dir)
    if pool.lab_faults:raise ContractError('run_case requires a clean pool; use a named synthetic demo for injection')
    plugin=MimicPlugin(pool,c['policy'],mode=mode,deadline_ms=deadline_ms,lab_seed=179 if scenario else None)
    write_json(out/'selftests.json',plugin.startup);write_json(out/'policy.json',c['policy']);write_json(out/'build_info.json',pool.info);journal.append('startup',dict(active=plugin.active,generation=plugin.generation))
    for eid,fault in FAULT_BY_SCENARIO.get(scenario,{}).items():pool.set_lab_fault(eid,fault)
    frames=c['frames']
    if scenario=='healthy_rotation':frames=[c['frames'][0]]*9
    report_frames=[];started=time.monotonic()
    try:
        for i,f in enumerate(frames):
            baseline=False if scenario=='baseline_hard_deny' else None
            result=plugin.evaluate(f['raw'],f['channel'],f['capture_ticks'],baseline=baseline)
            relative=f'requests/{i+1:03d}/result.json';write_json(out/relative,result)
            raw_path=out/f'requests/{i+1:03d}/input.bin';raw_path.write_bytes(f['raw'])
            journal.append('frame',dict(request_id=result['meta']['request_id'],frame_id=f['id'],result_file=relative,result_sha256=sha(canonical(result))))
            report_frames.append(dict(request_id=result['meta']['request_id'],frame_id=f['id'],input_file=str(raw_path.relative_to(out)),result_file=relative,quorum=result['quorum'],final_allow=result['final_allow'],seconds=result['seconds']))
            if scenario=='recovery' and i==0:
                pool.set_lab_fault('c_offsets',None);test=plugin.recover('c_offsets');write_json(out/'recovery.json',test);journal.append('recovery',dict(executor_id='c_offsets',status=test['status']))
        try:intact=case(c['root'])['hashes']==c['hashes']
        except Exception:intact=False
    finally:
        for eid in list(pool.lab_faults):pool.set_lab_fault(eid,None)
    for e in plugin.events:journal.append('scheduler',e)
    report=dict(schema=1,plugin_version='1.0.0',case_id=c['manifest']['case_id'],source=c['manifest']['source'],scenario=scenario,mode=mode,
      input_hashes=c['hashes'],input_integrity_ok=intact,frames=report_frames,scheduler_events=plugin.events,active_final=plugin.active,quarantined_final=sorted(plugin.quarantined),trace_tail=journal.tail,
      frame_count=len(report_frames),seconds=time.monotonic()-started,lab_fault_injection=scenario in FAULT_BY_SCENARIO,lab_schedule_seed=179 if scenario else None,
      expected_common_mode_limitation=scenario=='common_mode',confirmed_physical_attack=False,online_device_action=False,board_validation=False,
      scope='stateless IPv4/UDP fixed-header semantics and static ACL; no loader/fragment/time-state replication')
    if not intact:report['conclusions_valid']=False
    else:report['conclusions_valid']=True
    write_json(out/'report.json',report);(out/'report.md').write_text(render(report),encoding='utf8');seal(out)
    return report
