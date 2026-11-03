import copy,json,math
from pathlib import Path
import numpy as np
from afdx_ai.plugin import DiagnosticPlugin
from afdx_ai.schema import InputError,FEATURES,validate_observation
from afdx_ai.bridge import decode_event,FLAGS,COUNTERS,counter_metrics
from afdx_ai.synthetic import queue_window
from security_lab.policy import Rule
from .case import canonical,sha
from .packets import parse,compare,mutate_payload

class Tools:
    def __init__(self,case,root,output,rtl):
        self.case=case;self.root=Path(root);self.output=Path(output);self.rtl=rtl
        self.model=DiagnosticPlugin(self.root/'models');self.results={}
        self.registry={name:getattr(self,name) for name in
          ('inventory','diagnose','parse_frames','compare_pairs','summarize_events','search_logs',
           'inspect_time','inspect_loader','inspect_counters','mutate_replica','simulate_queue','counterfactual_diagnosis',
           'rtl_experiment','replay_capture','propose_policy')}

    def dispatch(self,name,args):
        if name not in self.registry:raise InputError('tool is not allowlisted')
        if not isinstance(args,dict):raise InputError('tool arguments must be an object')
        return self.registry[name](**args)

    def inventory(self):
        metrics=self.case.observation.get('metrics',{}) if self.case.observation else {}
        present=list(metrics) if isinstance(metrics,dict) else []
        missing=[f for f in FEATURES if f not in present]
        return dict(status='ok',case_id=self.case.id,case_sha256=self.case.fingerprint,
                    artifacts=list(self.case.artifacts.values()),files=self.case.files,
                    missing_metrics=missing,model_input_available=not missing and bool(self.case.observation))

    def diagnose(self):
        if self.case.observation is None:return dict(status='insufficient_data',missing_metrics=FEATURES)
        try:result=self.model.analyze(self.case.observation)
        except InputError as e:
            metrics=self.case.observation.get('metrics',{})
            missing=[f for f in FEATURES if f not in metrics] if isinstance(metrics,dict) else list(FEATURES)
            return dict(status='insufficient_data',reason=str(e),missing_metrics=missing)
        result['status_model']=result['status'];result['status']='ok';self.results['model']=result
        return result

    def parse_frames(self,artifact_id):
        item=self.case.artifact(artifact_id)
        if item['type'] not in ('frame','frame_pair'):raise InputError('frame artifact required')
        return dict(status='ok',frames=[parse(self.case.read(p)) for p in item['paths']],provenance=self.case.provenance(artifact_id))

    def compare_pairs(self,artifact_id):
        item=self.case.artifact(artifact_id,'frame_pair')
        result=compare(*[self.case.read(p) for p in item['paths']]);result.update(status='ok',provenance=self.case.provenance(artifact_id))
        return result

    def summarize_events(self,artifact_id):
        item=self.case.artifact(artifact_id,'events');raw=self.case.read(item['paths'][0]).decode('utf8')
        if len(raw.splitlines())>30000:raise InputError('event count budget')
        reasons={};channels={};count=0;examples=[]
        for number,line in enumerate(raw.splitlines(),1):
            if not line.strip():continue
            fields=line.split()
            if len(fields) not in (2,3):raise InputError('event log columns')
            for field in fields[:-1]:int(field)
            event=decode_event(int(fields[-1],16));count+=1;ch=str(event['channel']);channels[ch]=channels.get(ch,0)+1
            if event['flags'] and len(examples)<12:examples.append(dict(line=number,event=event))
            for mask,name in FLAGS.items():
                if event['flags']&mask:reasons[name]=reasons.get(name,0)+1
        return dict(status='ok',events=count,channels=channels,reason_counts=reasons,examples=examples,
                    used_as_model_features=False,provenance=self.case.provenance(artifact_id))

    def search_logs(self,keywords):
        if not isinstance(keywords,list) or not 1<=len(keywords)<=6 or any(not isinstance(k,str) or not 1<=len(k)<=40 for k in keywords):raise InputError('literal keyword limits')
        matches=[];searched=[]
        for ident,item in self.case.artifacts.items():
            if item['type']!='log':continue
            lines=self.case.read(item['paths'][0]).decode('utf8',errors='replace').splitlines()
            if len(lines)>20000:raise InputError('log line budget')
            searched.append(self.case.provenance(ident))
            for n,line in enumerate(lines,1):
                if any(k.casefold() in line.casefold() for k in keywords):
                    matches.append(dict(artifact_id=ident,line=n,text=line[:320],matched=[k for k in keywords if k.casefold() in line.casefold()]))
                    if len(matches)>=20:break
        return dict(status='ok',keywords=keywords,matches=matches[:20],searched=searched,literal_search=True,log_text_executed=False)

    def inspect_time(self,artifact_id):
        item=self.case.artifact(artifact_id,'time_samples');d=self.case.read_json(item['paths'][0])
        if set(d)!={'schema','samples','offset_limit_ms'} or d['schema']!=1 or not isinstance(d['samples'],list) or not 1<=len(d['samples'])<=1000:raise InputError('NTP sample schema')
        limit=d['offset_limit_ms']
        if type(limit) not in (int,float) or not math.isfinite(limit) or limit<=0:raise InputError('NTP limit')
        samples=[]
        for row in d['samples']:
            if set(row)!={'t1','t2','t3','t4'} or any(type(v) is not int or not 0<=v<2**64 for v in row.values()):raise InputError('NTP Q32.32 timestamp')
            t1,t2,t3,t4=[row[k] for k in ('t1','t2','t3','t4')]
            rtt=((t4-t1)-(t3-t2))*1000/2**32;offset=((t2-t1)+(t3-t4))*1000/(2*2**32)
            samples.append(dict(rtt_ms=rtt,offset_ms=offset,negative_rtt=rtt<0,exceeds_declared_limit=abs(offset)>limit))
        return dict(status='ok',samples=samples,offset_limit_ms=limit,
                    finding='time_exchange_outside_declared_limit' if any(s['negative_rtt'] or s['exceeds_declared_limit'] for s in samples) else 'no_limit_exceedance',
                    provenance=self.case.provenance(artifact_id),server_authentication_verified=False)

    def inspect_loader(self,artifact_id):
        item=self.case.artifact(artifact_id,'loader_trace');d=self.case.read_json(item['paths'][0])
        if set(d)!={'schema','events'} or d['schema']!=1 or not isinstance(d['events'],list) or len(d['events'])>1000:raise InputError('loader trace schema')
        time=-1;blocks={};retries=0;changed=[];out_of_order=[];timeouts=0;current_tid=None;next_block=1
        for i,event in enumerate(d['events'],1):
            if set(event)!={'time_ms','kind','tid','block','data_hex'}:raise InputError('loader event fields')
            t=event['time_ms'];kind=event['kind'];tid=event['tid'];block=event['block']
            if type(t) not in (int,float) or not math.isfinite(t) or t<time or kind not in ('request','data','ack','timeout','complete'):raise InputError('loader event order/type')
            if type(tid) is not int or not 0<=tid<=65535 or type(block) is not int or not 0<=block<=65535:raise InputError('loader TID/block')
            if not isinstance(event['data_hex'],str) or len(event['data_hex'])>1024:raise InputError('loader data bound')
            data=bytes.fromhex(event['data_hex']);time=t
            if kind=='request':current_tid=tid;blocks={};next_block=1
            elif kind=='timeout':timeouts+=1
            elif kind=='data':
                if tid!=current_tid:out_of_order.append(dict(event=i,reason='wrong_tid'));continue
                if block in blocks:
                    retries+=1
                    if blocks[block]!=data:changed.append(i)
                elif block!=next_block:out_of_order.append(dict(event=i,reason='block_sequence'))
                else:blocks[block]=data;next_block+=1
        stalled=timeouts>=3 and not blocks
        return dict(status='ok',timeouts=timeouts,duplicate_blocks=retries,changed_duplicate_events=changed,
                    sequence_issues=out_of_order,unique_received_bytes=sum(map(len,blocks.values())),
                    no_progress_with_repeated_timeouts=stalled,provenance=self.case.provenance(artifact_id),
                    finding='loader_trace_anomaly' if stalled or changed or out_of_order else 'no_trace_anomaly')

    def inspect_counters(self,artifact_id):
        item=self.case.artifact(artifact_id,'counters');d=self.case.read_json(item['paths'][0])
        if not isinstance(d,dict) or set(d)!={'schema','start','end','duration_s'} or type(d['schema']) is not int or d['schema']!=1:
            raise InputError('counter snapshot schema')
        for snapshot in (d['start'],d['end']):
            if not isinstance(snapshot,dict) or set(snapshot)!={'boot_id','epoch','mode','counters'}:raise InputError('snapshot fields')
            if not isinstance(snapshot['boot_id'],str) or not snapshot['boot_id']:raise InputError('snapshot boot_id')
            if type(snapshot['epoch']) is not int or not 0<=snapshot['epoch']<2**32 or type(snapshot['mode']) is not int or snapshot['mode'] not in (0,1,2):raise InputError('snapshot epoch/mode')
            if not isinstance(snapshot['counters'],dict) or set(snapshot['counters'])!=set(COUNTERS):raise InputError('snapshot counter names')
        try:result=counter_metrics(d['start'],d['end'],d['duration_s'])
        except InputError as error:
            return dict(status='inconclusive',reason=str(error),finding='unusable_counter_boundary',provenance=self.case.provenance(artifact_id))
        result.update(status='ok',finding='queue_drop_counter_increased' if result['raw_counter_deltas']['queue_overflows'] else 'no_queue_drop_increase',
                      provenance=self.case.provenance(artifact_id),missing_values_imputed=False)
        return result

    def mutate_replica(self,artifact_id):
        item=self.case.artifact(artifact_id,'frame_pair');original=self.case.read(item['paths'][0]);d=parse(original)
        if d['issues'] or d.get('fragment_offset') or d.get('more_fragments') or 'udp_length' not in d:return dict(status='inconclusive',reason='need valid complete UDP baseline')
        import binascii
        clean=bytearray(original);clean[19]=(clean[19]&0x9f)|0x40;clean[-4:]=binascii.crc32(clean[8:-4]).to_bytes(4,'little')
        injected=mutate_payload(bytes(clean));negative=bytearray(injected);negative[52]^=1
        directory=self.output/'experiments'/('injection_'+artifact_id);directory.mkdir(parents=True,exist_ok=True)
        for name,raw in [('baseline.bin',original),('normal_interface_B.bin',bytes(clean)),('valid_checksums_changed_B.bin',injected),('bad_fcs_negative_control.bin',bytes(negative))]:(directory/name).write_bytes(raw)
        return dict(status='passed',domain='controlled_software_injection',
          clean_control=compare(original,bytes(clean)),injected=compare(original,injected),negative_control=parse(bytes(negative)),
          directory=str(directory.relative_to(self.output)),proves_current_case_cause=False,
          provenance=self.case.provenance(artifact_id))

    def simulate_queue(self,scale=.5,repetitions=12):
        if type(scale) not in (int,float) or not .25<=scale<1 or type(repetitions) is not int or not 4<=repetitions<=32:raise InputError('simulation budget')
        if self.case.observation is None:return dict(status='insufficient_data')
        validate_observation(self.case.observation);m=self.case.observation['metrics'];before=[];after=[]
        for i in range(repetitions):
            params=[m['observed_pps'],m['mean_frame_bytes'],m['frame_size_cv'],m['arrival_cv'],m['sha_jobs_per_1k_frames'],'bursty',m['management_fraction']]
            before.append(queue_window(np.random.default_rng(9100+i),*params))
            params[0]*=scale;after.append(queue_window(np.random.default_rng(9100+i),*params))
        mean=lambda rows,k:float(np.mean([r[k] for r in rows]))
        b={k:mean(before,k) for k in before[0]};a={k:mean(after,k) for k in after[0]}
        result=dict(status='ok',domain='abstract_shared_inspector_v1',repetitions=repetitions,seed_start=9100,offered_rate_scale=scale,
          baseline=b,counterfactual=a,improvement_observed=a['latency_p95_us']<b['latency_p95_us'] and a['queue_overflow_ratio']<=b['queue_overflow_ratio'],
          model_target='conditional laboratory counterfactual, not current-device reproduction',hardware_timing_proof=False)
        self.results['queue']=result;return result

    def counterfactual_diagnosis(self):
        if 'queue' not in self.results:return dict(status='insufficient_data',reason='queue experiment required')
        observation=copy.deepcopy(self.case.observation);observation['source']='synthetic';observation['window_id']+='-counterfactual'
        observation['metrics'].update(self.results['queue']['counterfactual'])
        observation['window_duration_s']=192/max(observation['metrics']['observed_pps'],1e-9)
        result=self.model.analyze(observation);result['status_model']=result['status'];result['status']='ok'
        result['counterfactual_only']=True;self.results['counterfactual_model']=result;return result

    def rtl_experiment(self,profile):
        return self.rtl.run(profile,self.case.flow)

    def replay_capture(self,artifact_id):
        item=self.case.artifact(artifact_id,'frame_pair')
        result=self.rtl.run('captured_pair',self.case.flow,capture=[self.case.read(p) for p in item['paths']])
        result['provenance']=self.case.provenance(artifact_id);return result

    def propose_policy(self,cause):
        policies=[(i,a) for i,a in self.case.artifacts.items() if a['type']=='policy']
        advice={'replica_divergence':'保留内容一致性检查，调查两份业务数据的生产者及加载来源。',
          'time_anomaly':'保留时间边界检查，核实时间源身份、路径延迟及稳定锁定后的偏移。',
          'loader_stall':'核对会话TID、超时及缺失块；保持签名授权、目标校验与版本下限。',
          'fragment_pressure':'核实正常并发重组需求，再限制各服务域上下文并观测正常流量。',
          'link_degradation':'核对链路、线缆与副本缺失；保持CRC及双网检查。',
          'congestion':'按正常逻辑帧峰值和突发预算生成速率窗口候选。',
          'management_burst':'按正常管理请求预算生成独立速率窗口候选。',
          'normal':'维持现有策略并继续观测。'}
        base=dict(status='advice_only',advice=advice.get(cause,'补充测量与证据。'),writes_applied=False,
                  requires_trusted_configuration_flow=True,complete_policy_validation=False)
        if cause not in ('congestion','management_burst') or not policies:return base
        if 'queue' not in self.results or not self.results['queue']['improvement_observed']:
            return dict(**base,reason='未获得支持限流的实验结果，不生成参数改动。')
        ident,item=policies[0];d=self.case.read_json(item['paths'][0])
        if set(d)!={'schema','epoch','rule_id','rule','requirements'} or d['schema']!=1:raise InputError('policy snapshot schema')
        if type(d['epoch']) is not int or not 0<=d['epoch']<2**32 or type(d['rule_id']) is not int or not 0<=d['rule_id']<16:raise InputError('policy epoch/rule')
        old=Rule(**d['rule']);old_words=old.words();req=d['requirements']
        if any(getattr(old,k)!=v for k,v in self.case.flow.items()):raise InputError('policy snapshot does not match trusted case flow')
        if set(req)!={'max_normal_logical_pps','burst_frames'}:raise InputError('normal traffic requirement fields')
        pps=req['max_normal_logical_pps'];burst=req['burst_frames']
        if type(pps) is not int or not 1<=pps<=4000 or type(burst) is not int or not 0<=burst<=32:raise InputError('normal requirement bounds')
        window=125000;maximum=math.ceil(pps*window/12500000)+burst
        if not 1<=maximum<=80:return dict(**base,reason='候选超过固定验证配置。')
        if old.window and old.max_frames and old.max_frames/old.window<=maximum/window:return dict(**base,reason='现有配置已达到或严于候选，不放宽。')
        updated=copy.deepcopy(old);updated.window=window;updated.max_frames=maximum;new_words=updated.words()
        changes=[dict(field=f,old=getattr(old,f),new=getattr(updated,f),shadow_register=0x100+64*d['rule_id']+word*4)
                 for f,word in [('window',12),('max_frames',13)] if getattr(old,f)!=getattr(updated,f)]
        if any(a!=b for i,(a,b) in enumerate(zip(old_words,new_words)) if i not in (12,13)):raise InputError('policy change outside allowed fields')
        baseline=self.rtl.run('rate_baseline',self.case.flow,max_frames=maximum,window=window)
        candidate=self.rtl.run('rate_candidate',self.case.flow,max_frames=maximum,window=window)
        status='lab_checked_candidate' if baseline['status']=='passed' and candidate['status']=='passed' else 'unvalidated_candidate'
        return dict(status=status,advice=base['advice'],writes_applied=False,changes=changes,updated_rule=updated.__dict__,
          expected_epoch=d['epoch'],base_rule_sha256=sha(canonical(old_words)),patch_sha256=sha(canonical(changes)),
          requires_full_active_policy_shadow_clone=True,requires_epoch_and_base_hash_recheck=True,
          requires_normal_traffic_shadow_trial=True,requires_trusted_configuration_flow=True,
          complete_policy_validation=False,validated_scope='standalone rate-window behavior; not all deployed flows',
          policy_provenance=self.case.provenance(ident),experiments=[baseline,candidate])
