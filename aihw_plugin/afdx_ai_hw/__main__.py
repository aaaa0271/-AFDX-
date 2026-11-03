import argparse
from pathlib import Path
from .fixed import read_json, write_json, load_model
from .runtime import HardwareTemporalPlugin, csr_operations


def main():
    parser = argparse.ArgumentParser(description='AFDX fixed-point temporal inference plugin')
    sub = parser.add_subparsers(dest='command', required=True)
    sub.add_parser('inspect')
    for name in ('infer', 'emit-csr'):
        p = sub.add_parser(name)
        p.add_argument('--history', required=True)
        p.add_argument('--job-id', type=int, default=1)
        p.add_argument('--out', required=True)
        if name == 'infer':
            p.add_argument('--backend', choices=('rtl', 'reference'), default='rtl')
            p.add_argument('--measurement-source', choices=('synthetic', 'rtl_capture', 'hardware'), default='synthetic')
    args = parser.parse_args()
    if args.command == 'inspect':
        import json
        print(json.dumps(load_model()[0], indent=2, ensure_ascii=False))
        return
    history = read_json(args.history)
    # Output files are new artifacts; never overwrite the input measurements.
    if Path(args.out).resolve() == Path(args.history).resolve():
        parser.error('output must differ from input history')
    if args.command == 'infer':
        result = HardwareTemporalPlugin().analyze(history, args.backend, args.job_id, args.measurement_source)
    else:
        result = csr_operations(history, args.job_id)
    write_json(args.out, result)
    print('INFER_PASS' if args.command == 'infer' else 'CSR_PLAN_PASS', args.out)


if __name__ == '__main__':
    main()
