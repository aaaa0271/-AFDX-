from pathlib import Path
import hashlib, json, re, sys, unittest
R=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(R/'vendor'))
from pysnmp.proto.api import v2c
from pyasn1.codec.ber import decoder,encoder
from run_all import check_project
class PackagingTests(unittest.TestCase):
 def test_filesets(self):self.assertEqual(check_project()['status'],'PASS')
 def test_integrated_defense_resources(self):
  self.assertIn('-name TOP_LEVEL_ENTITY AFDX_defense_top',(R/'ARINC.qsf').read_text(encoding='utf-8'))
  self.assertIn('<Option Id="TopModule">AFDX_defense_top</Option>',(R/'ARINC.epr').read_text(encoding='utf-8'))
  top=(R/'rtl/AFDX_defense_top.v').read_text(encoding='utf-8')
  for name in ('afdx_security_plugin','afdx_defense_gate','afdx_defense_control','AFDX_competition_top'):self.assertIn(name,top)
  for name in ('weights.mem','biases.mem','thresholds.mem','shifts.mem','ai_model_params.vh','afdx_ai_tcn_plugin.v'):self.assertTrue((R/'aihw_plugin/rtl'/name).is_file())
 def test_coverage_counts(self):
  tests=json.loads((R/'scripts/tests.json').read_text())
  want={'legacy':52,'contest':15,'completion':5,'foundation':8,'experimental':5,'datagram':7,'integration':2}
  self.assertGreaterEqual(len(tests),94);self.assertEqual(len({t['name'] for t in tests}),len(tests))
  for suite,count in want.items():self.assertGreaterEqual(sum(t['suite']==suite for t in tests),count)
  for t in tests:
   self.assertTrue((R/t['file']).is_file())
   for script,_ in t['auditors']:self.assertTrue((R/'scripts'/script).is_file())
 def test_test_resources(self):
  for p in (R/'tb').glob('*.v'):
   text=p.read_text(encoding='utf-8-sig')
   for x in re.findall(r'`include\s+"([^"]+)"|\$readmemh\s*\(\s*"([^"]+)"',text):
    name=next(v for v in x if v)
    self.assertEqual(name,Path(name).name)
    self.assertTrue((R/'tb'/name).is_file(),str(p)+': '+name)
 def test_vendor_import_and_roundtrip(self):
  vectors=json.loads((R/'tb/snmp_manager_vectors.json').read_text())
  self.assertTrue(vectors)
  for v in vectors:
   key=next((k for k in ('request_hex','hex') if k in v),None)
   if key:
    raw=bytes.fromhex(v[key]);obj,tail=decoder.decode(raw,asn1Spec=v2c.Message());self.assertFalse(tail);self.assertEqual(encoder.encode(obj),raw)
 def test_no_testbench_module_used_by_production(self):
  # Fence: experimental prototype files must never be reintroduced into tb/
  # under the afdx_* prefix (an earlier build convention). Asserting that the
  # set stays empty is an explicit isolation decision: if such a file is ever
  # added, this failure forces a review instead of silently widening the
  # production compile.
  self.assertEqual([p.name for p in (R/'tb').glob('afdx_*.v')],[])
  # Real closure check: production RTL must not reference any module that is
  # defined only inside testbench files (comments are stripped first).
  def defined(folder):
   names=set()
   for p in (R/folder).glob('*.v'):
    names.update(re.findall(r'\bmodule\s+(\w+)',p.read_text(encoding='utf-8-sig')))
   return names
  tb_only=defined('tb')-defined('rtl')
  self.assertTrue(tb_only)
  strip_comments=lambda s:re.sub(r'//[^\n]*|/\*.*?\*/','',s,flags=re.S)
  for p in (R/'rtl').glob('*.v'):
   body=strip_comments(p.read_text(encoding='utf-8-sig'))
   for name in tb_only:
    self.assertNotRegex(body,r'\b'+name+r'\b',str(p)+': '+name)
 def test_baseline_not_closed(self):
  b=json.loads((R/'docs/baseline.json').read_text())
  self.assertFalse(b['normative_inventory_complete']);self.assertFalse(b['formal_certificate_issued'])
if __name__=='__main__':unittest.main()

