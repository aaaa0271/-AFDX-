"""Synthetic verdict fixtures, not HDL or contest protocol evidence."""
from pathlib import Path
import copy,hashlib,json,tempfile,unittest
from check_competition import evaluate,IDS,REQUIRED_AUDITS
class CompetitionGateTests(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.r=Path(self.tmp.name);(self.r/'docs').mkdir();self.out=self.r/'run';self.out.mkdir()
  self.names=sorted(REQUIRED_AUDITS);self.tests=[]
  for name in self.names:
   audits=[]
   for script in sorted(REQUIRED_AUDITS[name]):
    log=self.out/(name+'_'+script+'.log');log.write_text('SYNTHETIC\n');audits.append(dict(script=script,exit=0,log=log.name))
   self.tests.append(dict(name=name,status='PASS',audits=audits))
  p=self.r/'docs/synthetic.jpg';p.write_bytes(b'SYNTHETIC source image, not contest publication')
  self.spec=dict(profile='synthetic-profile',scope='SYNTHETIC RECORD SELF-TEST ONLY',requirements=[dict(id=rid,name=rid,tests=self.names) for rid in sorted(IDS)],sources=[dict(path='docs/synthetic.jpg',sha256=hashlib.sha256(p.read_bytes()).hexdigest())])
  self.el=dict(status='PASS',errors=0,top='AFDX_defense_top',baseline=dict(status='PASS'));self.changed=[];self.full=True
 def run_gate(self):
  (self.r/'docs/competition_requirements.json').write_text(json.dumps(self.spec));return evaluate(self.r,self.out,self.tests,self.el,self.changed,self.full)
 def test_complete_synthetic_does_not_certify(self):
  r=self.run_gate();self.assertTrue(r['competition_prototype_complete']);self.assertFalse(r['formal_arinc_certification']);self.assertFalse(r['full_selected_standard_scope_complete'])
 def test_dual_domain_required(self):
  self.spec['required_service_domains']=2;self.assertFalse(self.run_gate()['competition_prototype_complete'])
  self.el['multi_domain']=dict(status='PASS',errors=0,service_domains=2);self.assertTrue(self.run_gate()['competition_prototype_complete'])
 def test_old_top_cannot_certify_defense(self):
  self.el['top']='AFDX_competition_top';self.assertFalse(self.run_gate()['competition_prototype_complete'])
 def test_missing_baseline(self):
  self.el.pop('baseline');self.assertFalse(self.run_gate()['competition_prototype_complete'])
 def test_partial_run(self):self.full=False;self.assertFalse(self.run_gate()['competition_prototype_complete'])
 def test_one_required_hdl_failure(self):self.tests[0]['status']='FAIL';self.assertFalse(self.run_gate()['competition_prototype_complete'])
 def test_missing_independent_audit(self):self.tests[0]['audits']=[];self.assertFalse(self.run_gate()['competition_prototype_complete'])
 def test_error_compiler(self):self.el['errors']=1;self.assertFalse(self.run_gate()['competition_prototype_complete'])
 def test_changed_inputs(self):self.changed=['rtl/example.v'];self.assertFalse(self.run_gate()['competition_prototype_complete'])
 def test_wrong_competition_image(self):(self.r/'docs/synthetic.jpg').write_bytes(b'changed');self.assertFalse(self.run_gate()['competition_prototype_complete'])
 def test_missing_goal(self):self.spec['requirements'].pop();self.assertFalse(self.run_gate()['competition_prototype_complete'])
 def test_duplicate_results(self):self.tests.append(copy.deepcopy(self.tests[0]));self.assertFalse(self.run_gate()['competition_prototype_complete'])
if __name__=='__main__':unittest.main()