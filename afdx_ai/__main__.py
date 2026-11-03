import argparse,json
from pathlib import Path
from .schema import strict_json,InputError
from .plugin import DiagnosticPlugin
from .bridge import summarize_events,compare_ab

def main():
    p=argparse.ArgumentParser(description='AFDX read-only ML diagnostic plugin')
    p.add_argument('--models',type=Path,default=Path(__file__).resolve().parents[1]/'models')
    sub=p.add_subparsers(dest='command',required=True)
    i=sub.add_parser('infer');i.add_argument('--input',type=Path,required=True);i.add_argument('--out',type=Path)
    e=sub.add_parser('events');e.add_argument('--input',type=Path,required=True);e.add_argument('--out',type=Path)
    b=sub.add_parser('compare-ab');b.add_argument('--first',type=Path,required=True);b.add_argument('--second',type=Path,required=True);b.add_argument('--out',type=Path)
    a=p.parse_args()
    try:
        if a.command=='infer':result=DiagnosticPlugin(a.models).analyze(strict_json(a.input))
        elif a.command=='events':result=summarize_events(a.input)
        else:result=compare_ab(a.first.read_bytes(),a.second.read_bytes())
        text=json.dumps(result,indent=2,ensure_ascii=False,allow_nan=False)+'\n'
        if a.out:a.out.parent.mkdir(parents=True,exist_ok=True);a.out.write_text(text,encoding='utf8')
        print(text,end='')
    except (InputError,ValueError,KeyError,OSError) as error:p.exit(2,str(error)+'\n')
if __name__=='__main__':main()
