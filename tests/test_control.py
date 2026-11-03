import sys,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'host'))
from policy import Rule
from control import preflight,transaction
from evidence import snapshot

class ControlTests(unittest.TestCase):
 def rule(self,**kw):return Rule(1,2,0x030000000010,0x020000000002,**kw)
 def test_ambiguous_prefix(self):
  with self.assertRaises(ValueError):preflight({0:self.rule(),1:self.rule(destination_port=7)})
 def test_distinct_udp_flow(self):
  self.assertEqual(preflight({0:self.rule(destination_port=7),1:self.rule(destination_port=8)})['status'],'PASS')
 def test_loader_dynamic_ports_overlap(self):
  with self.assertRaises(ValueError):preflight({0:self.rule(kind=2),1:self.rule(destination_port=7)})
 def test_no_old_shadow_leak(self):
  writes=transaction({0:self.rule()});d={w['address']:w['value'] for w in writes}
  self.assertEqual(d[0x140],0);self.assertEqual(d[0x1000],0);self.assertEqual(d[0x1780],0)
 def test_invalid_rule_rejected(self):
  with self.assertRaises(ValueError):self.rule(max_mac=1519).words()
 def test_evidence_not_ready(self):self.assertIsNone(snapshot(lambda a:0))
 def test_evidence_raw_and_normalized_difference(self):
  a=bytearray(72);b=bytearray(a);a[19]=0x22;b[19]=0x42;a[54]=3;b[54]=4
  regs={0x2000:1,0x2008:72,0x200c:72,0x2004:54,0x2028:5}
  for base,raw in ((0x2100,a),(0x2900,b)):
   for i in range(0,72,4):regs[base+i]=int.from_bytes(raw[i:i+4],'little')
  r=snapshot(lambda k:regs.get(k,0));self.assertEqual(r['differences'],[dict(wire_offset=54,first=3,second=4)])
  self.assertEqual(bytes.fromhex(r['first_wire_hex']),a);self.assertEqual(r['rule'],1)
if __name__=='__main__':unittest.main()
