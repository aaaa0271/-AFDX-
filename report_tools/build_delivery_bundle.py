"""Bundle explicitly chosen reports/posters/archives; preserve every existing file."""
import argparse
import hashlib
import json
import zipfile
from pathlib import Path
from package_common import ROOT, validate_output

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--files', nargs='+', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    a = p.parse_args()
    output = validate_output(ROOT, a.output)
    files = [f.resolve() for f in a.files]
    if any(not f.is_file() or f.is_symlink() for f in files):
        p.error('All selected inputs must be existing regular files')
    if len({f.name.casefold() for f in files}) != len(files):
        p.error('Duplicate input filenames')
    output.parent.mkdir(parents=True, exist_ok=True)
    rows = []
    with zipfile.ZipFile(output, 'x', zipfile.ZIP_DEFLATED) as archive:
        for f in files:
            data = f.read_bytes()
            archive.writestr(f.name, data)
            rows.append(hashlib.sha256(data).hexdigest() + '  ' + f.name)
        archive.writestr('MANIFEST.sha256', '\n'.join(rows) + '\n')
    print(json.dumps(dict(output=str(output), files=len(files))))

if __name__ == '__main__':
    main()
