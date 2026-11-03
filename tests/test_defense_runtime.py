import sys
import unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'host'))
from defense_runtime import measured_window


class LiveMeasurementTests(unittest.TestCase):
    def samples(self):
        first=[0]*64;second=[0]*64
        for row in (first,second):row[0]=0x44454631;row[6]=1;row[7]=12500000
        first[1]=1;second[1]=2;second[2]=12500000
        second[5]=1
        second[8]=10;second[9]=10
        second[12]=20*80;second[14]=20*80*80
        second[16]=18;second[17]=18*1000;second[19]=18*1000*1000
        second[47]=10
        return first,second

    def test_missing_time_is_not_zero_imputed(self):
        first,second=self.samples();result=measured_window(first,second)
        self.assertIn('ntp_rtt_ms',result['missing']);self.assertNotIn('ntp_rtt_ms',result['metrics'])
        self.assertFalse(result['missing_values_imputed'])

    def test_physical_raw_counters(self):
        first,second=self.samples();result=measured_window(first,second)['metrics']
        self.assertEqual(result['observed_pps'],20)
        self.assertEqual(result['mean_frame_bytes'],80)
        self.assertEqual(result['frame_size_cv'],0)
        self.assertEqual(result['ab_unpaired_ratio'],0)
        self.assertEqual(result['arrival_cv'],0)

    def test_rtc_signed_offset_and_loading(self):
        first,second=self.samples();second[32]=8;second[40]=1
        second[36]=1<<31;second[38]=0;second[39]=0xffffffff
        second[41]=700;second[43]=1000
        result=measured_window(first,second)['metrics']
        self.assertEqual(result['ntp_rtt_ms'],500)
        self.assertEqual(result['ntp_offset_abs_ms'],1000)
        self.assertEqual(result['loader_progress_ratio'],.7)

    def test_epoch_boundary_rejected(self):
        first,second=self.samples();second[6]=2
        with self.assertRaises(ValueError):measured_window(first,second)

    def test_backward_utc_step_does_not_wrap(self):
        first,second=self.samples();first[5]=2
        result=measured_window(first,second)['metrics']
        self.assertEqual(result['clock_step_abs_ms'],2000)


if __name__=='__main__':unittest.main()
