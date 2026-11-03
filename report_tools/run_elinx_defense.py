"""Portable single-configuration compatibility analysis; never a target synthesis claim."""
import argparse
import sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
from run_all import default_elinx, run_elinx_configuration

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--out',type=Path,required=True)
    p.add_argument('--elinx',default=default_elinx())
    p.add_argument('--domains',type=int,choices=(1,2),default=1)
    p.add_argument('--top',choices=('defense','core'),default='defense')
    p.add_argument('--timeout',type=int,default=1200)
    a=p.parse_args()
    out=a.out.resolve()
    if out==ROOT or (out.is_relative_to(ROOT) and not out.is_relative_to(ROOT/'results')):
        p.error('Choose results/ or an external output directory')
    out.mkdir(parents=True,exist_ok=False)
    result=run_elinx_configuration(out,Path(a.elinx),a.domains,
        design='baseline' if a.top=='core' else 'defense',timeout=a.timeout)
    return 0 if result['status']=='PASS' else 1
if __name__=='__main__':raise SystemExit(main())
