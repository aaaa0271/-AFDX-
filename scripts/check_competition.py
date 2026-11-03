"""Project-level competition prototype gate; never claims full standard compliance."""
from pathlib import Path
import hashlib,json
IDS={'COMP-F01','COMP-F02','COMP-F03','COMP-F04','COMP-F05'}
REQUIRED_AUDITS={
 'tb_615a_roundtrip':{'verify_download_wire.py'},
 'tb_contest_snmp_pysnmp':{'verify_snmp_interop.py'},
 'tb_contest_basic_mac_top':{'verify_service_wire.py','test_service_wire.py'},
 'tb_completion_snmp_extended':{'verify_snmp_extended.py'},
 'tb_foundation_snmp_bulk_mac':{'verify_shared.py'},
 'tb_datagram_mac_joint':{'verify_shared.py'},
 'tb_integration_subvl_mac':{'verify_subvl_wire.py'},
 'tb_integration_multi_services':{'verify_multi_service_wire.py'}}
def evaluate(root,run,tests,elinx,changed,full):
 root=Path(root);run=Path(run);spec=json.loads((root/'docs/competition_requirements.json').read_text(encoding='utf-8'))
 issues=[];byname={t['name']:t for t in tests};rows=[]
 if {r['id'] for r in spec['requirements']}!=IDS or len(spec['requirements'])!=5:issues.append('Incomplete five-goal inventory')
 if len(byname)!=len(tests):issues.append('Duplicate test results')
 if not full:issues.append('Not a complete current functional regression')
 if changed:issues.append('Inputs changed during run')
 if elinx.get('status')!='PASS' or elinx.get('errors')!=0 or elinx.get('top')!='AFDX_defense_top':issues.append('Current AFDX_defense_top eLinx evidence missing')
 if spec.get('required_service_domains')==2:
  multi=elinx.get('multi_domain',{})
  if multi.get('status')!='PASS' or multi.get('errors')!=0 or multi.get('service_domains')!=2:issues.append('Dual-domain elaboration not passed')
 if elinx.get('baseline',{}).get('status')!='PASS':issues.append('Independent baseline elaboration missing')
 for source in spec.get('sources',[]):
  p=(root/source['path']).resolve()
  if not p.is_relative_to(root.resolve()) or not p.is_file() or hashlib.sha256(p.read_bytes()).hexdigest()!=source['sha256']:issues.append('Contest source image missing/changed')
 for name,scripts in REQUIRED_AUDITS.items():
  t=byname.get(name,{})
  actual={a['script'] for a in t.get('audits',[]) if a['exit']==0 and (run/a['log']).is_file()}
  if not scripts.issubset(actual):issues.append('Required independent audit missing: '+name)
 for req in spec['requirements']:
  failed=[n for n in req['tests'] if byname.get(n,{}).get('status')!='PASS']
  rows.append(dict(id=req['id'],name=req['name'],status='PASS' if not failed else 'INCOMPLETE',missing_or_failed_tests=failed,tests=req['tests']))
  if failed:issues.append(req['id']+': required test(s) not passed')
 return dict(status='PASS' if not issues else 'INCOMPLETE',competition_prototype_complete=not issues,profile=spec['profile'],requirements=rows,issues=issues,
 scope=spec['scope'],full_selected_standard_scope_complete=False,formal_arinc_certification=False)