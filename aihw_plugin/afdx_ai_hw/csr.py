"""Driver for the independent local AI CSR bus, using caller-owned transport."""
import numpy as np
from .fixed import ROOT, load_model, prepare_history, decode_result


class HardwareCsrPlugin:
    def __init__(self, read32, write32, root=ROOT, poll_budget=10000, source='hardware'):
        if type(poll_budget) is not int or poll_budget <= 0:
            raise ValueError('positive poll budget required')
        if source not in ('hardware', 'rtl_simulation'):
            raise ValueError('transport source')
        self.cfg, self.p = load_model(root)
        self.read32, self.write32 = read32, write32
        self.poll_budget, self.source = poll_budget, source

    def read(self, addr):
        value = self.read32(addr)
        if type(value) is not int or not 0 <= value <= 0xffffffff:
            raise ValueError('transport returned invalid uint32')
        return value

    def write(self, addr, value):
        # Transport completes cfg_valid/cfg_ready or raises; it must have its own bus timeout.
        if self.write32(addr, value) is False:
            raise OSError('transport write failed')

    def wait_bit(self, mask):
        for _ in range(self.poll_budget):
            if self.read(8) & mask:
                return
        raise TimeoutError('AI CSR polling budget exhausted')

    def analyze(self, history, job_id=1):
        if type(job_id) is not int or not 0 <= job_id <= 0xffffffff:
            raise ValueError('job id')
        qx, flags, outside = prepare_history(history, self.cfg, self.p)
        if self.read(0) != 0x41494831 or self.read(4) != int(self.cfg['model_tag'], 16):
            raise RuntimeError('AI CSR identity/model mismatch')
        self.wait_bit(1)
        for addr, value in ((12,job_id),(16,int(self.cfg['model_tag'],16)),(20,0x3ffff),(24,flags),(28,1)):
            self.write(addr,value)
        for i,value in enumerate(qx.reshape(-1)):
            self.write(32,(int(value)&0xffff)|(int(i==143)<<16))
        self.wait_bit(4)
        ident, packed, cycles = self.read(40), self.read(44), self.read(48)
        logits = np.asarray([self.read(52+i*4)&0xffff for i in range(9)], dtype=np.uint16).view(np.int16)
        if ident != job_id or self.read(4) != int(self.cfg['model_tag'],16):
            raise RuntimeError('AI CSR result binding mismatch; result retained for investigation')
        errors, saturation, mask = packed&0xffff, (packed>>16)&7, packed>>24
        if packed & 0x00f80000 or errors & ~0x7f:
            raise RuntimeError('AI CSR reserved result bits')
        result = decode_result(logits, errors, self.cfg, self.p, job_id, cycles, self.source)
        if mask != result['candidate_mask'] or (cycles != self.cfg['compute_cycles'] and not errors):
            raise RuntimeError('AI CSR result validation failed')
        if saturation and not errors & 32:
            raise RuntimeError('AI CSR missing saturation error')
        self.write(36,1)
        result.update(saturation_layers=saturation,outside_features=outside,preprocessing_on_host=True)
        return result
