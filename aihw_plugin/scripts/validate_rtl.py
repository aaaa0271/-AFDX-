#!/usr/bin/env python3
"""Fail-closed compiler/simulation runner. Uses argument arrays, not shell commands."""
import os
import re
import subprocess
import sys
import time
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from afdx_ai_hw.fixed import load_model, write_json
from afdx_ai_hw.runtime import tools
from scripts.make_vectors import make_vectors


def run(args, name, env):
    started = time.monotonic()
    r = subprocess.run(args, cwd=ROOT, env=env, capture_output=True, text=True, timeout=180)
    output = r.stdout + r.stderr
    (ROOT / 'reports' / (name + '.log')).write_text(output)
    if r.returncode or re.search(r'\b(?:FAIL|FATAL|ERROR)\b', output):
        raise RuntimeError(name + ' failed: ' + output[-3000:])
    return output, time.monotonic() - started


def main():
    cfg, _ = load_model()
    count = make_vectors()
    csr = ROOT / 'reports/csr_vectors'
    csr.mkdir(exist_ok=True)
    for name, n in [('inputs', 144), ('logits', 9), ('flags', 1), ('status', 1), ('mask', 1), ('saturation', 1)]:
        lines = (ROOT / 'reports/vectors' / (name + '.mem')).read_text().splitlines()[:n]
        (csr / (name + '.mem')).write_text('\n'.join(lines) + '\n')
    t = tools()
    env = dict(os.environ, TMPDIR=str(ROOT / 'reports'))
    prefix = [t['iverilog'], *t['base_args']]
    syntax, _ = run(prefix + ['-g2001', '-t', 'null', '-Irtl', '-s', 'afdx_ai_csr',
                              'rtl/afdx_ai_tcn_plugin.v', 'rtl/afdx_ai_csr.v'], 'syntax_verilog2001', env)
    summary = dict(model_tag=cfg['model_tag'], syntax_verilog2001=True,
                   synthesis_performed=False, target_timing_closed=False, board_tested=False, tests={})
    for top, sources, marker in [
        ('tb_tcn_plugin', ['rtl/afdx_ai_tcn_plugin.v', 'tests/tb_tcn_plugin.v'], 'RTL_ALL_PASS protocol_cases=12'),
        ('tb_csr', ['rtl/afdx_ai_tcn_plugin.v', 'rtl/afdx_ai_csr.v', 'tests/tb_csr.v'], 'CSR_ALL_PASS normal_jobs=1 illegal_accesses=6'),
        ('tb_arithmetic', ['rtl/afdx_ai_tcn_plugin.v', 'tests/tb_arithmetic.v'], 'ARITHMETIC_ALL_PASS')]:
        binary = 'reports/' + top + '.vvp'
        run(prefix + ['-g2012', '-Irtl', '-Ireports/vectors', '-s', top, '-o', binary, *sources], top + '_compile', env)
        output, seconds = run([t['vvp'], binary], top, env)
        if marker not in output:
            raise RuntimeError('missing final PASS marker for ' + top)
        if top == 'tb_tcn_plugin' and f'RTL_VECTOR_PASS vectors={count} intermediate_values={count*288} fixed_compute_cycles=14035' not in output:
            raise RuntimeError('missing vector proof')
        summary['tests'][top] = dict(status='PASS', seconds=seconds, log='reports/' + top + '.log')
        print(marker, flush=True)
    summary.update(vectors=count, compared_logits=count*9, compared_intermediate_values=count*288,
                   protocol_cases=12, compute_cycles=cfg['compute_cycles'],
                   assumed_clock_hz=12500000, simulated_compute_latency_us=cfg['compute_cycles'] / 12.5,
                   latency_excludes_input_collection_transfer_and_output_backpressure=True)
    write_json(ROOT / 'reports/rtl_validation.json', summary)
    print('RTL_VALIDATION_PASS', flush=True)


if __name__ == '__main__':
    main()
