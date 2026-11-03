"""Create a source ZIP outside the project, without deleting or overwriting anything."""
import argparse
import hashlib
import json
import zipfile
from pathlib import Path
from package_common import ROOT, inventory, validate_output

def build(source, output, folder_name=None):
    source = Path(source).resolve()
    if not (source / 'rtl/AFDX_defense_top.v').is_file():
        raise ValueError('Not an AFDX source directory')
    output = validate_output(source, output)
    if folder_name is not None and (not folder_name or Path(folder_name).name!=folder_name or folder_name in ('.','..') or '/' in folder_name or '\\\\' in folder_name):
        raise ValueError('Folder name must be one safe basename')
    prefix=(folder_name+'/') if folder_name else ''
    rows = inventory(source)
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, 'x', zipfile.ZIP_DEFLATED) as archive:
        for name, expected in rows.items():
            data = (source / name).read_bytes()
            if hashlib.sha256(data).hexdigest() != expected:
                raise RuntimeError('Input changed while packaging: ' + name)
            archive.writestr(prefix + name, data)
        archive.writestr(prefix + 'MANIFEST.sha256',
                         ''.join(h + '  ' + name + '\n' for name, h in rows.items()))
    print(json.dumps(dict(zip=str(output), manifest_files=len(rows),
                          pyc_retained=True, source_modified=False)))
    return rows

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--source', type=Path, default=ROOT)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--folder-name', help='Optional single top-level folder inside the ZIP')
    args = p.parse_args()
    build(args.source, args.output, args.folder_name)

if __name__ == '__main__':
    main()
