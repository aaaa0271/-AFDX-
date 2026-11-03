"""Package an explicitly selected evidence directory with a generated SHA-256 index."""
import argparse
import hashlib
import json
import zipfile
from pathlib import Path
from package_common import ROOT, validate_output

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--evidence', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    a = p.parse_args()
    evidence = a.evidence.resolve()
    if not evidence.is_dir():
        p.error('Evidence directory is missing')
    output = validate_output(ROOT, a.output)
    if output.is_relative_to(evidence):
        p.error('Output cannot be inside the evidence directory')
    files = sorted(f for f in evidence.rglob('*') if f.is_file() and f.name != 'MANIFEST.sha256')
    if not files:
        p.error('Evidence directory is empty')
    output.parent.mkdir(parents=True, exist_ok=True)
    rows = []
    with zipfile.ZipFile(output, 'x', zipfile.ZIP_DEFLATED) as archive:
        for f in files:
            if f.is_symlink() or not f.resolve().is_relative_to(evidence):
                raise ValueError('Evidence symlink or escaped path')
            rel = f.relative_to(evidence).as_posix()
            data = f.read_bytes()
            archive.writestr(rel, data)
            rows.append(hashlib.sha256(data).hexdigest() + '  ' + rel)
        archive.writestr('MANIFEST.sha256', '\n'.join(rows) + '\n')
    print(json.dumps(dict(output=str(output), files=len(rows),
                          scope='Archive integrity only; no functional verdict inferred')))

if __name__ == '__main__':
    main()
