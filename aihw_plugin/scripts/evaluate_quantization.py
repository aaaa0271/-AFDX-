#!/usr/bin/env python3
"""Evaluate the frozen float and bit-exact integer models on complete held-out splits."""
import sys
from pathlib import Path
import numpy as np
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / 'source_model'))
from afdx_ai_hw.fixed import load_model, load_arrays, round_away, integer_tcn, write_json
from afdx_ext.nn import tcn


def f1(y, pred):
    tp = np.sum((y == 1) & pred, axis=0)
    fp = np.sum((y == 0) & pred, axis=0)
    fn = np.sum((y == 1) & ~pred, axis=0)
    return np.divide(2 * tp, 2 * tp + fp + fn, out=np.zeros_like(tp, dtype=float), where=(2 * tp + fp + fn) != 0)


def metrics(labels, pred, latency, target):
    return dict(multilabel_macro_f1=float(f1(labels[:, :7], pred[:, :7]).mean()),
                warning_f1=float(f1(labels[:, 7], pred[:, 7])),
                warning_recall=float(pred[labels[:, 7] == 1, 7].mean()),
                warning_false_positive_rate=float(pred[labels[:, 7] == 0, 7].mean()),
                latency_mae_us=float(np.mean(np.abs(np.expm1(np.clip(latency, 0, 20)) - np.expm1(target)))))


def evaluate():
    cfg, q = load_model()
    p = load_arrays(ROOT / 'source_model/models/temporal.npz')
    report = dict(domain='held-out synthetic abstract packet-service traces',
                  source_weights_unchanged=True, model_tag=cfg['model_tag'],
                  quantization=f'post-training INT{cfg["weight_bits"]} weights / INT16 activations / INT48 accumulators',
                  quantization_scales_source='training maxima only; no test-label optimization',
                  test_used_in_initial_numeric_debugging=True, splits={})
    splits = ['validation', 'test', 'ood']
    if (ROOT / 'source_model/data/hardware_holdout.npz').exists():
        splits.append('hardware_holdout')
    for split in splits:
        d = load_arrays(ROOT / 'source_model/data' / (split + '.npz'))
        z = (np.log1p(d['X']) - p['mean']) / p['scale']
        float_out = tcn(p, z)
        raw = round_away(z.astype(np.float64) * (1 << cfg['q_input']))
        input_clip = np.any((raw < -32768) | (raw > 32767), axis=(1, 2))
        int_out, saturated = integer_tcn(np.clip(raw, -32768, 32767).astype(np.int16), cfg, q)
        output = int_out.astype(np.float64) / (1 << cfg['q_output'])
        int_pred = int_out[:, :8] >= q['thresholds_q']
        float_pred = float_out[:, :8] >= np.log(p['thresholds'] / (1 - p['thresholds']))
        in_support = ~np.any(np.abs(z) > 6, axis=(1, 2))
        valid = in_support & ~input_clip & (saturated == 0)
        results = dict(windows=len(z), scenario_groups=len(np.unique(d['group'])),
                       float=metrics(d['Y'], float_pred, float_out[:, 8] * p['reg_scale'] + p['reg_mean'], d['future_log_latency']),
                       integer_raw_all_windows=metrics(d['Y'], int_pred, output[:, 8] * p['reg_scale'] + p['reg_mean'], d['future_log_latency']),
                       input_saturated_windows=int(input_clip.sum()), arithmetic_saturated_windows=int((saturated != 0).sum()),
                       out_of_support_windows=int((~in_support).sum()), valid_windows=int(valid.sum()),
                       decision_agreement=float(np.mean(int_pred == float_pred)),
                       entire_window_decision_agreement=float(np.all(int_pred == float_pred, axis=1).mean()),
                       mean_abs_logit_error=float(np.mean(np.abs(output - float_out))),
                       max_abs_logit_error=float(np.max(np.abs(output - float_out))))
        if valid.any():
            results['integer_valid_windows_only'] = metrics(d['Y'][valid], int_pred[valid],
                output[valid, 8] * p['reg_scale'] + p['reg_mean'], d['future_log_latency'][valid])
        for name, subset in [('before_any_loss', (d['X'][:, -1, 7] == 0) & (d['Y'][:, 7] == 1)),
                             ('below_4pct_loss', (d['X'][:, -1, 7] < .04) & (d['Y'][:, 7] == 1))]:
            results['early_warning_' + name] = dict(windows=int(subset.sum()),
                raw_integer_recall=float(int_pred[subset, 7].mean()) if subset.any() else None,
                accepted_warning_recall=float((int_pred[subset, 7] & valid[subset]).mean()) if subset.any() else None)
        report['splits'][split] = results
    # Predeclared engineering acceptance: compare against same source float model, not an industrial target.
    report['acceptance'] = {'minimum_all_bit_agreement': .98, 'maximum_macro_f1_loss': .02,
                            'maximum_warning_f1_loss': .02, 'maximum_mae_relative_increase': .05}
    passed = all(s['decision_agreement'] >= .98 and
                 s['float']['multilabel_macro_f1'] - s['integer_raw_all_windows']['multilabel_macro_f1'] <= .02 and
                 s['float']['warning_f1'] - s['integer_raw_all_windows']['warning_f1'] <= .02 and
                 s['integer_raw_all_windows']['latency_mae_us'] <= s['float']['latency_mae_us'] * 1.05 and
                 s['input_saturated_windows'] == 0 and s['arithmetic_saturated_windows'] == 0
                 for s in report['splits'].values())
    report['acceptance']['passed'] = bool(passed)
    write_json(ROOT / 'reports/quantization_evaluation.json', report)
    print('QUANTIZATION_PASS' if passed else 'QUANTIZATION_FAIL', report['splits']['test'])
    if not passed:
        raise SystemExit(1)


if __name__ == '__main__':
    evaluate()
