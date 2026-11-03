#!/usr/bin/env python3
import shutil
import sys
import tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from afdx_ai_hw.fixed import load_model,sha,write_json
from scripts.export_model import export


def main():
    cfg,_=load_model()
    with tempfile.TemporaryDirectory(prefix='export_',dir=ROOT/'reports') as directory:
        tmp=Path(directory)
        for name in ('source_model/models','source_model/data','source_model/afdx_ext','models','rtl','reports'):
            (tmp/name).mkdir(parents=True,exist_ok=True)
        for name in ('source_model/models/temporal.npz','source_model/data/train.npz'):
            shutil.copy2(ROOT/name,tmp/name)
        for name in ('__init__.py','common.py','nn.py'):
            shutil.copy2(ROOT/'source_model/afdx_ext'/name,tmp/'source_model/afdx_ext'/name)
        export(tmp,weight_bits=cfg['weight_bits'])
        differences=[f for f in [*cfg['artifacts'],'models/model.json'] if sha(ROOT/f)!=sha(tmp/f)]
        result=dict(passed=not differences,different_files=differences,source_weights_overwritten=False)
        write_json(ROOT/'reports/export_reproduction.json',result)
        if differences:raise RuntimeError('export not reproducible')
        print('EXPORT_REPRODUCTION_PASS')


if __name__=='__main__':main()
