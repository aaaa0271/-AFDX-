#!/usr/bin/env python3
"""Replace only the previous Assistant's temporal tool through its object attribute."""
import argparse
import sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from afdx_ai_hw.runtime import HardwareTemporalPlugin
from afdx_ai_hw.fixed import load_model,sha,read_json


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--extensions-root',required=True)
    parser.add_argument('--case',required=True)
    parser.add_argument('--out',required=True)
    parser.add_argument('--query',default='分析复合故障并给出证据报告')
    parser.add_argument('--backend',choices=('rtl','reference'),default='rtl')
    args=parser.parse_args()
    ext=Path(args.extensions_root).resolve()
    cfg,_=load_model()
    if sha(ext/'models/temporal.npz')!=cfg['source_model_sha256']:
        raise RuntimeError('extension source-model version mismatch')
    source=read_json(Path(args.case)/'case.json')['source']
    sys.path.insert(0,str(ext))
    from afdx_ext.assistant import Assistant
    from afdx_ext.common import InputError
    class BoundTemporalTool:
        def __init__(self):self.plugin=HardwareTemporalPlugin();self.next_id=1
        def analyze(self,history):
            result=self.plugin.analyze(history,backend=args.backend,job_id=self.next_id,measurement_source=source)
            self.next_id+=1
            if result['status']!='candidate':
                raise InputError('hardware temporal tool rejected measurement: '+','.join(result['errors']))
            return result
    assistant=Assistant()
    assistant.temporal=BoundTemporalTool()
    result=assistant.run(args.query,args.case,args.out)
    print('EXTENSION_AGENT_PASS',result['status'])


if __name__=='__main__':main()
