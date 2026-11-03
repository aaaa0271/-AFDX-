"""Create labelled laboratory demonstrations, not a new model accuracy benchmark."""
import copy,json,struct,sys
from dataclasses import asdict
from pathlib import Path
import numpy as np
R=Path(__file__).resolve().parents[1];sys.path.insert(0,str(R))
from afdx_agent.packets import packet
from afdx_ai.synthetic import queue_window
from afdx_ai.bridge import COUNTERS
from security_lab.policy import Rule

FLOW=dict(peer_ip=0x0a000001,local_ip=0x0a000010,rx_mac=0x030000000010,peer_mac=0x020000000002,
          tx_mac=0x030000000012,source_port=100,destination_port=200)
# Byte-exact LF output on every platform (Windows text mode would otherwise
# translate \n to \r\n and break the frozen-case reproduction hash test).
def w(path,text):path.write_bytes(text.encode('utf-8'))

def main():
    # Frozen upstream examples come from prior held-out synthetic data. They are
    # observation fixtures, not labels or instructions consumed by the agent.
    examples=json.loads((R/'scripts/observation_fixtures.json').read_text())
    def create(name,kind,missing=False):
        directory=R/'cases'/name;directory.mkdir(exist_ok=False)
        observation=copy.deepcopy(examples[kind]);observation['window_id']='agent-'+name
        if missing:observation['metrics']={k:v for k,v in observation['metrics'].items() if k in ('observed_pps','queue_overflow_ratio')}
        w((directory/'observation.json'),json.dumps(observation,indent=2)+'\n')
        manifest=dict(schema=1,case_id=name,observation='observation.json',artifacts=[],expected_flow=FLOW)
        return directory,observation,manifest
    def artifact(directory,obs,m,ident,type_,files,source='synthetic_lab',binding='same_window'):
        m['artifacts'].append(dict(id=ident,type=type_,paths=files,source=source,binding=binding,
                                  window_id=obs['window_id'] if binding=='same_window' else None))
    def finish(d,m):
        w((d/'case.json'),json.dumps(m,indent=2)+'\n')
    def log(d,o,m,text):
        w((d/'run.log'),text+'\n');artifact(d,o,m,'run_log','log',['run.log'])
    def pair(d,o,m):
        (d/'A.bin').write_bytes(packet(FLOW,b'content-one',sn=31))
        (d/'B.bin').write_bytes(packet(FLOW,b'content-two',sn=31,network='B'))
        artifact(d,o,m,'pair','frame_pair',['A.bin','B.bin'])
    d,o,m=create('normal','normal');(d/'clean.bin').write_bytes(packet(FLOW));artifact(d,o,m,'clean','frame',['clean.bin']);log(d,o,m,'normal traffic observed');finish(d,m)
    for name,kind in [('ab_conflict','replica_divergence'),('model_disagreement','normal')]:
        d,o,m=create(name,kind);pair(d,o,m);log(d,o,m,'replica content mismatch; both CRC values valid');finish(d,m)
    d,o,m=create('congestion','congestion')
    q=queue_window(np.random.default_rng(4400),55000,800,.20,1.2,3,'bursty',.2)
    o['metrics'].update(q);o['metrics'].update(management_fraction=.2,active_context_ratio=.8,sha_jobs_per_1k_frames=3)
    o['window_duration_s']=192/q['observed_pps'];w((d/'observation.json'),json.dumps(o,indent=2)+'\n')
    policy=dict(schema=1,epoch=3,rule_id=0,rule=asdict(Rule(**FLOW,timeout=30000)),requirements=dict(max_normal_logical_pps=1000,burst_frames=4))
    w((d/'policy.json'),json.dumps(policy,indent=2)+'\n');artifact(d,o,m,'policy','policy',['policy.json'])
    log(d,o,m,'queue pressure observed; baseline policy window disabled')
    start=dict(boot_id='synthetic-congestion-boot',epoch=3,mode=2,counters={k:0 for k in COUNTERS});end=copy.deepcopy(start)
    drops=round(o['metrics']['queue_overflow_ratio']*192)
    end['counters'].update(observed=192-drops,queue_overflows=drops,accepted=(192-drops)//2)
    w((d/'counters.json'),json.dumps(dict(schema=1,start=start,end=end,duration_s=o['window_duration_s']),indent=2)+'\n')
    artifact(d,o,m,'counters','counters',['counters.json']);finish(d,m)
    def time_data(d,o,m):
        t=0x1234567800000000;ms=lambda n:int(n*2**32/1000)
        data=dict(schema=1,offset_limit_ms=2000,samples=[dict(t1=t,t2=t+ms(5001),t3=t+ms(5002),t4=t+ms(3))])
        w((d/'time.json'),json.dumps(data,indent=2)+'\n');artifact(d,o,m,'ntp','time_samples',['time.json'])
    d,o,m=create('time_anomaly','time_anomaly');time_data(d,o,m);log(d,o,m,'NTP offset beyond declared clock limit');finish(d,m)
    d,o,m=create('compound','time_anomaly');time_data(d,o,m);pair(d,o,m);log(d,o,m,'NTP offset abnormal and replica content mismatch');finish(d,m)
    d,o,m=create('loader_stall','loader_stall')
    events=[dict(time_ms=0,kind='request',tid=42000,block=0,data_hex='')]+[
            dict(time_ms=1000*i,kind='timeout',tid=42000,block=1,data_hex='') for i in range(1,5)]
    w((d/'loader.json'),json.dumps(dict(schema=1,events=events),indent=2)+'\n');artifact(d,o,m,'loader','loader_trace',['loader.json'])
    log(d,o,m,'load timeout; no received block progress; TID=42000');finish(d,m)
    d,o,m=create('fragment_pressure','fragment_pressure');log(d,o,m,'fragment queue/context pressure needs independent replay');finish(d,m)
    d,o,m=create('missing_measurements','normal',missing=True)
    for source,name in [('ab_first_wire.bin','A.bin'),('ab_second_wire.bin','B.bin')]:
        (d/name).write_bytes((R/'reference_evidence'/source).read_bytes())
    artifact(d,o,m,'pair','frame_pair',['A.bin','B.bin'],source='rtl_fixture',binding='reference_fixture')
    (d/'events.txt').write_bytes((R/'reference_evidence/security_events.txt').read_bytes())
    artifact(d,o,m,'events','events',['events.txt'],source='rtl_fixture',binding='reference_fixture');finish(d,m)
    d,o,m=create('fcs_error','normal');raw=bytearray(packet(FLOW));raw[52]^=1;(d/'bad.bin').write_bytes(raw)
    artifact(d,o,m,'bad','frame',['bad.bin']);log(d,o,m,'CRC error in captured sample');finish(d,m)
    print('CASES_GENERATED',len(list((R/'cases').glob('*/case.json'))))
if __name__=='__main__':main()
