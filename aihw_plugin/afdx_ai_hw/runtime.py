"""Read-only model adapter; RTL simulation is executed, never substituted by Python."""
import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path
import numpy as np
from .fixed import ROOT, load_model, prepare_history, integer_tcn, decode_result, write_json


def tools():
    found = {}
    for name, variable in (('iverilog', 'IVERILOG'), ('vvp', 'VVP')):
        candidate = os.environ.get(variable) or shutil.which(name)
        fallback = ROOT.parent / 'local_tools/usr/bin' / name
        if candidate is None and fallback.is_file():
            candidate = str(fallback)
        if candidate is None or not Path(candidate).is_file():
            raise RuntimeError('Install Icarus Verilog or set ' + variable)
        found[name] = str(Path(candidate).resolve())
    base = os.environ.get('IVL_BASE')
    fallback = Path(found['iverilog']).parents[1] / 'lib/x86_64-linux-gnu/ivl'
    if not base and fallback.is_dir():
        base = str(fallback)
    found['base_args'] = ['-B', str(Path(base).resolve())] if base else []
    return found


def simulate(qx, flags, job_id=1, root=ROOT, work=None):
    root = Path(root).resolve()
    cfg, p = load_model(root)
    a = np.asarray(qx)
    if a.shape != (8, 18) or a.dtype.kind not in 'iu' or np.any(a < -32768) or np.any(a > 32767):
        raise ValueError('quantized input')
    if type(flags) is not int or not 0 <= flags <= 3 or type(job_id) is not int or not 0 <= job_id <= 0xffffffff:
        raise ValueError('job metadata')
    t = tools()
    parent = Path(work).resolve() if work is not None else root / 'reports'
    parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='rtl_job_', dir=parent) as tmp:
        tmp = Path(tmp)
        values = [job_id, int(cfg['model_tag'], 16), flags] + (a.astype(np.int64).reshape(-1) & 0xffff).tolist()
        (tmp / 'input.mem').write_text(''.join(f'{v:08x}\n' for v in values))
        args = [t['iverilog'], *t['base_args'], '-g2012', '-I' + str(root / 'rtl'),
                '-s', 'tb_hw_infer', '-o', str(tmp / 'infer.vvp')]
        for parameter, filename in [('WEIGHTS_FILE', 'weights.mem'), ('BIASES_FILE', 'biases.mem'),
                                     ('THRESHOLDS_FILE', 'thresholds.mem'), ('SHIFTS_FILE', 'shifts.mem')]:
            # Verilog string argument, passed without a shell.
            import json
            args += ['-Ptb_hw_infer.' + parameter + '=' + json.dumps(str(root / 'rtl' / filename))]
        args += [str(root / 'rtl/afdx_ai_tcn_plugin.v'), str(root / 'tests/tb_hw_infer.v')]
        env = dict(os.environ, TMPDIR=str(tmp))
        compile_result = subprocess.run(args, cwd=tmp, env=env, capture_output=True, text=True, timeout=30)
        if compile_result.returncode:
            raise RuntimeError('RTL compile failed: ' + compile_result.stderr[:2000])
        run = subprocess.run([t['vvp'], str(tmp / 'infer.vvp')], cwd=tmp, env=env,
                             capture_output=True, text=True, timeout=30)
        if run.returncode or re.search(r'\b(?:ERROR|FATAL|FAIL)\b', run.stdout + run.stderr):
            raise RuntimeError('RTL simulation failed: ' + (run.stdout + run.stderr)[:2000])
        lines = [line for line in run.stdout.splitlines() if line.startswith('RESULT ')]
        if len(lines) != 1:
            raise RuntimeError('missing or duplicate RTL result')
        words = lines[0].split()
        if len(words) != 16:
            raise RuntimeError('RTL result field count')
        ident, tag = int(words[1]), words[2]
        errors, sat, cycles, mask = map(int, words[3:7])
        logits = np.asarray([int(w) for w in words[7:]], dtype=np.int64)
        if ident != job_id or tag != cfg['model_tag'] or cycles != cfg['compute_cycles']:
            raise RuntimeError('RTL result binding or cycle mismatch')
        result = decode_result(logits, errors, cfg, p, job_id, cycles, 'rtl_simulation')
        if result['candidate_mask'] != mask:
            raise RuntimeError('RTL decision mask mismatch')
        result['saturation_layers'] = sat
        result['rtl_log'] = run.stdout.strip()
        return result


class HardwareTemporalPlugin:
    def __init__(self, root=ROOT):
        self.root = Path(root)
        self.cfg, self.p = load_model(root)

    def analyze(self, history, backend='rtl', job_id=1, measurement_source='synthetic', work=None):
        if measurement_source not in ('synthetic', 'rtl_capture', 'hardware'):
            raise ValueError('measurement source')
        if type(job_id) is not int or not 0 <= job_id <= 0xffffffff:
            raise ValueError('job id')
        qx, flags, outside = prepare_history(history, self.cfg, self.p)
        if backend == 'rtl':
            result = simulate(qx, flags, job_id, self.root, work)
        elif backend == 'reference':
            logits, saturation = integer_tcn(qx[None], self.cfg, self.p)
            errors = (16 if flags & 1 else 0) | (32 if flags & 2 or saturation[0] else 0)
            result = decode_result(logits[0], errors, self.cfg, self.p, job_id, source='integer_reference')
            result['saturation_layers'] = int(saturation[0])
        else:
            raise ValueError('backend must be rtl or reference')
        result['measurement_source_declaration'] = measurement_source
        result['outside_features'] = outside
        result['preprocessing_on_host'] = True
        return result


def csr_operations(history, job_id=1, root=ROOT):
    cfg, p = load_model(root)
    if type(job_id) is not int or not 0 <= job_id <= 0xffffffff:
        raise ValueError('job id')
    qx, flags, outside = prepare_history(history, cfg, p)
    operations = [dict(op='wait_bits', addr=8, mask=1, value=1)]
    for addr, value in ((12, job_id), (16, int(cfg['model_tag'], 16)), (20, 0x3ffff), (24, flags), (28, 1)):
        operations.append(dict(op='write32', addr=addr, value=value))
    for i, value in enumerate(qx.reshape(-1)):
        operations.append(dict(op='write32', addr=32, value=(int(value) & 0xffff) | (int(i == 143) << 16)))
    operations += [dict(op='wait_bits', addr=8, mask=4, value=4)]
    operations += [dict(op='read32', addr=a) for a in [4, 40, 44, 48, *range(52, 88, 4)]]
    operations.append(dict(op='write32', addr=36, value=1))
    return dict(schema=1, bus='independent trusted local AI CSR', afdx_configuration_write=False,
                model_tag=cfg['model_tag'], outside_features=outside, operations=operations,
                polling_must_have_transport_deadline=True)
