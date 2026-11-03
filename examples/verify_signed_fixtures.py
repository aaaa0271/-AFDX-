"""Independently verify shipped fixture signatures and baseline file digests."""
import hashlib,json,sys
from pathlib import Path
R=Path(__file__).resolve().parents[1];sys.path.insert(0,str(R/'host'))
from authorizer import validate_manifest

f=json.loads((R/'tb/core_signed_authorizations.json').read_text())
for item in f['domains']:
    d=item['document']
    validate_manifest(d,bytes.fromhex(item['signature']),bytes.fromhex(f['public_key']),
                      target='SIM',hardware_id=d['hardware_id'],nonce=d['nonce'],now=150,floor=6)
    for row in d['files']:
        content=bytes(int(x,16) for x in (R/'reference_core/tb'/(row['name']+'.hex')).read_text().split())
        if len(content)!=row['length'] or hashlib.sha256(content).hexdigest()!=row['sha256']:
            raise ValueError('fixture content does not match signed manifest')
d=json.loads((R/'tb/signed_manifest.json').read_text())
validate_manifest(d,(R/'tb/manifest.sig').read_bytes(),(R/'tb/manifest_public_key.bin').read_bytes(),
                  target='SIM',hardware_id=d['hardware_id'],nonce=d['nonce'],now=150,floor=6)
print('SIGNED_FIXTURE_AUDIT_PASS manifests=3 core_files=6 fixture_time=150')
