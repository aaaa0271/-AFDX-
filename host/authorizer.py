"""Ed25519 signed loading manifests -> bounded RTL grant register writes.

Only this trusted host control plane handles signatures/persistent floors.
RTL independently SHA-256 checks actual TFTP data before releasing its last
DATA block. Neither a CRC nor a caller-provided 'signature_ok' flag is used.
"""
from __future__ import annotations
import argparse,base64,contextlib,hashlib,json,os,re,tempfile,time
from pathlib import Path
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
from cryptography.exceptions import InvalidSignature
DOMAIN=b'AFDX-SEC-MANIFEST-v1\0'
class AuthorizationError(ValueError):pass
def canonical(document):
 return DOMAIN+json.dumps(document,sort_keys=True,separators=(',',':'),ensure_ascii=True,allow_nan=False).encode('ascii')
def exact_int(value,minimum,maximum,label):
 if type(value) is not int or not minimum<=value<=maximum:raise AuthorizationError('invalid '+label)
 return value
def load_json(path):
 def pairs(items):
  out={}
  for k,v in items:
   if k in out:raise AuthorizationError('duplicate JSON key '+k)
   out[k]=v
  return out
 raw=Path(path).read_bytes()
 if len(raw)>65536:raise AuthorizationError('JSON too large')
 return json.loads(raw,object_pairs_hook=pairs,parse_constant=lambda x:(_ for _ in ()).throw(AuthorizationError('nonfinite JSON')))
@contextlib.contextmanager
def state_lock(path):
 lock=Path(str(path)+'.lock');deadline=time.monotonic()+5
 while True:
  try:fd=os.open(lock,os.O_CREAT|os.O_EXCL|os.O_WRONLY,0o600);os.close(fd);break
  except FileExistsError:
   if time.monotonic()>deadline:raise AuthorizationError('state locked; no stale lock is removed automatically')
   time.sleep(.01)
 try:yield
 finally:lock.unlink()
def atomic_json(path,value):
 path=Path(path);path.parent.mkdir(parents=True,exist_ok=True)
 fd,name=tempfile.mkstemp(dir=path.parent,prefix='state-',suffix='.tmp')
 try:
  with os.fdopen(fd,'w',encoding='utf8') as f:json.dump(value,f,sort_keys=True,indent=2);f.write('\n');f.flush();os.fsync(f.fileno())
  os.replace(name,path)
 finally:Path(name).unlink(missing_ok=True)
def initialize_state(path,target,hardware_id,floor):
 exact_int(floor,0,0xffffffff,'floor')
 if Path(path).exists():raise AuthorizationError('refuse to replace an existing trust state')
 atomic_json(path,dict(schema=1,target=target,hardware_id=hardware_id,floor=floor,used_nonces=[],generation=0))
def validate_manifest(document,signature,public_key,*,target,hardware_id,nonce,now,floor):
 if not isinstance(document,dict) or set(document)!={'schema','target','hardware_id','nonce','version','issued_at','expires_at','files'}:raise AuthorizationError('manifest schema')
 if document['schema']!=1 or type(document['schema']) is not int:raise AuthorizationError('manifest version')
 if document['target']!=target or document['hardware_id']!=hardware_id:raise AuthorizationError('wrong target')
 if not re.fullmatch('[0-9a-f]{64}',hardware_id):raise AuthorizationError('hardware_id must be a 256-bit hex value')
 if not isinstance(nonce,str) or not re.fullmatch('[0-9a-f]{64}',nonce) or document['nonce']!=nonce:raise AuthorizationError('wrong session nonce')
 version=exact_int(document['version'],0,0xffffffff,'version')
 if version<floor:raise AuthorizationError('rollback rejected')
 issued=exact_int(document['issued_at'],0,2**63-1,'issued_at');expires=exact_int(document['expires_at'],0,2**63-1,'expires_at')
 if issued>now or now>expires or expires<issued:raise AuthorizationError('expired or future manifest')
 files=document['files']
 if not isinstance(files,list) or not 1<=len(files)<=16:raise AuthorizationError('file count')
 names=set()
 for f in files:
  if not isinstance(f,dict) or set(f)!={'name','length','sha256'}:raise AuthorizationError('file schema')
  name=f['name']
  if not isinstance(name,str) or not re.fullmatch(r'[A-Za-z0-9_.-]{1,32}',name) or name in ('.','..'):raise AuthorizationError('unsafe filename')
  if name.casefold() in names:raise AuthorizationError('duplicate/case-colliding filename')
  names.add(name.casefold());exact_int(f['length'],0,4096,'length')
  if not isinstance(f['sha256'],str) or not re.fullmatch('[0-9a-f]{64}',f['sha256']):raise AuthorizationError('SHA256 encoding')
 try:
  if len(signature)!=64 or len(public_key)!=32:raise InvalidSignature
  Ed25519PublicKey.from_public_bytes(public_key).verify(signature,canonical(document))
 except (InvalidSignature,ValueError) as e:raise AuthorizationError('Ed25519 verification failed') from e
 return document

def grant_writes(document,*,rule_id,lease_cycles,floor):
 exact_int(rule_id,0,15,'rule_id');exact_int(lease_cycles,1,0xffffffff,'lease_cycles')
 writes=[(0x80+rule_id*4,floor)]
 hardware=int(document['hardware_id'],16)
 for index,f in enumerate(document['files']):
  name=f['name'].encode('ascii');words=[0]*32;words[0]=1|(rule_id<<4)|(len(name)<<16);words[1]=document['version'];words[2]=f['length'];words[3]=lease_cycles
  digest=bytes.fromhex(f['sha256'])
  for k in range(8):words[4+k]=int.from_bytes(digest[k*4:k*4+4],'big')
  padded=name.ljust(32,b'\0')
  for k in range(8):words[12+k]=int.from_bytes(padded[k*4:k*4+4],'little');words[20+k]=(hardware>>(32*k))&0xffffffff
  for k in range(4):words[28+k]=int.from_bytes(bytes.fromhex(document['nonce'])[k*4:k*4+4],'big')
  writes.extend((0x1000+index*128+k*4,v) for k,v in enumerate(words))
 # Explicitly revoke unused old grant slots in the shadow bank.
 for index in range(len(document['files']),16):writes.append((0x1000+index*128,0))
 return writes

def authorize(document,signature,public_key,*,state_path,target,hardware_id,nonce,now,rule_id,lease_cycles):
 state_path=Path(state_path)
 if not state_path.is_file() or state_path.is_symlink():raise AuthorizationError('provisioned persistent trust state required')
 with state_lock(state_path):
  state=load_json(state_path)
  if state.get('schema')!=1 or state.get('target')!=target or state.get('hardware_id')!=hardware_id:raise AuthorizationError('trust state identity')
  floor=exact_int(state.get('floor'),0,0xffffffff,'stored floor')
  checked=validate_manifest(document,signature,public_key,target=target,hardware_id=hardware_id,nonce=nonce,now=now,floor=floor)
  if nonce in state['used_nonces']:raise AuthorizationError('manifest nonce already consumed')
  writes=grant_writes(checked,rule_id=rule_id,lease_cycles=lease_cycles,floor=floor)
  state['used_nonces'].append(nonce);atomic_json(state_path,state)
  return dict(schema=1,target=target,version=checked['version'],floor=floor,manifest_sha256=hashlib.sha256(canonical(checked)).hexdigest(),public_key_sha256=hashlib.sha256(public_key).hexdigest(),writes=[dict(address=a,value=v) for a,v in writes],commit_required=True,signature_algorithm='Ed25519',file_hash='SHA-256',trust_boundary='trusted host key/state/control bus; no on-chip Ed25519 or secure NVM claim')
def confirm_publication(state_path,*,target,version,generation):
 """Called only by the trusted monitor after observing actual core publication.
 The separate admin action cannot be authorized by a network loading peer.
 """
 exact_int(version,0,0xffffffff,'version');exact_int(generation,1,0xffffffff,'generation')
 with state_lock(state_path):
  state=load_json(state_path)
  if state['target']!=target or version<state['floor'] or generation<=state['generation']:raise AuthorizationError('stale or wrong publication receipt')
  state['floor']=version;state['generation']=generation;atomic_json(state_path,state)

def main():
 ap=argparse.ArgumentParser();ap.add_argument('manifest',type=Path);ap.add_argument('--signature',type=Path,required=True);ap.add_argument('--public-key',type=Path,required=True);ap.add_argument('--state',type=Path,required=True);ap.add_argument('--target',required=True);ap.add_argument('--hardware-id',required=True);ap.add_argument('--nonce',required=True);ap.add_argument('--rule',type=int,required=True);ap.add_argument('--lease-cycles',type=int,required=True);ap.add_argument('--out',type=Path,required=True);a=ap.parse_args()
 result=authorize(load_json(a.manifest),a.signature.read_bytes(),a.public_key.read_bytes(),state_path=a.state,target=a.target,hardware_id=a.hardware_id,nonce=a.nonce,now=int(time.time()),rule_id=a.rule,lease_cycles=a.lease_cycles)
 atomic_json(a.out,result);print('AUTHORIZATION_PASS; grant writes generated; no core configuration modified')
if __name__=='__main__':main()
