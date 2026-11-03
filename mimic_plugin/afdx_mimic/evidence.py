import datetime,json
from pathlib import Path
from .contract import canonical,load_json,sha

def write_json(path,value):
    path=Path(path);path.parent.mkdir(parents=True,exist_ok=True)
    temporary=path.with_suffix(path.suffix+'.tmp');temporary.write_text(json.dumps(value,indent=2,ensure_ascii=False,allow_nan=False)+'\n',encoding='utf8');temporary.replace(path)
class Journal:
    def __init__(self,directory):self.root=Path(directory);self.tail='0'*64;self.seq=0
    def append(self,kind,data):
        self.seq+=1;r=dict(seq=self.seq,kind=kind,data=data,previous=self.tail,utc=datetime.datetime.now(datetime.timezone.utc).isoformat());r['sha256']=sha(canonical(r));self.tail=r['sha256']
        with (self.root/'trace.jsonl').open('a',encoding='utf8') as stream:stream.write(json.dumps(r,ensure_ascii=False)+'\n')
        return r
def seal(directory):
    root=Path(directory);files={str(p.relative_to(root)):sha(p.read_bytes()) for p in root.rglob('*') if p.is_file() and p!=root/'integrity.json'}
    write_json(root/'integrity.json',dict(schema=1,files=files,authenticated_signature=False));return verify(root)
def verify(directory):
    root=Path(directory).resolve();d=load_json((root/'integrity.json').read_bytes());actual={str(p.relative_to(root)) for p in root.rglob('*') if p.is_file() and p!=root/'integrity.json'}
    if set(d['files'])!=actual:raise ValueError('evidence inventory changed')
    for relative,h in d['files'].items():
        p=(root/relative).resolve()
        if Path(relative).is_absolute() or '..' in Path(relative).parts or not p.is_relative_to(root) or sha(p.read_bytes())!=h:raise ValueError('evidence hash/path mismatch')
    tail='0'*64;count=0
    for line in (root/'trace.jsonl').read_text(encoding='utf8').splitlines():
        r=load_json(line);h=r.pop('sha256');count+=1
        if r['seq']!=count or r['previous']!=tail or sha(canonical(r))!=h:raise ValueError('trace mismatch')
        if r['kind']=='frame':
            relative=r['data']['result_file'];path=(root/relative).resolve()
            if Path(relative).is_absolute() or '..' in Path(relative).parts or not path.is_relative_to(root):raise ValueError('trace result path')
            result=load_json(path.read_bytes())
            if sha(canonical(result))!=r['data']['result_sha256']:raise ValueError('frame trace binding')
        tail=h
    report=load_json((root/'report.json').read_bytes())
    if report['trace_tail']!=tail:raise ValueError('report trace binding')
    return dict(status='PASS',files=len(actual),trace_records=count,authenticated_signature=False)
