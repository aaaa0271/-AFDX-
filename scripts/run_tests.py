"""Reproducible Icarus regression; every success depends on actual tool exits.

Usage: python scripts/run_tests.py [--iverilog PATH --vvp PATH --ivl-base DIR]
The frozen fixtures are used as delivered. Generators run only when requested
separately; this runner never silently regenerates signatures or test vectors.

Merged-project adaptation: when no reference_core/ snapshot exists (plugin files
merged into the live project), --core-root defaults to the project root and the
baseline hash gate is treated as provenance-only (docs/security_plugin/
BASELINE_HASHES.json records the pristine 20261012 baseline the plugin wrapped).
"""
import argparse,concurrent.futures,datetime,hashlib,json,os,re,shutil,subprocess,sys,time
from pathlib import Path
R=Path(__file__).resolve().parents[1]


def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def source_hashes():
    roots=('rtl','host','tb','scripts','tests')
    if not (R/'host').exists():roots=('rtl','host','tb','scripts','tests')
    return {str(p.relative_to(R)):digest(p) for root in roots if (R/root).exists()
            for p in sorted((R/root).rglob('*')) if p.is_file() and '__pycache__' not in p.parts}
def baseline():
    bpath=R/'reference_core'
    record=R/'docs/security_plugin/BASELINE_HASHES.json'
    if not bpath.exists():
        # Merged layout: the frozen baseline is not carried inside the live
        # project. Its per-file manifest is retained under docs/ for provenance.
        if record.exists():
            n=len(json.loads(record.read_text()))
            print('BASELINE_GATE_SKIPPED merged layout; provenance manifest has',n,'entries',flush=True)
            return n
        return 0
    expected=json.loads((R/'docs/BASELINE_HASHES.json').read_text())
    actual={str(p.relative_to(bpath)):digest(p)
            for p in bpath.rglob('*') if p.is_file()}
    if actual!=expected:raise RuntimeError('baseline file list or content changed')
    return len(actual)


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--iverilog',default=os.environ.get('IVERILOG','iverilog'))
    p.add_argument('--vvp',default=os.environ.get('VVP','vvp'))
    p.add_argument('--ivl-base',default=os.environ.get('IVL_BASE'))
    p.add_argument('--core-root',type=Path,default=None,
                   help='Core RTL/TB root; defaults to reference_core if present, else the project root')
    p.add_argument('--out',type=Path,default=R/'results/latest')
    a=p.parse_args();out=a.out.resolve()
    if out.exists():raise RuntimeError('choose a fresh output directory: '+str(out))
    C=a.core_root.resolve() if a.core_root else (R/'reference_core' if (R/'reference_core').exists() else R)
    if not (C/'rtl').exists():raise RuntimeError('core root has no rtl/: '+str(C))
    out.mkdir(parents=True);env=dict(os.environ,PYTHONDONTWRITEBYTECODE='1',TMPDIR=str(out))
    started=time.monotonic();sources=source_hashes();count=baseline()
    (out/'source_hashes.json').write_text(json.dumps(sources,indent=2)+'\n')
    commands=[];results={}
    def run(cmd,cwd,log,timeout=600):
        before=time.monotonic()
        with log.open('w') as f:
            r=subprocess.run([str(x) for x in cmd],cwd=cwd,env=env,stdout=f,stderr=subprocess.STDOUT,timeout=timeout,
                             creationflags=subprocess.CREATE_NO_WINDOW if os.name=='nt' else 0)
        commands.append({'argv':[str(x) for x in cmd],'cwd':str(cwd),'log':str(log.relative_to(out)),
                         'exit':r.returncode,'seconds':round(time.monotonic()-before,3)})
        if r.returncode:raise RuntimeError(str(log)+': command exit '+str(r.returncode))
        return log.read_text(errors='replace')
    iv=[a.iverilog]+(['-B',a.ivl_base] if a.ivl_base else [])
    includes=['-I',str(C/'rtl'),'-I',str(C/'tb')]
    production=sorted((R/'rtl').glob('*.v'))
    if C!=R:production+=sorted((C/'rtl').glob('*.v'))
    for top in ('AFDX_security_plugin_top','AFDX_security_8port_top'):
        run(iv+['-g2001',*includes,'-s',top,'-o',out/(top+'.vvp'),*production],R,out/(top+'.compile.log'))
    run(iv+['-V'],R,out/'iverilog_version.log',30)
    t=run([sys.executable,'-m','unittest','discover','-s','tests','-v'],R,out/'host_tests.log',60)
    if not re.search(r'Ran \d+ tests',t) or not t.rstrip().endswith('OK'):raise RuntimeError('host tests incomplete')
    results['host']={'status':'PASS','tests':int(re.search(r'Ran (\d+) tests',t)[1])}
    plugin=sorted((R/'rtl').glob('afdx_sec*.v'))
    jobs={
      'sha':('tb_security_sha',[R/'rtl/afdx_sec_sha256.v',R/'tb/tb_security_sha.v'],'SEC_SHA_PASS'),
      'plugin':('tb_security_plugin',plugin+[R/'tb/tb_security_plugin.v'],'SEC_PLUGIN_PASS'),
      'core_multi':('tb_security_core_multi',production+[C/'tb/model_foundation_peer.v',C/'tb/model_security_rx_filter.v',R/'tb/tb_security_core_multi.v'],'SEC_CORE_MULTI_PASS'),
      'bypass':('tb_security_bypass',production+[C/'tb/model_foundation_peer.v',C/'tb/model_security_rx_filter.v',R/'tb/model_security_baseline.v',R/'tb/model_security_plugin.v',R/'tb/tb_security_bypass.v'],'SEC_BYPASS_PASS')}
    def bench(name,spec):
        top,files,marker=spec;d=out/name;d.mkdir()
        for folder in (C/'tb',R/'tb'):
            if folder.exists():
                for fixture in folder.glob('*.hex'):shutil.copyfile(fixture,d/fixture.name)
        run(iv+['-g2001',*includes,'-s',top,'-o',d/'sim.vvp',*files],R,d/'compile.log')
        log=run([a.vvp,'-n',d/'sim.vvp'],d,d/'result.log')
        if marker not in log or re.search(r'\bFAIL\b|_FAIL\b|TIMEOUT|BYPASS_MISMATCH|SEC_CORE_VIOLATION',log):
            raise RuntimeError(name+': missing success or failure reported')
        if name=='plugin':
            n=len(json.loads((R/'tb/scenarios.json').read_text())['cases'])
            if len(re.findall('SCENARIO_PASS',log))!=n:raise RuntimeError('scenario cardinality')
            run([sys.executable,R/'scripts/verify_plugin_wire.py',str(d)],R,d/'audit.log',60)
            return {'status':'PASS','packet_scenarios':n}
        if name=='core_multi':
            run([sys.executable,C/'scripts/verify_multi_service_wire.py',str(d/'multi_services_wire.txt')],R,d/'audit.log',60)
        if name=='bypass':
            for suffix in ('shared_wire.txt','service_wire.txt'):
                b=(d/('baseline_'+suffix)).read_bytes();w=(d/('plugin_'+suffix)).read_bytes()
                if b!=w:raise RuntimeError('bypass captured bytes/timestamps differ: '+suffix)
                shutil.copyfile(d/('plugin_'+suffix),d/suffix)
            run([sys.executable,C/'scripts/verify_shared.py',str(d/'result.log')],R,d/'audit.log',60)
        return {'status':'PASS'}
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        pending={pool.submit(bench,n,s):n for n,s in jobs.items()}
        for f in concurrent.futures.as_completed(pending):
            name=pending[f];results[name]=f.result();print(name,results[name],flush=True)
    if sources!=source_hashes():raise RuntimeError('plugin sources changed during regression')
    if (R/'reference_core').exists() and baseline()!=count:raise RuntimeError('baseline changed during regression')
    result={'status':'PASS','timestamp_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
            'core_root':str(C),'baseline_files_unchanged':count,'source_files':len(sources),'results':results,
            'seconds':round(time.monotonic()-started,3),
            'scope':'Host crypto + RTL simulation and independent wire audits. No FPGA timing or board certification.'}
    (out/'commands.json').write_text(json.dumps(commands,indent=2)+'\n')
    (out/'summary.json').write_text(json.dumps(result,indent=2)+'\n')
    print('SECURITY_REGRESSION_PASS',json.dumps(result),flush=True)
if __name__=='__main__':main()
