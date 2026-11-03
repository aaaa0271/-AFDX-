#!/usr/bin/env python3
"""Fresh scenarios generated AFTER the deployed numerical contract is frozen."""
import sys
from pathlib import Path
import numpy as np
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / 'source_model'))
from afdx_ai_hw.fixed import load_model, sha, write_json, read_json
from afdx_ext.telemetry import trajectory


def main():
    cfg, _ = load_model()
    freeze = ROOT / 'reports/hardware_holdout_freeze.json'
    target = ROOT / 'source_model/data/hardware_holdout.npz'
    if freeze.exists():
        old = read_json(freeze)
        if old['frozen_model_manifest_sha256'] != sha(ROOT / 'models/model.json'):
            raise RuntimeError('holdout was already used with a different frozen model')
        if target.exists():
            if sha(target) != old['data_sha256']:
                raise RuntimeError('holdout bytes changed')
            print('HARDWARE_HOLDOUT_ALREADY_FROZEN')
            return
    info = dict(frozen_model_manifest_sha256=sha(ROOT / 'models/model.json'),
                model_tag=cfg['model_tag'], generated_after_precision_selection=True,
                input_to_training_or_quantization=False, seed_start=910000,
                reused_generator=True, domain='new synthetic scenarios, not real-board data')
    write_json(freeze, info)
    xs, ys, regs, groups, metadata = [], [], [], [], []
    for group in range(128):
        split = 'test' if group < 64 else 'ood'
        x, y, duration, m = trajectory(910000 + group, group, split)
        metadata.append(m)
        for t in range(7, 21):
            xs.append(x[t-7:t+1])
            ys.append(np.r_[y[t], float(np.max(x[t+1:t+4, 7]) >= .04)])
            regs.append(np.log1p(np.max(x[t+1:t+4, 8])))
            groups.append(group)
    np.savez_compressed(target, X=np.asarray(xs, dtype=np.float32), Y=np.asarray(ys, dtype=np.float32),
                        future_log_latency=np.asarray(regs, dtype=np.float32), group=np.asarray(groups, dtype=np.int32))
    write_json(ROOT / 'source_model/data/hardware_holdout_groups.json', metadata)
    info.update(data_sha256=sha(target), scenario_groups=len(metadata), windows=len(xs))
    write_json(freeze, info)
    print('HARDWARE_HOLDOUT_PASS', len(xs))


if __name__ == '__main__':
    main()
