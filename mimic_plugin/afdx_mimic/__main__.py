import argparse,json
from pathlib import Path
from .build import build
from .bridge import export_agent_case,inspect_mimic,investigate_with_existing_agent
from .evidence import verify
from .run import SCENARIOS,run_case

def main():
    r=Path(__file__).resolve().parents[1];p=argparse.ArgumentParser(description='AFDX semantic mimic-defense laboratory plugin');sub=p.add_subparsers(dest='command',required=True)
    b=sub.add_parser('build');b.add_argument('--out',type=Path,default=Path('build/local'));b.add_argument('--cc');b.add_argument('--cxx')
    for name in ('run','demo'):
        a=sub.add_parser(name);a.add_argument('--out',type=Path,required=True);a.add_argument('--build',type=Path,default=Path('build/local'));a.add_argument('--mode',choices=['shadow','enforce'],default='shadow');a.add_argument('--deadline-ms',type=int,default=None)
        if name=='run':a.add_argument('--case',type=Path,required=True)
        else:a.add_argument('--scenario',choices=SCENARIOS,required=True)
    v=sub.add_parser('verify');v.add_argument('--run',type=Path,required=True)
    e=sub.add_parser('export-agent');e.add_argument('--run',type=Path,required=True);e.add_argument('--out',type=Path,required=True)
    i=sub.add_parser('inspect');i.add_argument('--run',type=Path,required=True)
    a=sub.add_parser('agent');a.add_argument('--run',type=Path,required=True);a.add_argument('--agent-root',type=Path,required=True);a.add_argument('--out',type=Path,required=True)
    args=p.parse_args()
    try:
        if args.command=='build':result=build(r,args.out,args.cc,args.cxx)
        elif args.command in ('run','demo'):
            scenario=args.scenario if args.command=='demo' else None
            case_dir=args.case if args.command=='run' else r/'cases'/('udp_length' if scenario in ('single_fault','recovery','common_mode') else 'normal')
            report=run_case(r,case_dir,args.out,args.build,scenario,args.mode,args.deadline_ms)
            result={k:report[k] for k in ('case_id','scenario','frame_count','active_final','quarantined_final','input_integrity_ok','online_device_action')};result['report']=str(args.out/'report.md')
        elif args.command=='verify':result=verify(args.run)
        elif args.command=='inspect':result=inspect_mimic(args.run)
        elif args.command=='export-agent':result=export_agent_case(args.run,args.out)
        else:result=investigate_with_existing_agent(args.run,args.agent_root,args.out)
        print(json.dumps(result,indent=2,ensure_ascii=False))
        if args.command in ('run','demo'):
            if not report['input_integrity_ok']:return 4
            if any(f['quorum']['status']=='no_quorum' for f in report['frames']):return 3
    except Exception as error:p.exit(2,type(error).__name__+': '+str(error)+'\n')
if __name__=='__main__':raise SystemExit(main())
