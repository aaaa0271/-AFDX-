import unittest
from prove_worst_case_envelope import verify, wire_ns, fragment_count
class EnvelopeTests(unittest.TestCase):
 def test_length_is_not_ignored(self):
  self.assertEqual(wire_ns(64),6720)
  self.assertEqual(wire_ns(1518),123040)
  self.assertNotEqual(wire_ns(64),wire_ns(1518))
 def test_fragment_known_answers(self):
  self.assertEqual(fragment_count(8192,64),342)
  self.assertEqual(fragment_count(8192,1518),6)
  self.assertEqual(fragment_count(17,64),1)
  self.assertEqual(fragment_count(18,64),2)
 def test_claim_boundaries(self):
  r=verify()
  self.assertEqual(r['enumeration']['bag_assignments'],8**6)
  self.assertEqual(r['wire_capacity']['max_utilization_exact'],'2307/3125')
  self.assertGreater(r['refutations'][0]['completion_lower_bound_ns'],384738240)
  self.assertFalse(r['ideal_link_theorem']['rtl_service_curve_established'])
  self.assertFalse(r['full_worst_case_proof'])
if __name__=='__main__':unittest.main()