import hashlib,json,re
from pathlib import Path
from afdx_ai.schema import strict_json,InputError

TYPES={'frame_pair','frame','events','log','time_samples','loader_trace','policy','counters'}
SOURCES={'synthetic_lab','rtl_fixture','external_capture','hardware_capture'}
def sha(raw):return hashlib.sha256(raw).hexdigest()
def canonical(d):return json.dumps(d,sort_keys=True,separators=(',',':'),ensure_ascii=False,allow_nan=False).encode()

class Case:
    def __init__(self,directory):
        self.root=Path(directory).resolve();self.files={}
        self.manifest=self.read_json('case.json');m=self.manifest
        required={'schema','case_id','observation','artifacts','expected_flow'}
        if not isinstance(m,dict) or set(m)!=required or type(m['schema']) is not int or m['schema']!=1:raise InputError('case schema')
        if not isinstance(m['case_id'],str) or not re.fullmatch('[A-Za-z0-9_-]{1,64}',m['case_id']):raise InputError('case_id')
        if not isinstance(m['artifacts'],list) or len(m['artifacts'])>24:raise InputError('artifact budget')
        self.artifacts={}
        for item in m['artifacts']:
            if not isinstance(item,dict) or set(item)!={'id','type','paths','binding','source','window_id'}:raise InputError('artifact schema')
            if not isinstance(item['id'],str) or not re.fullmatch('[A-Za-z0-9_-]{1,64}',item['id']) or item['id'] in self.artifacts:raise InputError('artifact id')
            if item['type'] not in TYPES or item['source'] not in SOURCES:raise InputError('artifact type/source')
            if item['binding'] not in ('same_window','reference_fixture'):raise InputError('artifact binding')
            if not isinstance(item['paths'],list) or len(item['paths'])!=(2 if item['type']=='frame_pair' else 1):raise InputError('artifact paths')
            for path in item['paths']:self.read(path)
            self.artifacts[item['id']]=item
        self.observation=self.read_json(m['observation']) if m['observation'] is not None else None
        if self.observation is not None and not isinstance(self.observation,dict):raise InputError('observation object required')
        for item in self.artifacts.values():
            if item['binding']=='same_window' and (not self.observation or item['window_id']!=self.observation.get('window_id')):
                raise InputError('same_window artifact is not bound to this observation')
        f=m['expected_flow']
        if not isinstance(f,dict) or set(f)!={'peer_ip','local_ip','rx_mac','peer_mac','tx_mac','source_port','destination_port'}:
            raise InputError('trusted lab flow schema')
        for k,v in f.items():
            limit=2**48 if k.endswith('mac') else 2**16 if k.endswith('port') else 2**32
            if type(v) is not int or not 0<=v<limit:raise InputError('lab flow field '+k)
        self.id=m['case_id'];self.flow=f
        self.fingerprint=sha(canonical(dict(manifest=m,files=self.files)))

    def resolve(self,path):
        if not isinstance(path,str) or not path or len(path)>240:raise InputError('relative evidence path')
        p=Path(path)
        if p.is_absolute() or '..' in p.parts:raise InputError('evidence path outside case')
        target=(self.root/p).resolve()
        if not target.is_relative_to(self.root) or not target.is_file():raise InputError('evidence file unavailable/outside case')
        if target.stat().st_size>8*1024*1024:raise InputError('evidence file size budget')
        return target

    def read(self,path):
        raw=self.resolve(path).read_bytes();digest=sha(raw)
        if path in self.files and digest!=self.files[path]:raise InputError('evidence changed after inventory: '+path)
        self.files[path]=digest
        if len(self.files)>50:raise InputError('evidence file count budget')
        return raw

    def read_json(self,path):
        def pairs(items):
            d={}
            for k,v in items:
                if k in d:raise InputError('duplicate JSON key')
                d[k]=v
            return d
        return json.loads(self.read(path),object_pairs_hook=pairs,
            parse_constant=lambda _:(_ for _ in ()).throw(InputError('nonfinite JSON')))


    def artifact(self,ident,type_=None):
        if ident not in self.artifacts:raise InputError('unknown evidence id')
        item=self.artifacts[ident]
        if type_ and item['type']!=type_:raise InputError('evidence type mismatch')
        return item

    def provenance(self,ident):
        item=self.artifact(ident)
        return dict(artifact_id=ident,binding=item['binding'],source=item['source'],window_id=item['window_id'],
                    files=[dict(path=p,sha256=self.files[p]) for p in item['paths']])
