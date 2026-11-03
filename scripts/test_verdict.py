import unittest
from verdict import verdict
class VerdictTests(unittest.TestCase):
 def setUp(self):self.text='# Errors: 0, Warnings: 0\n# UNIT_PASS\n# ** Note: $finish\nREGRESSION_FINAL_ERRORS=0\n'
 def test_positive(self):self.assertEqual(verdict(self.text,0,'UNIT_PASS')[0],'PASS')
 def test_fail_closed(self):
  for text,code in [(self.text,2),(self.text.replace('UNIT_PASS',''),0),(self.text.replace('REGRESSION_FINAL_ERRORS=0','REGRESSION_FINAL_ERRORS=1'),0),(self.text.replace('$finish',''),0),(self.text+'\nFAIL corrupted packet\n',0),(self.text+'\n** Error: failed compilation\n',0),(self.text+'\nDUT_TIMEOUT\n',0),(self.text+'\nerrors=2\n',0)]:
   with self.subTest(text=text,code=code):self.assertEqual(verdict(text,code,'UNIT_PASS')[0],'FAIL')
if __name__=='__main__':unittest.main()