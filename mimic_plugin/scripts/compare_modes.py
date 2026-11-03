"""Controlled single / fixed / dynamic comparison, with identical lab faults.

This measures a declared response-forgery injection, not a real vulnerability
exploit, production attack probability, or AFDX line-rate performance.
"""
import json,sys,time
from pathlib import Path
R=Path(__file__).resolve().parents[1];sys.path.insert(0,str(R));sys.path.insert(0,str(R/'scripts'))
from fixtures import POLICY,vectors
from afdx_mimic.contract import request,sha
from afdx_mimic.controller import MimicPlugin,adjudicate
from afdx_mimic.evidence import write_json
from concurrent.futures import ThreadPoolExecutor

def compare_modes(pool,out,repetitions=12):
    out=Path(out)
    if out.exists():raise ValueError('new comparison directory required')
    out.mkdir(parents=True);raw=next(raw for n,raw,w in vectors() if n=='udp_length');(out/'input.bin').write_bytes(raw)
    dynamic=MimicPlugin(pool,POLICY,mode='enforce',lab_seed=31);result={};active=['python_struct','c_offsets','cpp_cursor']
    pool.set_lab_fault('c_offsets','forged_allow')
    try:
        for mode in ('single','fixed','dynamic'):
            records=[];false_allows=0;exposure=0;start=time.monotonic()
            for i in range(repetitions):
                if mode=='dynamic':
                    r=dynamic.evaluate(raw,baseline=None);q=r['quorum'];exposure+=int('c_offsets' in r['active']);records.append(r)
                    false_allows+=int(q['semantic'] is not None and q['semantic']['verdict']=='allow')
                else:
                    data,meta=request(raw,POLICY,i+1,1);selected=['c_offsets'] if mode=='single' else active
                    deadline=time.monotonic()+.5
                    with ThreadPoolExecutor(max_workers=3) as workers:
                        rr=list(workers.map(lambda eid:pool.execute(eid,data,meta,len(raw),deadline),selected))
                    chosen=rr[0]['response'] if mode=='single' and rr[0]['status']=='ok' else None
                    q=adjudicate(rr,active) if mode=='fixed' else None
                    s=q['semantic'] if q else chosen;false_allows+=int(s is not None and s['verdict']=='allow');exposure+=1
                    records.append(dict(meta=meta,worker_results=rr,quorum=q))
            result[mode]=dict(requests=repetitions,false_allows=false_allows,faulty_executor_participations=exposure,seconds=time.monotonic()-start)
            write_json(out/(mode+'_records.json'),records)
    finally:pool.set_lab_fault('c_offsets',None)
    assert result['single']['false_allows']==repetitions
    assert result['fixed']['false_allows']==result['dynamic']['false_allows']==0
    assert result['fixed']['faulty_executor_participations']==repetitions and result['dynamic']['faulty_executor_participations']==1
    write_json(out/'summary.json',dict(status='PASS',fault='explicit c_offsets forged_allow laboratory output injection',results=result,
      input_sha256=sha(raw),production_security_probability=False,line_rate_measurement=False,
      conclusion='Both redundant modes mask this one faulty executor; dynamic mode removes its subsequent participation.'))
    return result
