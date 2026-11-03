"""One reproducible project: isolated ModelSim tests + independent decoders + eLinx.

Functional regression success is explicitly distinct from normative completeness.
No historical output can satisfy a test in a new run.
"""
from pathlib import Path
from datetime import datetime, timezone, timedelta
import argparse, concurrent.futures, csv, hashlib, json, os, re, shutil, subprocess, sys
import xml.etree.ElementTree as ET
from verdict import verdict
from check_competition import evaluate as competition_evaluate
ROOT=Path(__file__).resolve().parents[1]
AI_SOURCE=ROOT/'aihw_plugin/rtl/afdx_ai_tcn_plugin.v'
UTC8=timezone(timedelta(hours=8))

def default_elinx():
    # Honor an explicit environment override, then probe the install layouts
    # observed on delivery/verification machines before falling back to the
    # historical default (which still produces the original clear error).
    env=os.environ.get('AFDX_ELINX')
    if env:return env
    candidates=(
        'D:/eLinx3.0/bin/Passkey/bin/quartus_map.exe',
        'C:/Program Files (x86)/eHiWay/eLinx3.0/bin/Passkey/bin/quartus_map.exe',
        'D:/Program Files (x86)/eHiWay/eLinx3.0/bin/Passkey/bin/quartus_map.exe',
        'D:/Program Files (x86)/eLinx3.0/bin/Passkey/bin/quartus_map.exe',
    )
    for c in candidates:
        if Path(c).is_file():return c
    return candidates[0]

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def json_write(p,obj):p.write_text(json.dumps(obj,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
def inputs():
    files=[]
    for folder in ('rtl','tb','scripts','vendor','host','afdx_agent','afdx_ai','mimic_plugin','aihw_plugin','report_tools'):
        files.extend(p for p in (ROOT/folder).rglob('*') if p.is_file() and '__pycache__' not in p.parts and 'reports' not in p.parts and p.suffix!='.pyc')
    files.extend(p for p in (ROOT/'docs').rglob('*') if p.is_file())
    files.extend(ROOT/n for n in ('README.md','README_PACKAGE.md','requirements.txt','requirements-report.txt','VERSION.txt','run_demo.ps1'))
    files.extend(ROOT/n for n in ('ARINC.epr','ARINC.qsf','ARINC.qpf','run_all.ps1','AFDX_12p5MHz.sdc'))
    return {p.relative_to(ROOT).as_posix():sha(p) for p in sorted(files)}

def execute(cmd,cwd,out,timeout):
    env=dict(os.environ,PYTHONDONTWRITEBYTECODE='1',PYTHONUTF8='1')
    try:
        with out.open('wb') as stream:
            p=subprocess.run(cmd,cwd=cwd,env=env,stdout=stream,stderr=subprocess.STDOUT,timeout=timeout,
                             creationflags=subprocess.CREATE_NO_WINDOW if os.name=='nt' else 0)
        return p.returncode
    except subprocess.TimeoutExpired:
        with out.open('ab') as stream:stream.write(b'\nRUNNER_TIMEOUT\n')
        return -1
    except OSError as e:
        with out.open('ab') as stream:stream.write(('\nTOOL_LAUNCH_ERROR '+str(e)+'\n').encode())
        return -2

def check_project():
    files={p.relative_to(ROOT).as_posix() for p in (ROOT/'rtl').glob('*.v')}|{AI_SOURCE.relative_to(ROOT).as_posix()}
    tree=ET.parse(ROOT/'ARINC.epr')
    listed={x.get('Path').lstrip('/') for x in tree.findall(".//FileSet[@Type='DesignSrcs']/File")}
    qfiles=set(re.findall(r'-name VERILOG_FILE "([^"]+)"',(ROOT/'ARINC.qsf').read_text()))
    if files!=listed or files!=qfiles:raise ValueError('GUI/CLI RTL filesets differ')
    # Executable resources must not point back to any previous project checkout.
    bad=[]
    for base in ('rtl','tb','scripts'):
        for p in (ROOT/base).glob('*'):
            if p.is_file() and p.suffix in ('.v','.vh','.py','.json'):
                s=p.read_text(encoding='utf-8-sig').replace('\\','/').lower()
                if ('d:'+ '/elinx/'+'afdx/') in s or ('d:'+ '/elinx/'+'arinc/') in s:bad.append(p.relative_to(ROOT).as_posix())
    if bad:raise ValueError('Nonportable executable references: '+repr(bad))
    return {'status':'PASS','rtl_files':len(files),'same_gui_cli_sources':True,'external_workspace_references':bad}

def run_hdl(test,out,modelsim):
    d=out/test['name'];d.mkdir()
    if test.get('driver')=='defense_live':
        code=execute([sys.executable,str(ROOT/'scripts/verify_defense_live.py'),'--out',str(d/'live'),'--modelsim',str(modelsim)],ROOT,d/'console.log',test.get('timeout_seconds',1800))
        text=(d/'console.log').read_text(encoding='utf-8',errors='replace')
        summary=d/'live/summary.json'
        passed=code==0 and summary.is_file() and json.loads(summary.read_text(encoding='utf-8')).get('status')=='PASS' and 'DEFENSE_LIVE_INTEGRATION_PASS' in text
        row=dict(name=test['name'],suite=test['suite'],status='PASS' if passed else 'FAIL',exit=code,log=(d/'console.log').relative_to(out).as_posix(),audits=[],issues=[] if passed else ['Integrated native/RTL defense runner failed; see console.log'])
        json_write(d/'status.json',row);print(test['suite'],test['name'],row['status'],flush=True);return row
    production=sorted((ROOT/'rtl').glob('*.v'))+[AI_SOURCE]
    peers=sorted((ROOT/'tb').glob('model_*.v'))
    sources=production+peers
    if test['name']=='tb_m6e_01d_mechanics':
        sources=[p for p in sources if p.name!='afdx_m6d_integration.v']+[ROOT/'tb/m6d_01d_test_double.v']
    sources+=[ROOT/test['file']]
    for p in (ROOT/'tb').glob('*.hex'):shutil.copyfile(p,d/p.name)
    rom=d/'aihw_plugin/rtl';rom.mkdir(parents=True)
    for p in (ROOT/'aihw_plugin/rtl').glob('*.mem'):shutil.copyfile(p,rom/p.name)
    do=['onerror {quit -code 2 -f}','onbreak {resume}','vlib work','vmap work work',
        'vlog -vlog01compat -work work {+incdir+'+(ROOT/'tb').as_posix()+'} {+incdir+'+(ROOT/'aihw_plugin/rtl').as_posix()+'} '+' '.join('{'+p.as_posix()+'}' for p in sources),
        'vsim -c -voptargs=+acc -onfinish stop -t 1ps -lib work '+test.get('top',test['name'])+' '+ ' '.join('-G'+k+'='+str(v) for k,v in test.get('parameters',{}).items()),
        'run '+str(test['run_ms'])+' ms',
        'set errors [examine -radix decimal sim:/'+test.get('top',test['name'])+'/'+test['error_counter']+']',
        'puts "REGRESSION_FINAL_ERRORS=$errors"','if {$errors != 0} {quit -code 1 -f}','quit -code 0 -f']
    (d/'run.do').write_text('\n'.join(do)+'\n',encoding='utf-8')
    rc=execute([str(modelsim),'-c','-do','run.do','-l','result.log'],d,d/'console.log',test.get('timeout_seconds',300))
    text=(d/'console.log').read_text(errors='replace')
    if (d/'result.log').exists():text+='\n'+(d/'result.log').read_text(errors='replace')
    status,bad=verdict(text,rc,test['marker'])
    lines=[re.sub(r'^#\s?','',line).strip() for line in text.splitlines()]
    # A bare verdict text must be emitted, not merely echoed inside a command.
    if test['marker'] not in lines:status='FAIL';bad.append('Exact terminal PASS marker missing')
    if 'RUNNER_TIMEOUT' in text or 'TOOL_LAUNCH_ERROR' in text:status='FAIL'
    audits=[]
    if status=='PASS':
        for script,arg in test['auditors']:
            log=d/(Path(script).stem+'.log')
            code=execute([sys.executable,str(ROOT/'scripts'/script),str(d/arg)],d,log,120)
            audits.append(dict(script=script,exit=code,log=log.relative_to(out).as_posix()))
            if code!=0:status='FAIL';bad.append('Independent audit failed: '+script)
    row=dict(name=test['name'],suite=test['suite'],status=status,exit=rc,log=(d/'result.log').relative_to(out).as_posix(),audits=audits,issues=bad)
    json_write(d/'status.json',row)
    print(test['suite'],test['name'],status,flush=True)
    if bad:print('\n'.join(bad[:5]),flush=True)
    return row

def run_elinx_configuration(out,exe,domains,design='defense',timeout=1200):
    """Analysis/elaboration only; placeholder Quartus part is not EQ6HL130 synthesis."""
    if design not in ('defense','baseline') or domains not in (1,2):
        raise ValueError('elaboration configuration')
    dirname=('elinx' if domains==1 else 'elinx_multi') if design=='defense' else ('elinx_baseline' if domains==1 else 'elinx_baseline_multi')
    d=out/dirname;d.mkdir()
    sources=sorted((ROOT/'rtl').glob('*.v'))+[AI_SOURCE]
    top='AFDX_defense_top' if design=='defense' else 'AFDX_competition_top'
    design_top=top
    if domains!=1:
        top='AFDX_'+design+'_multi_elab_top'
        wrapper=d/(top+'.v')
        wrapper.write_text('module '+top+'; '+design_top+' #(.SERVICE_DOMAINS(2)) dut(); endmodule\n',encoding='utf-8')
        sources.append(wrapper)
    # Both current RTL defaults and plugin defaults are relative to cwd.
    for folder in ('aihw_plugin/rtl','rtl'):
        dest=d/folder;dest.mkdir(parents=True,exist_ok=True)
        for p in (ROOT/'aihw_plugin/rtl').glob('*.mem'):shutil.copyfile(p,dest/p.name)
    q=['set_global_assignment -name DEVICE EP1S80F1508C6','set_global_assignment -name FAMILY Stratix',
       'set_global_assignment -name TOP_LEVEL_ENTITY '+top,
       'set_global_assignment -name PROJECT_OUTPUT_DIRECTORY output',
       'set_global_assignment -name VERILOG_INPUT_VERSION VERILOG_2001',
       'set_global_assignment -name SEARCH_PATH "'+(ROOT/'aihw_plugin/rtl').as_posix()+'"',
       'set_global_assignment -name SEARCH_PATH "'+(d/'aihw_plugin/rtl').as_posix()+'"']
    q+=['set_global_assignment -name VERILOG_FILE "'+p.as_posix()+'"' for p in sources]
    (d/'ARINC.qsf').write_text('\n'.join(q)+'\n');(d/'ARINC.qpf').write_text('PROJECT_REVISION = "ARINC"\n')
    cmd=[str(exe),'--read_settings_files=on','--write_settings_files=off','--analysis_and_elaboration','ARINC']
    json_write(d/'command.json',cmd)
    rc=execute(cmd,d,d/'elaboration.log',timeout)
    text=(d/'elaboration.log').read_text(errors='replace')
    m=re.search(r'Analysis & Elaboration was successful\. 0 errors, (\d+) warnings',text)
    ok=rc==0 and m is not None and 'RUNNER_TIMEOUT' not in text
    result=dict(status='PASS' if ok else 'FAIL',exit=rc,tool=str(exe),top=design_top,
                elaborated_top=top,service_domains=domains,errors=0 if ok else None,
                warnings=int(m[1]) if m else None,sources=len(sources),
                stages=dict(analysis_elaboration='PASS' if ok else 'FAIL',
                            target_synthesis='NOT_RUN',place_route='NOT_RUN',timing='NOT_RUN'),
                analysis_part='EP1S80F1508C6',target_part='EQ6HL130',
                scope='Quartus-compatible analysis/elaboration only; not EQ6HL130 synthesis, fitting, timing closure or board evidence')
    json_write(d/'status.json',result);print('ELINX',design,domains,result['status'],flush=True)
    return result


def run_elinx(out,exe,timeout=1200):
    single=run_elinx_configuration(out,exe,1,timeout=timeout)
    single['multi_domain']=run_elinx_configuration(out,exe,2,timeout=timeout)
    single['baseline']=run_elinx_configuration(out,exe,1,design='baseline',timeout=timeout)
    single['baseline']['multi_domain']=run_elinx_configuration(out,exe,2,design='baseline',timeout=timeout)
    if any(row['status']!='PASS' for row in (single['multi_domain'],single['baseline'],single['baseline']['multi_domain'])):
        single['status']='FAIL'
    return single


def reuse_elinx(out,previous,exe):
    """Explicit, source-checked reuse; never relabels cached evidence as fresh execution."""
    previous=previous.resolve()
    if not previous.is_relative_to((ROOT/'results').resolve()):raise ValueError('Reuse evidence outside this project')
    prior=json.loads((previous/'acceptance.json').read_text(encoding='utf-8'))
    hashes=json.loads((previous/'source_hashes.json').read_text(encoding='utf-8'))
    es=json.loads((previous/'elinx/status.json').read_text(encoding='utf-8'))
    current={p.relative_to(ROOT).as_posix():sha(p) for p in (ROOT/'rtl').glob('*.v')}
    old={k:v for k,v in hashes.items() if k.startswith('rtl/') and k.endswith('.v')}
    if old!=current or prior['changed_inputs']:raise ValueError('Cannot reuse compilation of different or modified RTL')
    for name,digest in current.items():
        if sha(previous/'source_snapshot'/name)!=digest:raise ValueError('Previous RTL snapshot mismatch '+name)
    for name in ('ARINC.epr','ARINC.qsf','ARINC.qpf'):
        if hashes.get(name)!=sha(ROOT/name):raise ValueError('Compiler project settings changed')
    log=(previous/'elinx/elaboration.log').read_text(errors='replace')
    if es['status']!='PASS' or es['exit']!=0 or es['top']!='AFDX_competition_top' or es['errors']!=0:raise ValueError('Previous eLinx run not passed')
    if not re.search(r'Analysis & Elaboration was successful\. 0 errors, (\d+) warnings',log):raise ValueError('Missing raw compiler success')
    if Path(es['tool']).resolve()!=Path(exe).resolve():raise ValueError('Different compiler requested')
    d=out/'elinx';d.mkdir()
    for name in ('elaboration.log','command.json'):
        shutil.copyfile(previous/'elinx'/name,d/name)
    result=dict(es,reused=True,reused_from_run=previous.relative_to(ROOT).as_posix(),production_hashes_verified=current,
                original_log_sha256=sha(previous/'elinx/elaboration.log'),scope='Explicit reuse of actual eLinx analysis/elaboration for identical production RTL and project settings; this is not a new compiler invocation')
    json_write(d/'status.json',result)
    print('ELINX PASS (explicit source-verified reuse)',previous,flush=True)
    return result

def external_output_root(value=None):
    # Keep generated work libraries separate from sources, but inside this
    # delivery by default as requested. Never write into rtl/tb/docs/scripts.
    base=Path(value) if value else Path(os.environ.get('AFDX_RESULTS_ROOT',str(ROOT/'results')))
    base=base.expanduser().resolve()
    source=ROOT.resolve()
    if base==source or (base.is_relative_to(source) and not base.is_relative_to(source/'results')):
        raise ValueError('Use the results subdirectory or a path outside the source directory')
    return base

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--reuse-elinx',type=Path);ap.add_argument('--tests',nargs='+');ap.add_argument('--hdl-only',action='store_true');ap.add_argument('--elinx-only',action='store_true');ap.add_argument('--require-conformance',action='store_true')
    ap.add_argument('--modelsim',default=os.environ.get('AFDX_MODELSIM','C:/modeltech64_2020.4/win64/vsim.exe'))
    ap.add_argument('--elinx',default=default_elinx())
    ap.add_argument('--output-root',type=Path)
    ap.add_argument('--elinx-timeout',type=int,default=1200,help='Per-configuration elaboration timeout in seconds')
    ap.add_argument('--workers',type=int,default=1,choices=range(1,9),help='Independent isolated ModelSim runs (1..8)')
    args=ap.parse_args()
    try: output_base=external_output_root(args.output_root)
    except ValueError as e:ap.error(str(e))
    if args.reuse_elinx:ap.error('Fresh compilation is required for both single and multi-domain configurations')
    if args.hdl_only and args.elinx_only:ap.error('conflicting selections')
    alltests=json.loads((ROOT/'scripts/tests.json').read_text())
    tests=[t for t in alltests if not args.tests or t['name'] in args.tests]
    if args.tests and len(tests)!=len(args.tests):ap.error('unknown/duplicate test names')
    stamp=datetime.now(UTC8);out=output_base/('run_'+stamp.strftime('%Y%m%d_%H%M%S_%f'));out.mkdir(parents=True)
    print('RUN_EVIDENCE',out,flush=True)
    before=inputs();json_write(out/'source_hashes.json',before)
    project=check_project();json_write(out/'project_audit.json',project)
    gates=[]
    for script in ('test_verdict.py','test_conformance_gate.py','test_packaging.py','test_competition_gate.py','verify_standard_mib_inventory.py','test_worst_case_envelope.py','test_release_paths.py','freeze_plugin_manifests.py'):
        code=execute([sys.executable,str(ROOT/'scripts'/script)],ROOT,out/(script+'.log'),120)
        gates.append(dict(name=script,exit=code,status='PASS' if code==0 else 'FAIL'))
    if any(g['exit'] for g in gates):raise RuntimeError('Preflight gate self-test failed: '+str(out))
    rows=[];el={'status':'NOT_RUN'}
    # Independent tools have independent result directories. Both consume the
    # same pinned inputs; no background edits are permitted during this run.
    with concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
        task=(pool.submit(reuse_elinx,out,args.reuse_elinx,Path(args.elinx)) if args.reuse_elinx else pool.submit(run_elinx,out,Path(args.elinx),args.elinx_timeout)) if not args.hdl_only else None
        if not args.elinx_only:
            if args.workers==1:
                for test in tests:rows.append(run_hdl(test,out,Path(args.modelsim)))
            else:
                with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as simulations:
                    pending=[simulations.submit(run_hdl,test,out,Path(args.modelsim)) for test in tests]
                    rows=[job.result() for job in pending]
        if task is not None:el=task.result()
    ccode=execute([sys.executable,str(ROOT/'scripts/check_conformance.py'),'--out',str(out/'conformance.json')],ROOT,out/'conformance.log',120)
    conformance=json.loads((out/'conformance.json').read_text())
    after=inputs();changed=sorted(k for k in set(before)|set(after) if before.get(k)!=after.get(k))
    json_write(out/'source_changes.json',changed)
    ok=not changed and all(t['status']=='PASS' for t in rows) and (args.hdl_only or el['status']=='PASS') and ccode in (0,1)
    full=ok and len(rows)==len(alltests) and el['status']=='PASS'
    competition=competition_evaluate(ROOT,out,rows,el,changed,full)
    json_write(out/'competition_acceptance.json',competition)
    result=dict(release=(ROOT/'VERSION.txt').read_text().strip(),source_root=str(ROOT),competition_prototype_status=competition['status'],competition_prototype_complete=competition['competition_prototype_complete'],functional_status='PASS' if ok else 'FAIL',full_functional_regression=full,
      production_hdl_total=sum(t['suite']!='experimental' for t in rows),production_hdl_passed=sum(t['suite']!='experimental' and t['status']=='PASS' for t in rows),
      experimental_model_total=sum(t['suite']=='experimental' for t in rows),experimental_model_passed=sum(t['suite']=='experimental' and t['status']=='PASS' for t in rows),
      elinx=el,changed_inputs=changed,preflight_gates=gates,tests=rows,conformance_status=conformance['status'],
      full_foundation_complete=False,formal_arinc_certification=False,
      delivery_status='COMPETITION_PROFILE_PASS' if competition['competition_prototype_complete'] else 'INCOMPLETE',started_at=stamp.isoformat(),finished_at=datetime.now(UTC8).isoformat(),
      scope='Integrated competition prototype within docs/competition_profile.json. Full selected-edition standard expansions are tracked separately and are not certified.')
    json_write(out/'acceptance.json',result)
    with (out/'results.csv').open('w',newline='',encoding='utf-8') as f:
        w=csv.DictWriter(f,fieldnames=['name','suite','status','exit','log']);w.writeheader()
        for row in rows:w.writerow({k:row[k] for k in w.fieldnames})
    # Immutable input snapshot allows reproducing this verdict after edits.
    for name,digest in before.items():
        dest=out/'source_snapshot'/name;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(ROOT/name,dest)
        if sha(dest)!=digest:raise RuntimeError('Snapshot changed '+name)
    if full and competition['competition_prototype_complete']:json_write(output_base/'latest.json',dict(run=out.as_posix(),acceptance_sha256=sha(out/'acceptance.json'),functional_status='PASS',conformance_status=conformance['status'],competition_prototype_status=competition['status'],competition_prototype_complete=competition['competition_prototype_complete'],full_foundation_complete=False))
    print('FUNCTIONAL',result['functional_status'],'FULL_FUNCTIONAL_RUN',full,'COMPETITION_PROTOTYPE',competition['status'],'STANDARD_CONFORMANCE',conformance['status'],flush=True)
    return 1 if not ok or (full and not competition['competition_prototype_complete']) else 2 if args.require_conformance and not conformance['conformance_pass'] else 0
if __name__=='__main__':raise SystemExit(main())

