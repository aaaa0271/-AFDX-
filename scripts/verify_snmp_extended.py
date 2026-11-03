from pathlib import Path
import sys,json,re
r=Path(__file__).resolve().parents[1];sys.path.insert(0,str(r/'vendor'))
from pysnmp.proto.api import v2c
from pyasn1.codec.ber import decoder,encoder
base=(1,3,6,1,4,1,32473,1,1);known=[base+(i,) for i in range(1,26)]
vals=[0x060a01,0,0x87654321,7,3]+[100+i for i in range(20)]
vectors=json.loads((r/'tb/snmp_extended_vectors.json').read_text());log=Path(sys.argv[1]);responses=re.findall(r'EXT_RESPONSE case=(\d+) reject=(\d+) hex=([0-9a-f]*)',log.read_text(errors='replace'));assert len(responses)==len(vectors)
rows=[];snapshots=0
for index,reject,hexdata in responses:
 v=vectors[int(index)]
 if v['reject']:
  assert reject=='1' and hexdata=='';rows.append({'case':v['name'],'result':'REJECT_AS_EXPECTED'});continue
 snapshots+=1;msg,tail=decoder.decode(bytes.fromhex(hexdata),asn1Spec=v2c.Message());assert not tail
 pdu=v2c.apiMessage.get_pdu(msg);assert isinstance(pdu,v2c.ResponsePDU)
 assert bytes(v2c.apiMessage.get_community(msg)).decode()==v['community']
 assert int(v2c.apiPDU.get_request_id(pdu))==v['rid']
 assert int(v2c.apiPDU.get_error_status(pdu))==v['status']
 bindings=v2c.apiPDU.get_varbinds(pdu)
 if v['status']==1:assert not bindings
 elif v['status']==17:
  assert int(v2c.apiPDU.get_error_index(pdu))==1 and len(bindings)==1
  assert tuple(bindings[0][0])==tuple(v['oids'][0]) and int(bindings[0][1])==99
 else:
  assert len(bindings)==len(v['oids'])
  for request_oid,(response_oid,value) in zip(v['oids'],bindings):
   q=tuple(request_oid);wanted=next((x for x in known if x>q),None) if v['next'] else q if q in known else None
   if wanted is None:
    assert tuple(response_oid)==q
    assert value.tagSet==(v2c.EndOfMibView('') if v['next'] else v2c.NoSuchObject('')).tagSet
   else:
    assert tuple(response_oid)==wanted,(tuple(response_oid),wanted)
    obj=wanted[-1];assert int(value)==(snapshots if obj==2 else vals[obj-1]),(obj,value)
 assert encoder.encode(msg)==bytes.fromhex(hexdata)
 rows.append({'case':v['name'],'result':'PASS','response_bytes':len(hexdata)//2})
log.with_name('pysnmp_extended_verification.json').write_text(json.dumps(rows,indent=2));print('PYSNMP_EXTENDED_PASS',len(rows))
