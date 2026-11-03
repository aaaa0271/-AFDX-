#!/usr/bin/env python3
"""Re-run the original training program in isolation; never overwrite released weights."""
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
import numpy as np
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from afdx_ai_hw.fixed import load_arrays, write_json


def main():
    env = dict(os.environ, OPENBLAS_NUM_THREADS='1', OMP_NUM_THREADS='1')
    with tempfile.TemporaryDirectory(prefix='retrain_',dir=ROOT/'reports') as directory:
        target = Path(directory)
        for name in ('afdx_ext','scripts','data'):
            shutil.copytree(ROOT/'source_model'/name,target/name,ignore=shutil.ignore_patterns('__pycache__'))
        (target/'models').mkdir(); (target/'reports').mkdir()
        with (ROOT/'reports/training_reproduction.log').open('w') as log:
            r=subprocess.run([sys.executable,str(target/'scripts/train_temporal.py')],cwd=target,env=env,
                             stdout=log,stderr=subprocess.STDOUT,timeout=600)
        if r.returncode:
            raise RuntimeError('training failed; see reports/training_reproduction.log')
        expected=load_arrays(ROOT/'source_model/models/temporal.npz')
        actual=load_arrays(target/'models/temporal.npz')
        differences={k:float(np.max(np.abs(expected[k].astype(float)-actual[k].astype(float)))) for k in expected}
        result=dict(passed=all(v==0 for v in differences.values()),maximum_array_differences=differences,
                    source_weights_overwritten=False,scope='same NumPy/sklearn runtime; no cross-platform bit identity promise')
        write_json(ROOT/'reports/training_reproduction.json',result)
        if not result['passed']:raise RuntimeError('retrained arrays differ')
        print('TRAINING_REPRODUCTION_PASS')


if __name__=='__main__':main()
