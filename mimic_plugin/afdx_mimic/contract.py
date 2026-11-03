import hashlib,json,re,struct
from pathlib import Path

class ContractError(ValueError):pass
REASONS=('OK','WIRE_LENGTH','PREAMBLE','FCS','ETHERTYPE','IP_VERSION','IP_BOUNDS','IP_OPTIONS',
         'IP_CHECKSUM','IP_FRAGMENT','IP_PROTOCOL','IP_TTL','UDP_LENGTH','UDP_CHECKSUM','ACL','UDP_CHECKSUM_REQUIRED')
RULE_FIELDS={'id','peer_ip','local_ip','rx_mac','peer_mac','source_port','destination_port','max_mac','require_udp_checksum'}
HEADER=struct.Struct('>4sQIIQBBH32s32s')
RULE=struct.Struct('>HIIQQHHHB')
META={'request_id','epoch','generation','policy_hash','input_hash'}
SEMANTIC={'verdict','reason','rule_id','wire_length','fields','payload_hex'}
MAX_OUTPUT=8192

def canonical(value):return json.dumps(value,sort_keys=True,separators=(',',':'),ensure_ascii=False,allow_nan=False).encode()
def sha(raw):return hashlib.sha256(raw).hexdigest()
def uint(value,bits,name):
    if type(value) is not int or not 0<=value<2**bits:raise ContractError('invalid '+name)
    return value
def load_json(raw):
    def pairs(items):
        d={}
        for k,v in items:
            if k in d:raise ContractError('duplicate JSON key')
            d[k]=v
        return d
    return json.loads(raw,object_pairs_hook=pairs,parse_constant=lambda _:(_ for _ in ()).throw(ContractError('nonfinite JSON')))
def policy(value):
    if not isinstance(value,dict) or set(value)!={'schema','epoch','rules'} or type(value['schema']) is not int or value['schema']!=1:raise ContractError('policy schema')
    uint(value['epoch'],32,'epoch')
    if not isinstance(value['rules'],list) or not 1<=len(value['rules'])<=8:raise ContractError('rule count')
    seen=set();rules=[]
    for r in value['rules']:
        if not isinstance(r,dict) or set(r) not in (RULE_FIELDS,RULE_FIELDS|{'allow_fragments'}):raise ContractError('rule fields')
        if 'allow_fragments' in r and type(r['allow_fragments']) is not bool:raise ContractError('fragment policy flag')
        for k,bits in [('id',4),('peer_ip',32),('local_ip',32),('rx_mac',48),('peer_mac',48),('source_port',16),('destination_port',16)]:uint(r[k],bits,k)
        if r['id'] in seen or type(r['max_mac']) is not int or not 64<=r['max_mac']<=1518 or type(r['require_udp_checksum']) is not bool:raise ContractError('rule value/duplicate')
        seen.add(r['id']);rules.append(dict(r))
    return dict(schema=1,epoch=value['epoch'],rules=sorted(rules,key=lambda x:x['id']))

def request(raw,p,request_id,generation,channel=0,capture_ticks=0):
    if not isinstance(raw,bytes) or len(raw)>2048:raise ContractError('frame input bound')
    p=policy(p);uint(request_id,64,'request_id');uint(generation,32,'generation');uint(capture_ticks,64,'capture_ticks')
    if type(channel) is not int or channel not in (0,1):raise ContractError('RX channel')
    meta=dict(request_id=request_id,epoch=p['epoch'],generation=generation,policy_hash=sha(canonical(p)),input_hash=sha(raw))
    data=HEADER.pack(b'MDH1',request_id,p['epoch'],generation,capture_ticks,channel,len(p['rules']),len(raw),bytes.fromhex(meta['policy_hash']),bytes.fromhex(meta['input_hash']))
    data+=b''.join(RULE.pack(*[r[k] for k in ('id','peer_ip','local_ip','rx_mac','peer_mac','source_port','destination_port','max_mac')],int(r['require_udp_checksum'])|(int(r.get('allow_fragments',False))<<1)) for r in p['rules'])
    return data+raw,meta

def decode_response(raw,expected,wire_length):
    if len(raw)>MAX_OUTPUT:raise ContractError('worker output budget')
    d=load_json(raw)
    if not isinstance(d,dict) or set(d)!=META|SEMANTIC:raise ContractError('worker result schema')
    for k in ('request_id','epoch','generation'):
        uint(d[k],64 if k=='request_id' else 32,k)
    if any(d[k]!=expected[k] for k in META):raise ContractError('stale or mismatched worker result')
    if d['verdict'] not in ('allow','deny') or d['reason'] not in REASONS:raise ContractError('worker verdict/reason')
    if type(d['wire_length']) is not int or d['wire_length']!=wire_length:raise ContractError('wire length binding')
    if type(d['rule_id']) is not int or not -1<=d['rule_id']<16:raise ContractError('rule id')
    if not isinstance(d['fields'],list) or len(d['fields'])!=9:raise ContractError('semantic fields')
    for x,b in zip(d['fields'],(48,48,32,32,16,8,16,16,16)):uint(x,b,'semantic field')
    if not isinstance(d['payload_hex'],str) or len(d['payload_hex'])>3000 or not re.fullmatch('(?:[0-9a-f]{2})*',d['payload_hex']):raise ContractError('payload encoding')
    if d['verdict']=='deny':
        if d['reason']=='OK' or d['rule_id']!=-1 or any(d['fields']) or d['payload_hex']:raise ContractError('noncanonical denial')
    elif d['reason']!='OK' or d['rule_id']<0 or d['fields'][8]!=len(d['payload_hex'])//2+8:raise ContractError('noncanonical allowance')
    return d

def semantic(d):return {k:d[k] for k in sorted(SEMANTIC)}
def semantic_hash(d):return sha(canonical(semantic(d)))

def case(directory):
    root=Path(directory).resolve();hashes={}
    def read(path):
        if not isinstance(path,str) or not path or len(path)>200 or Path(path).is_absolute() or '..' in Path(path).parts:raise ContractError('case relative path')
        f=(root/path).resolve()
        if not f.is_relative_to(root) or not f.is_file() or f.stat().st_size>1024*1024:raise ContractError('case path/size')
        raw=f.read_bytes();hashes[path]=sha(raw);return raw
    m=load_json(read('case.json'))
    if not isinstance(m,dict) or set(m)!={'schema','case_id','source','policy','frames'} or type(m['schema']) is not int or m['schema']!=1:raise ContractError('case schema')
    if not isinstance(m['case_id'],str) or not re.fullmatch('[A-Za-z0-9_-]{1,64}',m['case_id']):raise ContractError('case id')
    if m['source'] not in ('synthetic_lab','external_capture','hardware_capture'):raise ContractError('case source')
    p=policy(load_json(read(m['policy'])))
    if not isinstance(m['frames'],list) or not 1<=len(m['frames'])<=256:raise ContractError('frame count')
    frames=[];ids=set();last=-1
    for f in m['frames']:
        if not isinstance(f,dict) or set(f)!={'id','path','channel','capture_ticks'}:raise ContractError('frame schema')
        if not isinstance(f['id'],str) or not re.fullmatch('[A-Za-z0-9_-]{1,64}',f['id']) or f['id'] in ids:raise ContractError('frame id')
        ids.add(f['id']);uint(f['capture_ticks'],64,'capture_ticks')
        if f['capture_ticks']<last:raise ContractError('capture order')
        last=f['capture_ticks']
        raw=read(f['path']);request(raw,p,0,0,f['channel'],last)
        frames.append(dict(f,raw=raw))
    return dict(root=root,manifest=m,policy=p,frames=frames,hashes=hashes)
