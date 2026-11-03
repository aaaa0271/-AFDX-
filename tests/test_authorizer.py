from pathlib import Path
import sys,tempfile,unittest,copy,hashlib
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'host'))
from authorizer import *
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
class AuthorizationTests(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.root=Path(self.tmp.name);self.key=Ed25519PrivateKey.generate();self.public=self.key.public_key().public_bytes_raw();self.hw=f'{0x4d4953:064x}';self.nonce='ab'*32
  self.doc=dict(schema=1,target='SIM',hardware_id=self.hw,nonce=self.nonce,version=7,issued_at=100,expires_at=200,files=[dict(name='A.LUP',length=3,sha256=hashlib.sha256(b'abc').hexdigest())]);self.state=self.root/'state.json';initialize_state(self.state,'SIM',self.hw,6)
 def valid(self,doc=None,**kw):
  doc=doc or self.doc;params=dict(target='SIM',hardware_id=self.hw,nonce=self.nonce,now=150,floor=6);params.update(kw)
  return validate_manifest(doc,self.key.sign(canonical(doc)),self.public,**params)
 def test_real_signature_and_grant_digest_words(self):
  result=self.valid();w=dict(grant_writes(result,rule_id=3,lease_cycles=100000,floor=6));self.assertEqual(w[0x80+12],6);self.assertEqual(w[0x1000+4],7)
  self.assertEqual(''.join(f'{w[0x1000+16+i*4]:08x}' for i in range(8)),self.doc['files'][0]['sha256'])
 def test_signed_mutation_rejected(self):
  sig=self.key.sign(canonical(self.doc));d=copy.deepcopy(self.doc);d['files'][0]['sha256']='00'*32
  with self.assertRaises(AuthorizationError):validate_manifest(d,sig,self.public,target='SIM',hardware_id=self.hw,nonce=self.nonce,now=150,floor=6)
 def test_wrong_key(self):
  with self.assertRaises(AuthorizationError):validate_manifest(self.doc,self.key.sign(canonical(self.doc)),Ed25519PrivateKey.generate().public_key().public_bytes_raw(),target='SIM',hardware_id=self.hw,nonce=self.nonce,now=150,floor=6)
 def test_target_binding(self):
  with self.assertRaises(AuthorizationError):self.valid(target='OTHER')
 def test_hardware_binding(self):
  with self.assertRaises(AuthorizationError):self.valid(hardware_id='00'*32)
 def test_nonce_binding(self):
  with self.assertRaises(AuthorizationError):self.valid(nonce='cd'*32)
 def test_expired(self):
  with self.assertRaises(AuthorizationError):self.valid(now=201)
 def test_future(self):
  with self.assertRaises(AuthorizationError):self.valid(now=99)
 def test_rollback(self):
  with self.assertRaises(AuthorizationError):self.valid(floor=8)
 def test_equal_floor_retry_is_allowed_with_new_nonce(self):self.valid(floor=7)
 def test_nonce_persisted_and_replay_denied(self):
  args=dict(state_path=self.state,target='SIM',hardware_id=self.hw,nonce=self.nonce,now=150,rule_id=3,lease_cycles=100000)
  authorize(self.doc,self.key.sign(canonical(self.doc)),self.public,**args)
  with self.assertRaises(AuthorizationError):authorize(self.doc,self.key.sign(canonical(self.doc)),self.public,**args)
 def test_missing_state_fails_closed(self):
  self.state.unlink()
  with self.assertRaises(AuthorizationError):authorize(self.doc,self.key.sign(canonical(self.doc)),self.public,state_path=self.state,target='SIM',hardware_id=self.hw,nonce=self.nonce,now=150,rule_id=3,lease_cycles=1)
 def test_floor_survives_new_process_state_read(self):
  confirm_publication(self.state,target='SIM',version=9,generation=1);self.assertEqual(load_json(self.state)['floor'],9)
  with self.assertRaises(AuthorizationError):confirm_publication(self.state,target='SIM',version=8,generation=2)
 def test_stale_publication_generation(self):
  confirm_publication(self.state,target='SIM',version=7,generation=1)
  with self.assertRaises(AuthorizationError):confirm_publication(self.state,target='SIM',version=7,generation=1)
 def test_unsafe_and_duplicate_names(self):
  for name in ('../a','a/b','a\\b','.', '..','X'*33,'\x00'):
   d=copy.deepcopy(self.doc);d['files'][0]['name']=name
   with self.assertRaises(AuthorizationError):self.valid(d)
  d=copy.deepcopy(self.doc);d['files'].append(dict(d['files'][0],name='a.lup'))
  with self.assertRaises(AuthorizationError):self.valid(d)
 def test_bad_lengths_and_numeric_types(self):
  for n in (-1,4097,True,1.0):
   d=copy.deepcopy(self.doc);d['files'][0]['length']=n
   with self.assertRaises(AuthorizationError):self.valid(d)
 def test_empty_and_maximum_content_digest(self):
  for n in (0,4096):
   d=copy.deepcopy(self.doc);d['files'][0]['length']=n;d['files'][0]['sha256']=hashlib.sha256(bytes(n)).hexdigest();self.valid(d)
 def test_duplicate_json_key_rejected(self):
  p=self.root/'bad.json';p.write_text('{"version":1,"version":2}')
  with self.assertRaises(AuthorizationError):load_json(p)
 def test_extra_manifest_fields_rejected(self):
  d=copy.deepcopy(self.doc);d['signature_ok']=True
  with self.assertRaises(AuthorizationError):self.valid(d)
 def test_provisioning_cannot_reset_existing_floor(self):
  with self.assertRaises(AuthorizationError):initialize_state(self.state,'SIM',self.hw,0)
if __name__=='__main__':unittest.main()
