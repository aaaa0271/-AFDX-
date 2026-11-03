import datetime,hashlib,json,os,time
from pathlib import Path
from .case import canonical,sha

def atomic_json(path,value):
    data=json.dumps(value,indent=2,ensure_ascii=False,allow_nan=False)+'\n';temporary=path.with_suffix(path.suffix+'.tmp')
    with temporary.open('w',encoding='utf8') as f:f.write(data);f.flush();os.fsync(f.fileno())
    os.replace(temporary,path)

class Journal:
    def __init__(self,directory):
        self.root=Path(directory);self.previous='0'*64;self.records=[]
        (self.root/'tools').mkdir(parents=True)
    def append(self,tool,args,result,seconds):
        seq=len(self.records)+1;relative=f'tools/{seq:02d}_{tool}.json';path=self.root/relative;atomic_json(path,result)
        record=dict(seq=seq,tool=tool,args=args,previous=self.previous,result_file=relative,result_sha256=sha(path.read_bytes()),
                    status=result.get('status','ok'),utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),seconds=seconds)
        record['hash']=sha(canonical(record));self.previous=record['hash'];self.records.append(record)
        with (self.root/'trace.jsonl').open('a',encoding='utf8') as f:f.write(json.dumps(record,ensure_ascii=False)+'\n');f.flush();os.fsync(f.fileno())
        return record

def verify(directory):
    root=Path(directory).resolve();previous='0'*64;count=0
    for line in (root/'trace.jsonl').read_text(encoding='utf8').splitlines():
        d=json.loads(line);digest=d.pop('hash');count+=1
        if d['seq']!=count or d['previous']!=previous or sha(canonical(d))!=digest:raise ValueError('trace hash/sequence mismatch')
        path=(root/d['result_file']).resolve()
        if not path.is_relative_to(root) or sha(path.read_bytes())!=d['result_sha256']:raise ValueError('tool result hash/path mismatch')
        previous=digest
    completion=root/'completion.json'
    if completion.exists():
        c=json.loads(completion.read_text(encoding='utf8'));report=json.loads((root/'report.json').read_text(encoding='utf8'))
        if c['trace_tail']!=previous or report['trace_tail']!=previous or report['steps']!=count:raise ValueError('report trace binding mismatch')
        if sha((root/'report.json').read_bytes())!=c['report_sha256'] or sha((root/'report.md').read_bytes())!=c['markdown_sha256']:raise ValueError('report hash mismatch')
    return dict(status='PASS',tool_calls=count,last_hash=previous,authenticated_signature=False)
