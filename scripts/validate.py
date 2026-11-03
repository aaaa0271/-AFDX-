"""Validate model-driven investigations, evidence tools and actual RTL replay."""
import argparse,hashlib,json,os,re,subprocess,sys,time
from pathlib import Path
R=Path(__file__).resolve().parents[1];sys.path.insert(0,str(R))
from afdx_agent.agent import Agent
from afdx_agent.audit import verify
from afdx_agent.case import Case
from afdx_agent.rtl import RTLRunner

def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def sources():
    return {str(p.relative_to(R)):sha(p) for folder in ('afdx_agent','afdx_ai','security_lab','models','tests','cases','scripts')
      for p in (R/folder).rglob('*') if p.is_file() and '__pycache__' not in p.parts}

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--out',type=Path,required=True)
    parser.add_argument('--rtl',choices=['off','required'],default='required')
    parser.add_argument('--iverilog',default=os.environ.get('IVERILOG'));parser.add_argument('--vvp',default=os.environ.get('VVP'));parser.add_argument('--ivl-base',default=os.environ.get('IVL_BASE'))
    a=parser.parse_args();out=a.out.resolve()
    if out.exists():raise RuntimeError('choose a fresh output directory')
    out.mkdir(parents=True);initial=sources();start=time.monotonic()
    (out/'source_hashes.json').write_text(json.dumps(initial,indent=2)+'\n')
    env=dict(os.environ,OPENBLAS_NUM_THREADS='1',OMP_NUM_THREADS='1',PYTHONDONTWRITEBYTECODE='1',TMPDIR=str(out))
    with (out/'tests.log').open('w') as f:
        r=subprocess.run([sys.executable,'-m','unittest','discover','-s','tests','-v'],cwd=R,env=env,stdout=f,stderr=subprocess.STDOUT,timeout=120)
    log=(out/'tests.log').read_text()
    if r.returncode or not re.match(r'^OK(\s*\(.*\))?\s*$',log.strip().splitlines()[-1]):raise RuntimeError('unit/integration tests failed')
    count=int(re.search(r'Ran (\d+) tests',log)[1]);print('tests',count,'PASS',flush=True)
    config=dict(root=R,iverilog=a.iverilog,vvp=a.vvp,ivl_base=a.ivl_base,rtl_mode=a.rtl)
    reports={}
    for case in sorted((R/'cases').iterdir()):
        if not case.is_dir():continue
        report=Agent(**config).run(case,out/'cases'/case.name)
        if report['errors'] or not report['integrity_ok'] or report['stop_reason']!='complete':raise RuntimeError('agent case failed: '+case.name)
        verify(out/'cases'/case.name);reports[case.name]=report
        print(case.name,'PASS',report['steps'],'calls',flush=True)
    ab=reports['ab_conflict'];disagree=reports['model_disagreement'];compound=reports['compound'];load=reports['congestion'];missing=reports['missing_measurements']
    if ab['current_focus']!='replica_divergence' or disagree['model']['candidates'][0]['cause']!='normal' or disagree['current_focus']!='replica_divergence':raise RuntimeError('model/evidence correction failed')
    if {f['kind'] for f in compound['verified_local_findings']}!={'time_anomaly','replica_divergence'}:raise RuntimeError('compound evidence inspection incomplete')
    if missing['model'] is not None or any(f['supports_current_window'] for f in missing['verified_local_findings']):raise RuntimeError('missing data/reference fixture false claim')
    if a.rtl=='required' and load['policy']['status']!='lab_checked_candidate':raise RuntimeError('policy not actually RTL-checked')
    runner=RTLRunner(R,out/'fixed_rtl',iverilog=a.iverilog,vvp=a.vvp,ivl_base=a.ivl_base,mode=a.rtl)
    fixed={};flow=Case(R/'cases/normal').flow
    for profile in ('ab_integrity','loader_phase','time_response','fragment_budget','rate_baseline','rate_candidate'):
        result=runner.run(profile,flow);fixed[profile]=result
        if a.rtl=='required' and result['status']!='passed':raise RuntimeError('fixed RTL experiment failed')
    if initial!=sources():raise RuntimeError('implementation/models/evidence changed during validation')
    actual_rtl_audits=list(out.rglob('audit.json'));frame_cases=0
    for path in actual_rtl_audits:
        artifact=json.loads(path.read_text())
        if artifact.get('domain')=='isolated_real_security_RTL':frame_cases+=len(artifact['cases'])
    summary=dict(status='PASS',tests=count,agent_cases=len(reports),rtl_mode=a.rtl,
       fixed_rtl_profiles=len(fixed),fixed_rtl_packet_checks=sum(len(x.get('cases',[])) for x in fixed.values()),
       total_actual_rtl_runs=len(actual_rtl_audits),total_actual_rtl_packet_checks=frame_cases,
       tool_calls=sum(r['steps'] for r in reports.values()),
       model_disagreement_recovered=True,compound_local_findings=2,missing_metrics_not_imputed=True,
       policy_candidate_status=load['policy']['status'],source_files=len(initial),sources_unchanged=True,
       configuration_writes_applied=False,board_validation=False,seconds=time.monotonic()-start,
       cases={name:dict(focus=r['current_focus'],steps=r['steps'],validation_status=r['validation_status'],local_findings=len(r['verified_local_findings'])) for name,r in reports.items()},
       fixed_rtl=fixed)
    (out/'summary.json').write_text(json.dumps(summary,indent=2,ensure_ascii=False)+'\n')
    print('AGENT_VALIDATION_PASS',json.dumps({k:v for k,v in summary.items() if k not in ('cases','fixed_rtl')}),flush=True)
if __name__=='__main__':main()
