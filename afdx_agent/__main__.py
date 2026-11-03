import argparse,json,os
from pathlib import Path
from .agent import Agent
from .audit import verify

def main():
    p=argparse.ArgumentParser(description='AFDX model-guided diagnostic tool agent')
    sub=p.add_subparsers(dest='command',required=True)
    run=sub.add_parser('run');run.add_argument('--case',type=Path,required=True);run.add_argument('--out',type=Path,required=True)
    run.add_argument('--max-steps',type=int,default=16);run.add_argument('--rtl',choices=['auto','off','required'],default='auto')
    run.add_argument('--iverilog',default=os.environ.get('IVERILOG'));run.add_argument('--vvp',default=os.environ.get('VVP'));run.add_argument('--ivl-base',default=os.environ.get('IVL_BASE'))
    audit=sub.add_parser('verify');audit.add_argument('--run',type=Path,required=True)
    a=p.parse_args()
    try:
        if a.command=='verify':result=verify(a.run)
        else:
            report=Agent(iverilog=a.iverilog,vvp=a.vvp,ivl_base=a.ivl_base,rtl_mode=a.rtl,max_steps=a.max_steps).run(a.case,a.out)
            result={k:report[k] for k in ('case_id','completion','stop_reason','steps','current_focus','errors','configuration_writes_applied','validation_status')}
            result['report']=str(a.out/'report.md')
        print(json.dumps(result,indent=2,ensure_ascii=False))
        if a.command=='run':
            if report['errors'] or not report['integrity_ok']:return 3
            if report['stop_reason']=='budget_exhausted':return 4
    except Exception as error:p.exit(2,f'{type(error).__name__}: {error}\n')
if __name__=='__main__':raise SystemExit(main())
