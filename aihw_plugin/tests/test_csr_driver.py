import unittest
import numpy as np
from afdx_ai_hw.fixed import ROOT,load_model,load_arrays,prepare_history,integer_tcn
from afdx_ai_hw.csr import HardwareCsrPlugin


class FakeTransport:
    """Protocol fixture, not a substitute for the separately tested CSR RTL."""
    def __init__(self,tag,logits,flags,saturation):
        self.tag=tag;self.logits=logits;self.status=flags;self.saturation=saturation
        self.reg={};self.words=[];self.done=False;self.acked=False
        self.stuck=False;self.bad_id=False;self.bad_mask=False
    def read(self,addr):
        if addr==0:return 0x41494831
        if addr==4:return self.tag
        if addr==8:return 0 if self.stuck else (4 if self.done else 1)
        if addr==40:return self.reg[12]+int(self.bad_id)
        if addr==44:
            cfg,p=load_model();mask=sum(int(self.logits[i]>=p['thresholds_q'][i])<<i for i in range(8)) if self.status==0 else 0
            return self.status|(self.saturation<<16)|((mask^int(self.bad_mask))<<24)
        if addr==48:return 14035
        return int(self.logits[(addr-52)//4])&0xffff
    def write(self,addr,value):
        self.reg[addr]=value
        if addr==32:
            self.words.append(value)
            if value&(1<<16):self.done=True
        if addr==36:self.acked=True


class CsrDriverTests(unittest.TestCase):
    def setup_transport(self):
        cfg,p=load_model();h=load_arrays(ROOT/'source_model/data/test.npz')['X'][91]
        q,flags,_=prepare_history(h,cfg,p);out,sat=integer_tcn(q[None],cfg,p)
        errors=(16 if flags&1 else 0)|(32 if flags&2 or sat[0] else 0)
        return h,FakeTransport(int(cfg['model_tag'],16),out[0],errors,int(sat[0]))
    def test_normal_driver(self):
        h,t=self.setup_transport();r=HardwareCsrPlugin(t.read,t.write,source='rtl_simulation').analyze(h,42)
        self.assertEqual(r['job_id'],42);self.assertTrue(t.acked);self.assertEqual(len(t.words),144)
    def test_wrong_model(self):
        h,t=self.setup_transport();t.tag^=1
        with self.assertRaises(RuntimeError):HardwareCsrPlugin(t.read,t.write).analyze(h)
        self.assertFalse(t.words)
    def test_poll_timeout(self):
        h,t=self.setup_transport();t.stuck=True
        with self.assertRaises(TimeoutError):HardwareCsrPlugin(t.read,t.write,poll_budget=2).analyze(h)
    def test_wrong_job(self):
        h,t=self.setup_transport();t.bad_id=True
        with self.assertRaises(RuntimeError):HardwareCsrPlugin(t.read,t.write).analyze(h)
        self.assertFalse(t.acked)
    def test_wrong_mask(self):
        h,t=self.setup_transport();t.bad_mask=True
        with self.assertRaises(RuntimeError):HardwareCsrPlugin(t.read,t.write).analyze(h)
        self.assertFalse(t.acked)
    def test_invalid_uint32(self):
        h,t=self.setup_transport()
        with self.assertRaises(ValueError):HardwareCsrPlugin(lambda _:True,t.write).analyze(h)
    def test_transport_failure(self):
        h,t=self.setup_transport()
        with self.assertRaises(OSError):HardwareCsrPlugin(t.read,lambda *_:False).analyze(h)


if __name__=='__main__':unittest.main()
