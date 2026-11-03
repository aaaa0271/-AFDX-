"""Recovery regressions: snapshots are synthetic transport fixtures, not RTL evidence."""
import copy
import sys
import threading
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'host'))
from defense_runtime import DefenseRuntime, measured_window, FEATURES
import test_defense_runtime as fixtures

class WindowRecoveryTests(unittest.TestCase):
    def snapshot(self,n,epoch=1):
        row=[0]*64
        row[0]=0x44454631;row[1]=n+1;row[2]=n*12500000
        row[5]=n;row[6]=epoch;row[7]=12500000
        row[8]=10*n;row[9]=10*n;row[12]=20*80*n;row[14]=20*80*80*n
        row[16]=18*n;row[17]=18*1000*n;row[19]=18*1000*1000*n
        row[32]=8;row[36]=1<<20;row[40]=1;row[47]=10*n
        return row

    def runtime(self,rows):
        r=DefenseRuntime.__new__(DefenseRuntime)
        r.snapshot=Mock(side_effect=rows)
        r.read32=Mock(return_value=0)
        r.ai=SimpleNamespace(analyze=Mock(return_value={'status':'normal'}))
        r.history=[];r.last_snapshot=None;r.last_inference=None
        r.last_window_seconds=None;r.last_window_capture=None;r.last_measurement_issue=None
        r.window_records=[];r.multiplexed_rules=set()
        r.declared_policy={'epoch':1}
        r.mimic=SimpleNamespace(lock=threading.Lock(),policy={'epoch':1})
        return r

    def collect(self,r):
        r.window_records=[{'raw':b'actual_window_fixture','latency':100}]
        return r.collect_window()

    def test_short_abnormal_frames_raise_value_error_not_division_by_zero(self):
        a,b=fixtures.LiveMeasurementTests().samples();b[12]=0;b[14]=0
        with self.assertRaisesRegex(ValueError,'frames_without_measured_bytes'):measured_window(a,b)

    def test_invalid_window_clears_prior_result_and_recovers(self):
        bad=self.snapshot(2);bad[12]=self.snapshot(1)[12];bad[14]=self.snapshot(1)[14]
        r=self.runtime([self.snapshot(0),self.snapshot(1),bad,self.snapshot(3)])
        self.collect(r);self.collect(r);r.last_inference={'stale':True}
        result=self.collect(r)
        self.assertEqual(result['status'],'invalid_measurements')
        self.assertFalse(result['inference_submitted']);self.assertIsNone(r.last_inference)
        self.assertEqual(r.history,[]);self.assertIsNone(r.last_window_capture)
        self.assertEqual(self.collect(r)['inference']['samples'],1)
        r.ai.analyze.assert_not_called()

    def test_missing_window_requires_eight_new_contiguous_samples(self):
        missing=self.snapshot(4);missing[40]=0
        rows=[self.snapshot(n) for n in range(4)]+[missing]+[self.snapshot(n) for n in range(5,13)]
        r=self.runtime(rows)
        for _ in range(4):self.collect(r)
        r.last_inference={'stale':True}
        result=self.collect(r)
        self.assertEqual(result['status'],'incomplete_measurements');self.assertEqual(r.history,[])
        self.assertIsNone(r.last_inference);self.assertIsNone(r.last_window_capture)
        for n in range(1,8):
            result=self.collect(r)
            self.assertEqual(result['status'],'warming_up');self.assertEqual(len(r.history),n)
        r.ai.analyze.assert_not_called()
        self.assertEqual(self.collect(r)['status'],'normal')
        r.ai.analyze.assert_called_once()

    def test_unacknowledged_epoch_does_not_infer(self):
        r=self.runtime([self.snapshot(0),self.snapshot(1),self.snapshot(2,2),self.snapshot(3,2)])
        self.collect(r);self.collect(r);r.last_inference={'stale':True}
        for _ in range(2):
            self.assertEqual(self.collect(r)['status'],'policy_transition_required')
            self.assertEqual(r.history,[]);self.assertIsNone(r.last_inference)
        r.ai.analyze.assert_not_called()

    def test_committed_epoch_acknowledgment_rebuilds_baseline(self):
        rule=dict(id=0,peer_ip=0x0a000020,local_ip=0x0a000010,rx_mac=0x030000000040,
                  peer_mac=0x020000000002,source_port=10000,destination_port=20000,max_mac=1518,require_udp_checksum=False)
        r=self.runtime([self.snapshot(0),self.snapshot(1),self.snapshot(2,2),self.snapshot(3,2)])
        self.collect(r);self.collect(r)
        r.acknowledge_policy({'schema':1,'epoch':2,'rules':[rule]})
        self.assertEqual(r.declared_policy['epoch'],2);self.assertEqual(r.history,[])
        result=self.collect(r)
        self.assertEqual(result['status'],'warming_up');self.assertEqual(len(r.history),1)

    def test_policy_must_match_rtl_and_pending_frame_must_drain(self):
        r=self.runtime([self.snapshot(0,2)])
        rule=dict(id=0,peer_ip=1,local_ip=2,rx_mac=3,peer_mac=4,source_port=1,destination_port=2,max_mac=1518,require_udp_checksum=False)
        with self.assertRaisesRegex(ValueError,'epoch'):
            r.acknowledge_policy({'schema':1,'epoch':1,'rules':[rule]})
        r.read32.return_value=1
        with self.assertRaisesRegex(RuntimeError,'pending'):
            r.acknowledge_policy({'schema':1,'epoch':2,'rules':[rule]})

    def test_snapshot_failure_invalidates_baseline(self):
        r=self.runtime([self.snapshot(0),OSError('bus timeout'),self.snapshot(2),self.snapshot(3)])
        self.collect(r);r.last_inference={'stale':True}
        with self.assertRaises(OSError):self.collect(r)
        self.assertIsNone(r.last_snapshot);self.assertIsNone(r.last_inference)
        self.assertEqual(self.collect(r)['samples'],0)
        self.assertEqual(self.collect(r)['inference']['samples'],1)

    def test_nonfinite_direct_measurement_breaks_history(self):
        r=self.runtime([])
        metrics={key:0.0 for key in FEATURES};metrics[FEATURES[0]]=float('nan')
        r.history=[{'stale':True}];r.last_inference={'stale':True}
        with self.assertRaisesRegex(ValueError,'finite'):r.append_measurement(metrics,{k:'sensor' for k in FEATURES})
        self.assertEqual(r.history,[]);self.assertIsNone(r.last_inference)

if __name__=='__main__':unittest.main()
