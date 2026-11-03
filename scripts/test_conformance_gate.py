"""Synthetic gate tests; passing these is NOT protocol or certification evidence."""
from pathlib import Path
import copy
import json
import tempfile
import unittest
from check_conformance import digest, evaluate, PINNED


class GateTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        (self.root/'rtl').mkdir()
        (self.root/'rtl/design.v').write_text('module example; endmodule\n')
        (self.root/'standard.txt').write_text('SYNTHETIC standard fixture, not an ARINC publication')
        (self.root/'review.txt').write_text('SYNTHETIC reviewed-record fixture')
        (self.root/'raw.log').write_text('SYNTHETIC_PASS\n')
        review = dict(status='APPROVED', reviewer='test-fixture', evidence=self.ref('review.txt'))
        self.baseline = dict(core_standard='ARINC664P7-1', normative_inventory_complete=True,
                             inventory_review=review, cross_revision_review=copy.deepcopy(review),
                             standards=[dict(id=identifier, full_text_available=True,
                                             full_text_path='standard.txt', full_text_sha256=digest(self.root/'standard.txt')) for identifier in sorted(PINNED)])
        receipt = dict(requirement_id='REQ-1', verdict='PASS',
                       source_hashes={'rtl/design.v':digest(self.root/'rtl/design.v')}, raw_log=self.ref('raw.log'))
        (self.root/'receipt.json').write_text(json.dumps(receipt))
        self.rows = [dict(id='REQ-1', source_ids=['ARINC664P7-1'], status='VERIFIED',
                          source_locator='Synthetic section1', locator_verified=True,
                          applicability_review=copy.deepcopy(review), test_evidence=[self.ref('receipt.json')])]

    def ref(self, name):
        return dict(path=name, sha256=digest(self.root/name))

    def result(self):
        return evaluate(self.root, self.baseline, self.rows)

    def test_complete_synthetic_records_never_issue_certificate(self):
        result = self.result()
        self.assertTrue(result['conformance_pass'])
        self.assertFalse(result['formal_certificate_issued'])

    def test_existing_functional_pass_does_not_close_open_requirements(self):
        self.baseline['current_functional_test_count'] = 76
        self.rows[0]['status'] = 'TESTED'
        self.assertFalse(self.result()['conformance_pass'])

    def test_inventory_flag_is_not_review(self):
        self.baseline['inventory_review'] = {'status':'OPEN'}
        self.assertFalse(self.result()['conformance_pass'])

    def test_incomplete_inventory(self):
        self.baseline['normative_inventory_complete'] = False
        self.assertFalse(self.result()['conformance_pass'])

    def test_catalog_is_not_normative_full_text(self):
        self.baseline['standards'][0]['full_text_available'] = False
        self.assertFalse(self.result()['conformance_pass'])

    def test_empty_inventory(self):
        self.rows = []
        self.assertEqual(self.result()['status'], 'INVALID')

    def test_duplicate_requirement(self):
        self.rows.append(copy.deepcopy(self.rows[0]))
        self.assertEqual(self.result()['status'], 'INVALID')

    def test_unknown_standard(self):
        self.rows[0]['source_ids'] = ['INVENTED']
        self.assertEqual(self.result()['status'], 'INVALID')

    def test_invalid_status(self):
        self.rows[0]['status'] = 'PASS'
        self.assertEqual(self.result()['status'], 'INVALID')

    def test_no_normative_locator(self):
        self.rows[0]['locator_verified'] = False
        self.assertFalse(self.result()['conformance_pass'])

    def test_changed_rtl(self):
        (self.root/'rtl/design.v').write_text('module changed; endmodule\n')
        self.assertFalse(self.result()['conformance_pass'])

    def test_added_rtl_not_in_evidence(self):
        (self.root/'rtl/added.v').write_text('module added; endmodule\n')
        self.assertFalse(self.result()['conformance_pass'])

    def test_modified_raw_log(self):
        (self.root/'raw.log').write_text('different\n')
        self.assertFalse(self.result()['conformance_pass'])

    def test_missing_pass_receipt(self):
        self.rows[0]['test_evidence'] = []
        self.assertFalse(self.result()['conformance_pass'])

    def test_na_needs_review_and_rationale(self):
        self.rows[0]['status'] = 'NOT_APPLICABLE'
        self.assertFalse(self.result()['conformance_pass'])
        self.rows[0]['not_applicable_reason'] = 'Synthetic fixture rationale'
        self.assertTrue(self.result()['conformance_pass'])
        self.rows[0]['applicability_review'] = None
        self.assertFalse(self.result()['conformance_pass'])

    def test_external_path_rejected(self):
        self.rows[0]['test_evidence'][0]['path'] = '../outside.json'
        self.assertFalse(self.result()['conformance_pass'])


if __name__ == '__main__':
    unittest.main()