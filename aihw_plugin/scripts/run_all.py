#!/usr/bin/env python3
"""One command for independent local validation. Missing tools cause failure."""
import argparse
import json
import os
import subprocess
import sys
import time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from afdx_ai_hw.fixed import write_json,load_model


def main():
    p=argparse.ArgumentParser()
    p.add_argument('--retrain',action='store_true',help='also reproduce original NumPy training')
    args=p.parse_args()
    (ROOT/'reports').mkdir(exist_ok=True)
    commands=[]
    if (ROOT/'RELEASE_MANIFEST.json').exists():commands.append(('release_integrity',['scripts/verify_release.py']))
    commands += [('host_tests',['-m','unittest','discover','-s','tests','-p','test_*.py','-v']),
                 ('export_reproduction',['scripts/verify_export.py']),
                 ('holdout_freeze',['scripts/make_hardware_holdout.py']),
                 ('quantization',['scripts/evaluate_quantization.py']),
                 ('rtl_validation',['scripts/validate_rtl.py']),
                 ('demo',['-m','afdx_ai_hw','infer','--history','examples/history.json','--out','reports/demo_rtl.json'])]
    if args.retrain:commands.append(('training_reproduction',['scripts/reproduce_training.py']))
    summary=dict(model_tag=load_model()[0]['model_tag'],status='RUNNING',stages=[])
    env=dict(os.environ,OPENBLAS_NUM_THREADS='1',OMP_NUM_THREADS='1')
    for name,command in commands:
        start=time.monotonic()
        with (ROOT/'reports'/('run_all_'+name+'.log')).open('w') as log:
            r=subprocess.run([sys.executable,*command],cwd=ROOT,env=env,stdout=log,stderr=subprocess.STDOUT,timeout=700)
        summary['stages'].append(dict(name=name,status='PASS' if r.returncode==0 else 'FAIL',seconds=time.monotonic()-start))
        write_json(ROOT/'reports/run_all.json',summary)
        print(name,summary['stages'][-1]['status'],flush=True)
        if r.returncode:raise SystemExit(r.returncode)
    summary['status']='PASS'
    summary['physical_board_validation']=False
    write_json(ROOT/'reports/run_all.json',summary)
    print('ALL_VALIDATION_PASS',flush=True)


if __name__=='__main__':main()
