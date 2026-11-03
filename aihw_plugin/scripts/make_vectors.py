#!/usr/bin/env python3
"""Model-derived vectors + exhaustive feature/time impulses + signed extremes."""
import sys
from pathlib import Path
import numpy as np
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from afdx_ai_hw.fixed import load_model, load_arrays, prepare_history, integer_tcn, write_json
from scripts.export_model import hex_file


def make_vectors():
    cfg, p = load_model()
    xs, flags, names = [], [], []
    splits = ['validation', 'test', 'ood']
    if (ROOT / 'source_model/data/hardware_holdout.npz').exists():
        splits.append('hardware_holdout')
    for split in splits:
        data = load_arrays(ROOT / 'source_model/data' / (split + '.npz'))
        for i in np.linspace(0, len(data['X']) - 1, 16, dtype=int):
            qx, flag, _ = prepare_history(data['X'][i], cfg, p)
            xs.append(qx); flags.append(flag); names.append(f'{split}_{i}')
    for time in range(8):
        for feature in range(18):
            for sign in (-1, 1):
                a = np.zeros((8, 18), dtype=np.int16)
                a[time, feature] = sign * 3072
                xs.append(a); flags.append(0); names.append(f'impulse_t{time}_f{feature}_{sign}')
    r = np.random.default_rng(819271)
    for i in range(24):
        xs.append(r.integers(-6144, 6145, size=(8, 18), dtype=np.int16))
        flags.append(0); names.append(f'random_integers_{i}')
    for value in (0, 1, -1, 32767, -32768):
        xs.append(np.full((8, 18), value, dtype=np.int16))
        flags.append(0); names.append(f'all_{value}')
    for i in range(4):
        xs.append(r.integers(-32768, 32768, size=(8, 18), dtype=np.int16))
        flags.append(0); names.append(f'full_range_{i}')
    # Explicit provenance/quality flags: computation retained, decisions suppressed.
    for flag in (1, 2, 3):
        xs.append(xs[0]); flags.append(flag); names.append(f'quality_flags_{flag}')
    x = np.stack(xs)
    logits, saturation, trace = integer_tcn(x, cfg, p, trace=True)
    status = np.array([(16 if f & 1 else 0) | (32 if f & 2 or s else 0)
                       for f, s in zip(flags, saturation)], dtype=np.uint16)
    mask = np.sum((logits[:, :8] >= p['thresholds_q']) * (1 << np.arange(8)), axis=1).astype(np.uint8)
    mask[status != 0] = 0
    out = ROOT / 'reports/vectors'
    out.mkdir(parents=True, exist_ok=True)
    for name, data, bits in [('inputs', x, 16), ('logits', logits, 16),
                             ('flags', flags, 16), ('status', status, 16),
                             ('mask', mask, 8), ('saturation', saturation, 8)]:
        hex_file(out / (name + '.mem'), data, bits)
    traces = np.concatenate([trace['h1'].reshape(-1, 128), trace['h2'].reshape(-1, 128), trace['rep']], axis=1)
    hex_file(out / 'trace.mem', traces, 16)
    (out / 'tb_vectors.vh').write_text(f'localparam integer VECTOR_COUNT = {len(x)};\n')
    write_json(out / 'manifest.json', dict(model_tag=cfg['model_tag'], count=len(x), names=names,
               numeric_vectors_are_not_real_measurements=True, intermediate_values_per_vector=288,
               arithmetic_saturation_vectors=int((saturation != 0).sum())))
    from afdx_ai_hw.fixed import rshift_away
    math_cases = []
    for shift in range(32):
        candidates = {0, 1, -1, (1 << 47)-1, -(1 << 47), 32767, -32768}
        for multiple in (0, 1, 7, 127):
            center = (multiple << shift) + ((1 << (shift-1)) if shift else 0)
            for delta in (-1, 0, 1):
                for sign in (-1, 1):
                    value = sign * (center + delta)
                    if -(1 << 47) <= value < (1 << 47):
                        candidates.add(value)
        math_cases += [(value, shift, int(rshift_away(value, shift))) for value in sorted(candidates)]
    for name, data, bits in [('math_values',[a for a,b,c in math_cases],48),
                             ('math_shifts',[b for a,b,c in math_cases],8),
                             ('math_expected',[c for a,b,c in math_cases],48)]:
        hex_file(out/(name+'.mem'),data,bits)
    (out/'tb_math.vh').write_text(f'localparam integer MATH_COUNT = {len(math_cases)};\n')
    write_json(out/'math_manifest.json',dict(cases=len(math_cases),shifts=list(range(32)),
               covers_negative_halves=True,covers_full_signed_48bit_extremes=True))
    print('VECTORS_PASS', len(x))
    return len(x)


if __name__ == '__main__':
    make_vectors()
