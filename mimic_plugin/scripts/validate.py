"""Freeze source, build real executors and validate the whole plugin release."""
import argparse,hashlib,json,os,re,subprocess,sys,time
from pathlib import Path
R=Path(__file__).resolve().parents[1];sys.path.insert(0,str(R));sys.path.insert(0,str(R/'scripts'))
from afdx_mimic.build import build
from afdx_mimic.workers import WorkerPool
from afdx_mimic.run import SCENARIOS,run_case
from afdx_mimic.evidence import verify,write_json
from afdx_mimic.bridge import investigate_with_existing_agent
from compare_modes import compare_modes
from rtl_checks import check_rtl
from native_sanitize import check_native
from release_paths import verify_local,verify_upstream

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def sources():
    return {str(p.relative_to(R)):sha(p) for folder in ('afdx_mimic','executors','scripts','tests','cases','rtl','security_lab') for p in (R/folder).rglob('*') if p.is_file() and '__pycache__' not in p.parts}|{'trusted_selftests.json':sha(R/'trusted_selftests.json')}

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path);p.add_argument('--agent-root',type=Path)
    p.add_argument('--upstream-root',type=Path);p.add_argument('--integrity-only',action='store_true')
    p.add_argument('--iverilog');p.add_argument('--vvp');p.add_argument('--ivl-base');args=p.parse_args()
    local_integrity=verify_local(R);upstream=verify_upstream(R,args.upstream_root)
    if args.integrity_only:
        print('MIMIC_INTEGRITY_PASS',json.dumps(dict(local=local_integrity,upstream=upstream)));return
    if args.out is None:p.error('--out is required unless --integrity-only is selected')
    if os.name=='nt':raise RuntimeError('this historical sanitizer/Icarus validator requires POSIX; use the integrated ModelSim runner or native unittest suite on Windows')
    out=args.out.resolve()
    if out.exists():raise RuntimeError('choose new validation output')
    out.mkdir(parents=True);initial=sources();write_json(out/'source_hashes.json',initial);started=time.monotonic()
    info=build(R,out/'build');pool=WorkerPool(R,out/'build')
    env=dict(os.environ,MIMIC_TEST_BUILD=str(out/'build'),PYTHONDONTWRITEBYTECODE='1',TMPDIR=str(out))
    with (out/'tests.log').open('w') as stream:r=subprocess.run([sys.executable,'-m','unittest','discover','-s','tests','-v'],cwd=R,env=env,stdout=stream,stderr=subprocess.STDOUT,timeout=180)
    log=(out/'tests.log').read_text()
    if r.returncode or not log.rstrip().endswith('OK'):raise RuntimeError('software tests failed')
    tests=int(re.search(r'Ran (\d+) tests',log)[1]);print('software_tests',tests,'PASS',flush=True)
    reports={}
    for directory in sorted((R/'cases').iterdir()):
        if not directory.is_dir():continue
        report=run_case(R,directory,out/'cases'/directory.name,out/'build',pool=pool);verify(out/'cases'/directory.name);reports['case_'+directory.name]=report
        assert report['input_integrity_ok'] and all(f['quorum']['status']=='quorum' for f in report['frames'])
        print('case',directory.name,'PASS',flush=True)
    for scenario in SCENARIOS:
        directory=R/'cases'/('udp_length' if scenario in ('single_fault','recovery','common_mode') else 'normal')
        report=run_case(R,directory,out/'scenarios'/scenario,out/'build',scenario,'enforce',pool=pool);verify(out/'scenarios'/scenario);reports[scenario]=report
        first=report['frames'][0]['quorum']
        if scenario=='single_fault':assert first['semantic']['verdict']=='deny' and 'c_offsets' in report['quarantined_final']
        if scenario=='common_mode':assert first['semantic']['verdict']=='allow' and report['expected_common_mode_limitation']
        if scenario=='pool_exhaustion':assert all(f['quorum']['status']=='no_quorum' for f in report['frames']) and not report['active_final']
        if scenario=='recovery':assert 'c_offsets' not in report['quarantined_final']
        if scenario=='baseline_hard_deny':assert all(f['final_allow'] is False for f in report['frames'])
        if scenario=='healthy_rotation':assert any(e['kind']=='executor_switch' for e in report['scheduler_events'])
        if scenario in ('timeout','stale_epoch','stale_generation','wrong_semantics'):assert 'c_offsets' in report['quarantined_final']
        print('scenario',scenario,'EXPECTED_LIMIT_DEMONSTRATED' if scenario=='common_mode' else 'PASS',flush=True)
    compare=compare_modes(pool,out/'mode_comparison');print('mode_comparison PASS',flush=True)
    sanitizer=check_native(out/'native_sanitizer');print('sanitizer',sanitizer['executions'],'PASS',flush=True)
    rtl=check_rtl(out/'rtl',args.iverilog,args.vvp,args.ivl_base);print('RTL',rtl['quorum_rtl_cases'],rtl['original_security_packet_checks'],'PASS',flush=True)
    integration=None
    if args.agent_root:
        integration=investigate_with_existing_agent(out/'scenarios/single_fault',args.agent_root,out/'agent_bridge')
        assert integration['agent_integrity_ok'] and integration['no_missing_metrics_imputed'];print('existing_agent_bridge PASS',flush=True)
    if initial!=sources():raise RuntimeError('implementation or evidence changed during validation')
    frames=sum(r['frame_count'] for r in reports.values());selfchecks=sum(len(r['vectors']) for r in pool.startup_certificates)
    summary=dict(status='PASS',software_tests=tests,independent_executors=len(info['executors']),golden_executor_checks=selfchecks,
      input_cases=3,lab_scenarios=len(SCENARIOS),investigation_frames=frames,native_sanitized_executions=sanitizer['executions'],quorum_rtl_cases=rtl['quorum_rtl_cases'],original_security_packet_checks=rtl['original_security_packet_checks'],
      mode_comparison=compare,common_mode_limitation_demonstrated=True,existing_agent_bridge=integration is not None,
      upstream_files_checked=upstream['files_checked'],upstream_unchanged=True if upstream['status']=='PASS' else None,upstream=upstream,local_integrity=local_integrity,frozen_source_files=len(initial),sources_unchanged=True,
      complete_mac_wrapper=False,new_voter_connected_to_original_security=False,board_validation=False,online_device_action=False,seconds=time.monotonic()-started,
      reports={name:dict(frames=r['frame_count'],quarantined=r['quarantined_final'],conclusions_valid=r['conclusions_valid']) for name,r in reports.items()})
    write_json(out/'summary.json',summary);print('MIMIC_VALIDATION_PASS',json.dumps({k:v for k,v in summary.items() if k not in ('mode_comparison','reports')}),flush=True)

if __name__=='__main__':main()
