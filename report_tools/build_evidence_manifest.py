"""Index actual run artifacts with hashes; no hard-coded performance/pass claims."""
import argparse
import hashlib
import json
from pathlib import Path


def build(run,output):
    run=Path(run).resolve();output=Path(output).resolve()
    if output.exists():raise FileExistsError(output)
    acceptance=json.loads((run/'acceptance.json').read_text(encoding='utf-8'))
    artifacts=[]
    for p in sorted(run.rglob('*')):
        if not p.is_file():continue
        rel=p.relative_to(run)
        if any(x in ('work','source_snapshot','native') for x in rel.parts):continue
        if p.suffix.lower() in ('.exe','.dll','.obj','.o'):continue
        artifacts.append(dict(path=rel.as_posix(),bytes=p.stat().st_size,sha256=hashlib.sha256(p.read_bytes()).hexdigest()))
    result=dict(schema=2,run=str(run),functional_status=acceptance.get('functional_status'),
                tests=len(acceptance.get('tests',[])),artifacts=artifacts,
                scope='Artifact presence and integrity; semantic claims remain in original run verdicts.')
    output.parent.mkdir(parents=True,exist_ok=True)
    with output.open('x',encoding='utf-8') as f:json.dump(result,f,ensure_ascii=False,indent=2);f.write('\\n')
    return result


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--run',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    args=p.parse_args();result=build(args.run,args.output);print('Indexed',len(result['artifacts']),'actual artifacts')
