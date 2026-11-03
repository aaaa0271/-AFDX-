import copy
import json
import tempfile
import unittest
from pathlib import Path
import numpy as np
from afdx_ai_hw.fixed import (ROOT, load_model, load_arrays, prepare_history,
    integer_tcn, decode_result, rshift_away, round_away, read_json)
from afdx_ai_hw.runtime import HardwareTemporalPlugin, csr_operations


class HostTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cfg, cls.p = load_model()
        cls.history = load_arrays(ROOT / 'source_model/data/test.npz')['X'][91].astype(float).tolist()

    def test_complete_history(self):
        qx, flags, outside = prepare_history(self.history, self.cfg, self.p)
        self.assertEqual(qx.shape, (8, 18))
        self.assertEqual(qx.dtype, np.int16)

    def test_missing_history(self):
        with self.assertRaises(ValueError): prepare_history(self.history[:-1], self.cfg, self.p)

    def test_missing_feature(self):
        with self.assertRaises(ValueError): prepare_history([r[:-1] for r in self.history], self.cfg, self.p)

    def test_transposed(self):
        with self.assertRaises(ValueError): prepare_history(np.array(self.history).T, self.cfg, self.p)

    def test_boolean(self):
        h = copy.deepcopy(self.history); h[0][0] = True
        with self.assertRaises(ValueError): prepare_history(h, self.cfg, self.p)

    def test_strings(self):
        h = copy.deepcopy(self.history); h[0][0] = '1'
        with self.assertRaises(ValueError): prepare_history(h, self.cfg, self.p)

    def test_nan(self):
        h = copy.deepcopy(self.history); h[0][0] = float('nan')
        with self.assertRaises(ValueError): prepare_history(h, self.cfg, self.p)

    def test_infinity(self):
        h = copy.deepcopy(self.history); h[0][0] = float('inf')
        with self.assertRaises(ValueError): prepare_history(h, self.cfg, self.p)

    def test_float32_overflow(self):
        h = copy.deepcopy(self.history); h[0][2] = 1e300
        with self.assertRaises(ValueError): prepare_history(h, self.cfg, self.p)

    def test_negative(self):
        h = copy.deepcopy(self.history); h[0][0] = -1
        with self.assertRaises(ValueError): prepare_history(h, self.cfg, self.p)

    def test_ratio_limits(self):
        for column in (4, 5, 6, 7, 12, 13, 14, 15, 16):
            for value in (0, 1):
                h = copy.deepcopy(self.history); h[0][column] = value
                prepare_history(h, self.cfg, self.p)
            h = copy.deepcopy(self.history); h[0][column] = 1.001
            with self.assertRaises(ValueError): prepare_history(h, self.cfg, self.p)

    def test_profile_limits(self):
        for col, value in ((0, 200001), (1, 63), (1, 1519)):
            h = copy.deepcopy(self.history); h[0][col] = value
            with self.assertRaises(ValueError): prepare_history(h, self.cfg, self.p)
        for col, value in ((0, 0), (0, 200000), (1, 64), (1, 1518)):
            h = copy.deepcopy(self.history); h[0][col] = value
            prepare_history(h, self.cfg, self.p)

    def test_out_of_support_flag(self):
        h = copy.deepcopy(self.history); h[0][10] = 1e20
        _, flags, outside = prepare_history(h, self.cfg, self.p)
        self.assertTrue(flags & 1)
        self.assertIn('ntp_offset_abs_ms', outside)

    def test_half_away_float(self):
        self.assertEqual(round_away(np.array([-2.5,-1.5,-.5,0,.5,1.5,2.5])).tolist(),[-3,-2,-1,0,1,2,3])

    def test_integer_rounding_exhaustive(self):
        x = np.arange(-65536, 65537, dtype=np.int64)
        # Independent quotient/remainder oracle, including negative half cases.
        for shift in range(16):
            d = 1 << shift
            quotient, remainder = np.divmod(np.abs(x), d)
            oracle = (quotient + (remainder * 2 >= d)) * np.sign(x)
            np.testing.assert_array_equal(rshift_away(x, shift), oracle)

    def test_threshold_boundary(self):
        for i, threshold in enumerate(self.p['thresholds_q']):
            a = np.full(9, -32768, dtype=np.int16)
            a[i] = threshold
            r = decode_result(a, 0, self.cfg, self.p)
            self.assertTrue(r['candidate_mask'] & (1 << i))
            a[i] = threshold - 1
            r = decode_result(a, 0, self.cfg, self.p)
            self.assertFalse(r['candidate_mask'] & (1 << i))

    def test_error_suppresses_decisions(self):
        for error in (1, 2, 4, 8, 16, 32, 64, 128, 65535):
            r = decode_result(np.full(9, 32767, np.int16), error, self.cfg, self.p)
            self.assertEqual(r['candidate_mask'], 0)
            self.assertFalse(r['warning'])
            self.assertIsNone(r['future_latency_max_p95_us'])

    def test_quantized_extremes(self):
        for value in (-32768, 32767):
            out, sat = integer_tcn(np.full((1,8,18),value,np.int16),self.cfg,self.p)
            self.assertEqual(out.dtype,np.int16)
            self.assertEqual(sat.shape,(1,))

    def test_quantized_float_rejected(self):
        with self.assertRaises(ValueError): integer_tcn(np.zeros((1,8,18)),self.cfg,self.p)

    def test_quantized_range_rejected(self):
        with self.assertRaises(ValueError): integer_tcn(np.full((1,8,18),32768),self.cfg,self.p)

    def test_reference_provenance(self):
        r = HardwareTemporalPlugin().analyze(self.history,backend='reference')
        self.assertEqual(r['source'],'integer_reference')
        self.assertFalse(r['hardware_timing_proof'])
        self.assertFalse(r['afdx_configuration_write'])

    def test_bad_job_id(self):
        for i in (-1,2**32,True,1.5):
            with self.assertRaises(ValueError): HardwareTemporalPlugin().analyze(self.history,backend='reference',job_id=i)

    def test_bad_backend(self):
        with self.assertRaises(ValueError): HardwareTemporalPlugin().analyze(self.history,backend='hardware')

    def test_bad_source(self):
        with self.assertRaises(ValueError): HardwareTemporalPlugin().analyze(self.history,backend='reference',measurement_source='certified')

    def test_csr_operations(self):
        ops = csr_operations(self.history)['operations']
        beats = [o for o in ops if o['op']=='write32' and o['addr']==32]
        self.assertEqual(len(beats),144)
        self.assertTrue(beats[-1]['value'] & (1<<16))
        self.assertTrue(all(not b['value'] & (1<<16) for b in beats[:-1]))
        self.assertEqual(ops[-1],dict(op='write32',addr=36,value=1))

    def test_duplicate_json(self):
        with tempfile.TemporaryDirectory(dir=ROOT/'reports') as d:
            p = Path(d)/'x.json'; p.write_text('{"x":1,"x":2}')
            with self.assertRaises(ValueError): read_json(p)

    def test_nonfinite_json(self):
        with tempfile.TemporaryDirectory(dir=ROOT/'reports') as d:
            p=Path(d)/'x.json'; p.write_text('[NaN]')
            with self.assertRaises(ValueError): read_json(p)


if __name__ == '__main__':
    unittest.main()
