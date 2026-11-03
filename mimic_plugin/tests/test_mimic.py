import concurrent.futures,contextlib,copy,hashlib,io,json,os,random,shutil,subprocess,sys,tempfile,time,unittest
from pathlib import Path
from unittest.mock import patch
R=Path(__file__).resolve().parents[1];sys.path.insert(0,str(R));sys.path.insert(0,str(R/'scripts'))
from fixtures import POLICY,FLOW,frame,expected,vectors,change,generate
from afdx_mimic.build import build,SPECS
from afdx_mimic.contract import ContractError,canonical,case,decode_response,load_json,policy,request,semantic,semantic_hash
from afdx_mimic.controller import MimicPlugin,adjudicate,combine_gate
from afdx_mimic.workers import WorkerPool
from afdx_mimic.run import run_case
from afdx_mimic.evidence import verify
from afdx_mimic.bridge import export_agent_case,inspect_mimic

_TEMP=None;_POOL=None
def pool():
 global _TEMP,_POOL
 if _POOL is None:
  path=os.environ.get('MIMIC_TEST_BUILD')
  if path:_POOL=WorkerPool(R,Path(path))
  else:
   _TEMP=tempfile.TemporaryDirectory(dir=R/'reports');directory=Path(_TEMP.name)/'build';build(R,directory);_POOL=WorkerPool(R,directory)
 return _POOL
def response(raw,eid='python_struct',p=POLICY):
 # Differential parsing checks are not a host real-time latency benchmark.
 data,meta=request(raw,p,17,2);result=pool().execute(eid,data,meta,len(raw),time.monotonic()+(15 if os.name=='nt' else 1))
 if result['status']!='ok':raise AssertionError(result)
 return result['response']

class ContractTests(unittest.TestCase):
 def test_duplicate_json_rejected(self):
  with self.assertRaises(ContractError):load_json('{"a":1,"a":2}')
 def test_nan_rejected(self):
  with self.assertRaises(ContractError):load_json('{"a":NaN}')
 def test_policy_unknown_field(self):
  p=copy.deepcopy(POLICY);p['shell']='touch nope'
  with self.assertRaises(ContractError):policy(p)
 def test_policy_duplicate_id(self):
  p=copy.deepcopy(POLICY);p['rules']*=2
  with self.assertRaises(ContractError):policy(p)
 def test_policy_boolean_integer(self):
  p=copy.deepcopy(POLICY);p['epoch']=True
  with self.assertRaises(ContractError):policy(p)
 def test_policy_sorted_stably(self):
  p=copy.deepcopy(POLICY);p['rules'].append(dict(p['rules'][0],id=1));self.assertEqual([1,3],[r['id'] for r in policy(p)['rules']])
 def test_request_bounds(self):
  for raw,ch in [(b'x'*2049,0),(b'',2),(b'',True)]:
   with self.subTest(ch=ch),self.assertRaises(ContractError):request(raw,POLICY,1,1,ch)
 def test_request_boolean_id(self):
  with self.assertRaises(ContractError):request(frame(),POLICY,True,1)
 def test_stale_response_binding(self):
  raw=frame();data,meta=request(raw,POLICY,17,2);r=response(raw)
  for key in meta:
   d=copy.deepcopy(r);d[key]=d[key]^1 if isinstance(d[key],int) else '0'*64
   with self.subTest(key=key),self.assertRaises(ContractError):decode_response(canonical(d),meta,len(raw))
 def test_boolean_semantic_field(self):
  raw=frame();_,meta=request(raw,POLICY,17,2);r=response(raw);r['fields'][0]=True
  with self.assertRaises(ContractError):decode_response(canonical(r),meta,len(raw))
 def test_noncanonical_denial(self):
  raw=frame();_,meta=request(raw,POLICY,17,2);r=response(raw);r.update(verdict='deny',reason='ACL')
  with self.assertRaises(ContractError):decode_response(canonical(r),meta,len(raw))
 def test_payload_length_binding(self):
  raw=frame();_,meta=request(raw,POLICY,17,2);r=response(raw);r['payload_hex']=''
  with self.assertRaises(ContractError):decode_response(canonical(r),meta,len(raw))
 def test_no_arbitrary_fault_command(self):
  with self.assertRaises(ContractError):pool().set_lab_fault('c_offsets','; touch bad')

class ExecutorTests(unittest.TestCase):
 def test_explicit_fragment_profile_uses_four_independent_parsers(self):
  from fixtures import repair
  full=frame(bytes(range(32)));udp=full[42:82]
  profile=copy.deepcopy(POLICY);profile['rules'][0]['allow_fragments']=True
  for offset,payload,more in ((0,udp[:24],True),(24,udp[24:],False)):
   body=bytearray(full[8:42]+payload);body[16:18]=(20+len(payload)).to_bytes(2,'big')
   body[20:22]=((offset//8)|(8192 if more else 0)).to_bytes(2,'big')
   body=body.ljust(59,b'\0')+b'\x01';raw=repair(b'\x55'*7+b'\xd5'+body+b'\0'*4,True)
   results=[response(raw,eid,profile) for eid in SPECS]
   self.assertTrue(all(r['verdict']=='allow' for r in results))
   self.assertEqual(len({semantic_hash(r) for r in results}),1)
   self.assertEqual(bytes.fromhex(results[0]['payload_hex']),raw[22:42+len(payload)])
   for eid in SPECS:self.assertEqual(response(raw,eid)['reason'],'IP_FRAGMENT')
 def test_all_independent_golden_semantics(self):
  for eid in SPECS:
   for name,raw,want in vectors():
    with self.subTest(executor=eid,vector=name):self.assertEqual(want,semantic(response(raw,eid)))
 def test_random_valid_packets(self):
  rng=random.Random(1789)
  for size in [0,1,2,3,17,511,512,1470,1471,*[rng.randrange(1472) for _ in range(12)]]:
   payload=rng.randbytes(size);sn=rng.randrange(256);net=rng.choice(['A','B']);raw=frame(payload,sn,net)
   want=expected(raw,payload=payload,sn=sn,network=net)
   for eid in SPECS:self.assertEqual(want,semantic(response(raw,eid)))
 def test_differential_random_corruptions(self):
  rng=random.Random(619)
  for _ in range(32):
   b=bytearray(frame(rng.randbytes(rng.randrange(100))));pos=rng.randrange(len(b));b[pos]^=1<<rng.randrange(8)
   results=[semantic(response(bytes(b),e)) for e in SPECS]
   self.assertTrue(all(d==results[0] for d in results))
 def test_udp_zero_policy_is_explicit(self):
  p=copy.deepcopy(POLICY);p['rules'][0]['require_udp_checksum']=False;raw=change(frame(),48,b'\0\0')
  for eid in SPECS:self.assertEqual('allow',response(raw,eid,p)['verdict'])
 def test_mac_interface_difference_allowed(self):
  for eid in SPECS:
   self.assertEqual('allow',response(frame(network='A'),eid)['verdict']);self.assertEqual('allow',response(frame(network='B'),eid)['verdict'])
 def test_native_maximum_short_inputs(self):
  rng=random.Random(511)
  for size in [0,1,7,8,21,41,63,64,71,72,1526,1527,2048]:
   results=[semantic(response(rng.randbytes(size),e)) for e in SPECS];self.assertTrue(all(x==results[0] for x in results))
 def test_output_overflow_is_failure(self):
  p=pool();p.set_lab_fault('c_offsets','oversize');data,meta=request(frame(),POLICY,1,1)
  try:self.assertEqual('error',p.execute('c_offsets',data,meta,len(frame()),time.monotonic()+(15 if os.name=='nt' else 1))['status'])
  finally:p.set_lab_fault('c_offsets',None)
 def test_malformed_output_is_failure(self):
  p=pool();p.set_lab_fault('c_offsets','malformed');data,meta=request(frame(),POLICY,1,1)
  try:self.assertEqual('error',p.execute('c_offsets',data,meta,len(frame()),time.monotonic()+(15 if os.name=='nt' else 1))['status'])
  finally:p.set_lab_fault('c_offsets',None)
 def test_source_tamper_detected(self):
  p=pool();original=copy.deepcopy(p.info);p.info['source_hashes']['executors/python_struct.py']='0'*64
  try:
   with self.assertRaises(ContractError):p.verify()
  finally:p.info=original
 def test_binary_tamper_detected(self):
  p=pool();original=copy.deepcopy(p.info);p.info['binary_hashes']['c_offsets']='0'*64
  try:
   with self.assertRaises(ContractError):p.verify()
  finally:p.info=original

class ControllerTests(unittest.TestCase):
 def setUp(self):
  self.p=pool()
  for e in list(self.p.lab_faults):self.p.set_lab_fault(e,None)
  self.m=MimicPlugin(self.p,POLICY,mode='enforce',lab_seed=10,deadline_ms=5000 if os.name=='nt' else 500)
 def tearDown(self):
  for e in list(self.p.lab_faults):self.p.set_lab_fault(e,None)
 def test_healthy_quorum(self):self.assertTrue(self.m.evaluate(frame(),baseline=True)['final_allow'])
 def test_original_deny_never_overridden(self):self.assertFalse(self.m.evaluate(frame(),baseline=False)['final_allow'])
 def test_missing_baseline_is_unknown(self):self.assertIsNone(self.m.evaluate(frame())['final_allow'])
 def test_shadow_preserves_baseline(self):
  self.m.mode='shadow';bad=next(raw for n,raw,w in vectors() if n=='udp_length');r=self.m.evaluate(bad,baseline=True);self.assertEqual('deny',r['quorum']['semantic']['verdict']);self.assertTrue(r['final_allow'])
 def test_single_forged_allow_isolated_and_replaced(self):
  self.p.set_lab_fault('c_offsets','forged_allow');bad=next(raw for n,raw,w in vectors() if n=='udp_length');r=self.m.evaluate(bad,baseline=True)
  self.assertFalse(r['final_allow']);self.assertEqual(['c_offsets'],r['quorum']['dissenters']);self.assertIn('python_table',r['next_active']);self.assertGreater(r['next_generation'],r['meta']['generation'])
 def test_semantic_not_just_allow_compared(self):
  self.p.set_lab_fault('c_offsets','wrong_semantics');r=self.m.evaluate(frame(),baseline=True);self.assertTrue(r['final_allow']);self.assertEqual(['c_offsets'],r['quorum']['dissenters'])
 def test_stale_epoch_excluded(self):
  self.p.set_lab_fault('c_offsets','stale_epoch');r=self.m.evaluate(frame(),baseline=True);self.assertIn('c_offsets',r['quorum']['errors']);self.assertTrue(r['final_allow'])
 def test_stale_generation_excluded(self):
  self.p.set_lab_fault('c_offsets','stale_generation');r=self.m.evaluate(frame(),baseline=True);self.assertIn('c_offsets',r['quorum']['errors'])
 def test_wrong_input_hash_excluded(self):
  self.p.set_lab_fault('c_offsets','wrong_input');r=self.m.evaluate(frame(),baseline=True);self.assertIn('c_offsets',r['quorum']['errors'])
 def test_timeout_is_missing_vote(self):
  self.p.set_lab_fault('c_offsets','timeout');r=self.m.evaluate(frame(),baseline=True);self.assertTrue(r['final_allow']);self.assertEqual('timeout',next(x['status'] for x in r['worker_results'] if x['executor_id']=='c_offsets'))
 def test_two_failures_never_shrink_quorum(self):
  self.p.set_lab_fault('c_offsets','crash');self.p.set_lab_fault('cpp_cursor','crash');r=self.m.evaluate(frame(),baseline=True);self.assertFalse(r['final_allow']);self.assertEqual([],self.m.active)
  r=self.m.evaluate(frame(),baseline=True);self.assertFalse(r['final_allow']);self.assertEqual([],r['worker_results'])
 def test_common_mode_counterexample(self):
  self.p.set_lab_fault('c_offsets','forged_allow');self.p.set_lab_fault('cpp_cursor','forged_allow');bad=next(raw for n,raw,w in vectors() if n=='udp_length');r=self.m.evaluate(bad,baseline=True)
  self.assertEqual('allow',r['quorum']['semantic']['verdict']);self.assertTrue(r['final_allow']);self.assertIn('python_struct',self.m.quarantined)
 def test_recovery_requires_full_golden_test(self):
  self.p.set_lab_fault('c_offsets','forged_allow');bad=next(raw for n,raw,w in vectors() if n=='udp_length');self.m.evaluate(bad,baseline=True)
  self.assertEqual('failed',self.m.recover('c_offsets')['status']);self.assertIn('c_offsets',self.m.quarantined)
  self.p.set_lab_fault('c_offsets',None);self.assertEqual('passed',self.m.recover('c_offsets')['status']);self.assertNotIn('c_offsets',self.m.quarantined)
 def test_periodic_rotation_changes_active_subset(self):
  original=set(self.m.active)
  for _ in range(4):self.m.evaluate(frame())
  self.assertNotEqual(original,set(self.m.active));self.assertEqual(4,len(self.m.decisions))
 def test_unique_request_commits(self):
  a=self.m.evaluate(frame());b=self.m.evaluate(frame());self.assertNotEqual(a['meta']['request_id'],b['meta']['request_id']);self.assertEqual(2,len(self.m.decisions))
 def test_inflight_blocks_policy_and_recovery(self):
  self.m.lock.acquire()
  try:
   with self.assertRaises(ContractError):self.m.evaluate(frame())
   with self.assertRaises(ContractError):self.m.update_policy(dict(POLICY,epoch=4))
   with self.assertRaises(ContractError):self.m.recover('c_offsets')
  finally:self.m.lock.release()
 def test_policy_epoch_monotonic(self):
  with self.assertRaises(ContractError):self.m.update_policy(POLICY)
  self.m.update_policy(dict(POLICY,epoch=4));self.assertEqual(4,self.m.evaluate(frame())['meta']['epoch'])
 def test_invalid_budgets(self):
  for value in (0,True,5001):
   with self.assertRaises(ContractError):MimicPlugin(self.p,POLICY,deadline_ms=value)
 def test_duplicate_identity_never_two_votes(self):
  r=self.m.evaluate(frame())['worker_results'][0];q=adjudicate([r,r],self.m.active);self.assertEqual('no_quorum',q['status'])
 def test_two_active_executors_refused(self):
  with self.assertRaises(ContractError):adjudicate([],['python_struct','c_offsets'])
 def test_single_fault_position_enumeration(self):
  good=self.m.evaluate(frame())['worker_results'];wanted=semantic_hash(good[0]['response'])
  for i in range(3):
   for status in ('error','timeout','ok'):
    records=copy.deepcopy(good);records[i]['status']=status
    if status=='ok':records[i]['response']['fields'][2]^=1
    self.assertEqual(wanted,adjudicate(records,self.m.active)['semantic_sha256'])

class FilesAndBridgeTests(unittest.TestCase):
 def setUp(self):self.tmp=tempfile.TemporaryDirectory(dir=R/'reports');self.work=Path(self.tmp.name)
 def tearDown(self):self.tmp.cleanup()
 def clone(self):shutil.copytree(R/'cases/normal',self.work/'case');return self.work/'case'
 def test_case_traversal_denied(self):
  d=self.clone();m=json.loads((d/'case.json').read_text());m['frames'][0]['path']='../secret'
  (d/'case.json').write_text(json.dumps(m))
  with self.assertRaises(ContractError):case(d)
 def test_symlink_escape_denied(self):
  d=self.clone();(self.work/'secret').write_bytes(frame());(d/'normal_A.bin').unlink()
  try:(d/'normal_A.bin').symlink_to(self.work/'secret')
  except (OSError,NotImplementedError):self.skipTest('platform refuses symlink creation; path traversal tests remain active')
  with self.assertRaises(ContractError):case(d)
 def test_case_cannot_inject_lab_fault(self):
  d=self.clone();m=json.loads((d/'case.json').read_text());m['fault']='forged_allow';(d/'case.json').write_text(json.dumps(m))
  with self.assertRaises(ContractError):case(d)
 def test_run_and_audit(self):
  out=self.work/'run';r=run_case(R,R/'cases/normal',out,pool().build,pool=pool());self.assertTrue(r['input_integrity_ok']);self.assertEqual('PASS',verify(out)['status'])
 def test_report_tamper_detected(self):
  out=self.work/'run';run_case(R,R/'cases/normal',out,pool().build,pool=pool());(out/'report.md').write_text('forged')
  with self.assertRaises(ValueError):verify(out)
 def test_extra_nested_integrity_not_ignored(self):
  out=self.work/'run';run_case(R,R/'cases/normal',out,pool().build,pool=pool());(out/'extra').mkdir();(out/'extra/integrity.json').write_text('{}')
  with self.assertRaises(ValueError):verify(out)
 def test_modified_input_invalidates_conclusions(self):
  d=self.clone();original=MimicPlugin.evaluate
  def mutate(m,*a,**kw):
   r=original(m,*a,**kw);(d/'normal_A.bin').write_bytes(b'changed');return r
  with patch.object(MimicPlugin,'evaluate',mutate):r=run_case(R,d,self.work/'run',pool().build,pool=pool())
  self.assertFalse(r['input_integrity_ok']);self.assertFalse(r['conclusions_valid'])
 def test_export_uses_reference_binding_and_no_fake_metrics(self):
  out=self.work/'run';run_case(R,R/'cases/normal',out,pool().build,pool=pool());export_agent_case(out,self.work/'export');m=json.loads((self.work/'export/case.json').read_text())
  self.assertIsNone(m['observation']);self.assertTrue(all(a['binding']=='reference_fixture' for a in m['artifacts']));self.assertEqual('ok',inspect_mimic(out)['status'])
 def test_input_directory_cannot_be_output(self):
  d=self.clone()
  with self.assertRaises(ContractError):run_case(R,d,d/'run',pool().build,pool=pool())
 def test_external_case_cannot_enable_demo_injection(self):
  d=self.clone();m=json.loads((d/'case.json').read_text());m['source']='external_capture';(d/'case.json').write_text(json.dumps(m))
  with self.assertRaises(ContractError):run_case(R,d,self.work/'run',pool().build,scenario='single_fault',pool=pool())
 def test_all_cases_reproduce_exactly(self):
  root=self.work/'generated';root.mkdir()
  with contextlib.redirect_stdout(io.StringIO()):generate(root)
  for p in root.rglob('*'):
   if p.is_file():self.assertEqual((R/p.relative_to(root)).read_bytes(),p.read_bytes(),str(p.relative_to(root)))
 def test_invalidated_evidence_cannot_export(self):
  d=self.clone();original=MimicPlugin.evaluate
  def remove(m,*a,**kw):
   r=original(m,*a,**kw)
   if (d/'normal_A.bin').exists():(d/'normal_A.bin').unlink()
   return r
  with patch.object(MimicPlugin,'evaluate',remove):r=run_case(R,d,self.work/'run',pool().build,pool=pool())
  self.assertFalse(r['conclusions_valid'])
  with self.assertRaises(ContractError):export_agent_case(self.work/'run',self.work/'export')

if __name__=='__main__':unittest.main()
