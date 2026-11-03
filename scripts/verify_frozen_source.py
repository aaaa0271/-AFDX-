"""Read-only integrity check of the final source handoff; creates no cache/log."""
from pathlib import Path
import hashlib,json,sys
ROOT=Path(__file__).resolve().parents[1]
def main():
    p=ROOT/'SOURCE_MANIFEST.json'
    if not p.is_file():print('NOT_FROZEN: final delivery manifest not generated');return 2
    m=json.loads(p.read_text(encoding='utf-8'))
    expected=m['files']
    current={f.relative_to(ROOT).as_posix():hashlib.sha256(f.read_bytes()).hexdigest()
             for f in ROOT.rglob('*') if f.is_file() and f!=p}
    missing=sorted(set(expected)-set(current));added=sorted(set(current)-set(expected))
    changed=sorted(n for n in set(current)&set(expected) if current[n]!=expected[n])
    result=dict(status='PASS' if not (missing or added or changed) else 'FAIL',
                release=m['release'],files=len(expected),missing=missing,added=added,changed=changed)
    print(json.dumps(result,indent=2,ensure_ascii=False));return 0 if result['status']=='PASS' else 1
if __name__=='__main__':raise SystemExit(main())