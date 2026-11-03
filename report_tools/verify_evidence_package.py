"""Verify every listed file and optional ZIP, rejecting missing/tampered entries."""
import argparse
import hashlib
import json
import zipfile
from pathlib import Path


def verify(source,archive=None):
    source=Path(source).resolve()
    rows={}
    for line in (source/'MANIFEST.sha256').read_text(encoding='utf-8').splitlines():
        digest,sep,name=line.partition('  ')
        if not sep or len(digest)!=64 or name in rows:raise ValueError('Invalid/duplicate manifest line')
        path=(source/name).resolve()
        if not path.is_relative_to(source) or not path.is_file():raise ValueError('Missing/unsafe path: '+name)
        if hashlib.sha256(path.read_bytes()).hexdigest()!=digest:raise ValueError('Hash mismatch: '+name)
        rows[name]=digest
    if archive:
        with zipfile.ZipFile(archive) as z:
            if z.testzip():raise ValueError('ZIP CRC failure')
            names=z.namelist()
            if len(names)!=len(set(names)):raise ValueError('Duplicate ZIP entries')
            prefix='' if 'MANIFEST.sha256' in names else source.name+'/'
            expected={prefix+n for n in rows}|{prefix+'MANIFEST.sha256'}
            if set(names)!=expected:raise ValueError('ZIP file set differs from manifest')
            for name,digest in rows.items():
                if hashlib.sha256(z.read(prefix+name)).hexdigest()!=digest:raise ValueError('ZIP hash mismatch: '+name)
    return dict(status='PASS',manifest_files=len(rows),zip_verified=bool(archive))


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('source',type=Path);p.add_argument('--zip',type=Path)
    args=p.parse_args();print(json.dumps(verify(args.source,args.zip)))
