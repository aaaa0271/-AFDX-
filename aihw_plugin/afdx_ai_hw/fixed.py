"""Integer reference for the RTL. No floating-point inference in integer_tcn."""
from pathlib import Path
import hashlib
import json
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
FEATURES = ['observed_pps', 'mean_frame_bytes', 'frame_size_cv', 'arrival_cv',
            'ab_unpaired_ratio', 'ab_payload_mismatch_ratio', 'fcs_error_ratio',
            'queue_overflow_ratio', 'latency_p95_us', 'ntp_rtt_ms',
            'ntp_offset_abs_ms', 'clock_step_abs_ms', 'loader_progress_ratio',
            'loader_retry_ratio', 'fragment_orphan_ratio', 'management_fraction',
            'active_context_ratio', 'sha_jobs_per_1k_frames']
CAUSES = ['congestion', 'link_degradation', 'replica_divergence', 'time_anomaly',
          'loader_stall', 'fragment_pressure', 'management_burst']
ERRORS = {0: 'frame_length', 1: 'missing_features', 2: 'model_mismatch',
          3: 'input_timeout', 4: 'out_of_support', 5: 'numeric_saturation',
          6: 'unsupported_job_flags'}


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def read_json(path):
    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                raise ValueError('duplicate JSON key')
            result[key] = value
        return result
    return json.loads(Path(path).read_text(), object_pairs_hook=pairs,
                      parse_constant=lambda _: (_ for _ in ()).throw(ValueError('nonfinite JSON')))


def write_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False, allow_nan=False) + '\n')


def load_arrays(path):
    with np.load(path, allow_pickle=False) as z:
        result = {k: z[k].copy() for k in z.files}
    if any(a.dtype.kind not in 'fiu' or not np.isfinite(a).all() for a in result.values()):
        raise ValueError('nonfinite or nonnumeric model array')
    return result


def round_away(x):
    """Round to nearest; exact half rounds away from zero."""
    x = np.asarray(x)
    return np.copysign(np.floor(np.abs(x) + 0.5), x).astype(np.int64)


def rshift_away(x, shift):
    x = np.asarray(x, dtype=np.int64)
    shift = np.asarray(shift, dtype=np.int64)
    if np.any(shift < 0) or np.any(shift > 31):
        raise ValueError('unsupported shift')
    offset = np.where(shift == 0, 0, 1 << np.maximum(shift - 1, 0))
    mag = (np.abs(x) + offset) >> shift
    return np.where(x < 0, -mag, mag)


def load_model(root=ROOT):
    root = Path(root)
    cfg = read_json(root / 'models/model.json')
    artifact_names = {'models/quantized.npz', 'rtl/ai_model_params.vh',
                      'rtl/weights.mem', 'rtl/biases.mem', 'rtl/thresholds.mem', 'rtl/shifts.mem'}
    if set(cfg['artifacts']) != artifact_names or cfg['weight_bits'] not in (8, 16):
        raise ValueError('model manifest contract')
    for name in ('q_input', 'q_h1', 'q_h2', 'q_output'):
        if type(cfg[name]) is not int or not 0 <= cfg[name] <= 15:
            raise ValueError('invalid binary point')
    if len(cfg['shifts']) != 3 or any(len(a) != n for a, n in zip(cfg['shifts'], (16, 16, 9))):
        raise ValueError('shift shape')
    if any(type(v) is not int or not 0 <= v <= 31 for a in cfg['shifts'] for v in a):
        raise ValueError('shift range')
    for relative, expected in cfg['artifacts'].items():
        if relative not in ('models/quantized.npz', 'rtl/ai_model_params.vh',
                            'rtl/weights.mem', 'rtl/biases.mem', 'rtl/thresholds.mem', 'rtl/shifts.mem'):
            raise ValueError('invalid artifact path')
        if sha(root / relative) != expected:
            raise ValueError('model artifact hash mismatch: ' + relative)
    p = load_arrays(root / 'models/quantized.npz')
    expected = {'K1': (3, 18, 16), 'b1': (16,), 'K2': (3, 16, 16),
                'b2': (16,), 'W': (32, 9), 'b': (9,), 'thresholds_q': (8,),
                'mean': (18,), 'scale': (18,), 'reg_mean': (), 'reg_scale': (), 'radius': ()}
    if set(p) != set(expected) or any(p[k].shape != shape for k, shape in expected.items()):
        raise ValueError('model shape mismatch')
    for k in ('K1', 'K2', 'W'):
        limit = (1 << (cfg['weight_bits'] - 1)) - 1
        if p[k].dtype.kind not in 'iu' or np.any(p[k] < -limit) or np.any(p[k] > limit):
            raise ValueError('weight type/range')
    if np.any(p['scale'] <= 0):
        raise ValueError('normalization scale')
    for k in ('b1', 'b2', 'b'):
        if p[k].dtype.kind not in 'iu' or np.any(p[k] < -(1 << 31)) or np.any(p[k] >= (1 << 31)):
            raise ValueError('bias type/range')
    if p['thresholds_q'].dtype.kind not in 'iu' or np.any(np.abs(p['thresholds_q'].astype(np.int64)) > 32767):
        raise ValueError('threshold type/range')
    return cfg, p


def prepare_history(history, cfg, p):
    def has_bool(value):
        if isinstance(value, (bool, np.bool_)):
            return True
        if isinstance(value, (list, tuple)):
            return any(has_bool(v) for v in value)
        return False
    if has_bool(history):
        raise ValueError('boolean measurement')
    a = np.asarray(history)
    if a.shape != (8, 18) or a.dtype.kind not in 'fi' or not np.isfinite(a).all():
        raise ValueError('history must contain exactly 8x18 finite numeric measurements')
    with np.errstate(over='ignore'):
        x = a.astype(np.float32)
    if not np.isfinite(x).all() or np.any(x < 0):
        raise ValueError('negative or unrepresentable measurement')
    if np.any(x[:, (4, 5, 6, 7, 12, 13, 14, 15, 16)] > 1):
        raise ValueError('ratio outside [0,1]')
    if np.any(x[:, 0] > 200000) or np.any(x[:, 1] < 64) or np.any(x[:, 1] > 1518):
        raise ValueError('unsupported rate or frame length')
    z = (np.log1p(x) - p['mean']) / p['scale']
    outside = np.flatnonzero(np.max(np.abs(z), axis=0) > 6)
    rounded = round_away(z.astype(np.float64) * (1 << cfg['q_input']))
    clipped = bool(np.any((rounded < -32768) | (rounded > 32767)))
    flags = int(bool(len(outside))) | (int(clipped) << 1)
    return np.clip(rounded, -32768, 32767).astype(np.int16), flags, [FEATURES[i] for i in outside]


def integer_tcn(qx, cfg, p, trace=False):
    """Batch integer convolution, matching every rounding boundary in RTL.

    Returns raw Q-output logits and per-window saturation bitmask:
    bit 0=conv1, bit 1=conv2, bit 2=final dense layer.
    """
    qx = np.asarray(qx)
    if qx.dtype.kind not in 'iu' or qx.ndim != 3 or qx.shape[1:] != (8, 18):
        raise ValueError('quantized input shape/type')
    if np.any(qx < -32768) or np.any(qx > 32767):
        raise ValueError('quantized input range')
    x = qx.astype(np.int64)
    sat = np.zeros(len(x), dtype=np.uint8)
    layers = []
    for layer, dilation in ((1, 1), (2, 2)):
        w = p['K' + str(layer)].astype(np.int64)
        b = p['b' + str(layer)].astype(np.int64)
        accum = np.broadcast_to(b, (len(x), 8, 16)).copy()
        for k in range(3):
            offset = k * dilation
            if offset == 0:
                accum += x @ w[k]
            else:
                accum[:, offset:] += x[:, :-offset] @ w[k]
        rounded = rshift_away(accum, cfg['shifts'][layer - 1])
        sat |= np.any(rounded > 32767, axis=(1, 2)).astype(np.uint8) << (layer - 1)
        x = np.clip(rounded, 0, 32767)
        layers.append(x.copy())
    pooled = rshift_away(x.sum(axis=1), 3)
    rep = np.concatenate([x[:, -1], pooled], axis=1)
    acc = rep @ p['W'].astype(np.int64) + p['b'].astype(np.int64)
    rounded = rshift_away(acc, cfg['shifts'][2])
    sat |= np.any((rounded < -32768) | (rounded > 32767), axis=1).astype(np.uint8) << 2
    out = np.clip(rounded, -32768, 32767).astype(np.int16)
    if trace:
        return out, sat, dict(h1=layers[0], h2=layers[1], rep=rep)
    return out, sat


def decode_result(logits, errors, cfg, p, job_id=0, cycles=None, source='integer_reference'):
    a = np.asarray(logits)
    if a.shape != (9,) or a.dtype.kind not in 'iu' or np.any(a < -32768) or np.any(a > 32767):
        raise ValueError('result logits')
    if type(errors) is not int or not 0 <= errors <= 0xffff:
        raise ValueError('result errors')
    if source not in ('integer_reference', 'rtl_simulation', 'hardware'):
        raise ValueError('source declaration')
    out = a.astype(np.float64) / (1 << cfg['q_output'])
    scores = 1 / (1 + np.exp(-np.clip(out[:8], -40, 40)))
    mask = a[:8].astype(np.int64) >= p['thresholds_q']
    log_latency = np.clip(out[8] * float(p['reg_scale']) + float(p['reg_mean']), 0, 20)
    valid = errors == 0
    return dict(schema=1, status='candidate' if valid else 'invalid_measurement',
                job_id=int(job_id), model_tag=cfg['model_tag'], source=source,
                errors=[name for bit, name in ERRORS.items() if errors & (1 << bit)],
                unknown_error_bits=int(errors & ~0x7f), raw_logits_q=a.astype(int).tolist(),
                cause_scores={c: float(scores[i]) for i, c in enumerate(CAUSES)},
                compound_candidates=[dict(cause=c, score=float(scores[i])) for i, c in enumerate(CAUSES) if valid and mask[i]],
                warning=bool(valid and mask[7]), candidate_mask=int(sum(int(mask[i]) << i for i in range(8))) if valid else 0,
                future_queue_risk_score=float(scores[7]), scores_are_calibrated_probabilities=False,
                future_latency_max_p95_us=float(np.expm1(log_latency)) if valid else None,
                history_windows=8, horizon_windows=3, compute_cycles=cycles,
                confirmed_physical_causes=[], afdx_configuration_write=False,
                hardware_timing_proof=False)
