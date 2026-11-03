from pathlib import Path
import sys,json,re
R=Path(__file__).resolve().parents[1];sys.path.insert(0,str(R/'vendor'))
from pysnmp.proto.api import v2c
from pyasn1.codec.ber import decoder,encoder
vectors=json.loads((R/'tb/snmp_manager_vectors.json').read_text());log=Path(sys.argv[1]).read_text(errors='replace')
responses=re.findall(r'PYSNMP_RESPONSE case=(\d+) hex=([0-9a-fA-F]+)',log);assert len(responses)==len(vectors)
rows=[]
for index,hexdata in responses:
 v=vectors[int(index)];wire=bytes.fromhex(hexdata);message,tail=decoder.decode(wire,asn1Spec=v2c.Message());assert not tail
 pdu=v2c.apiMessage.get_pdu(message);assert isinstance(pdu,v2c.ResponsePDU)
 assert int(v2c.apiMessage.get_version(message))==1 and bytes(v2c.apiMessage.get_community(message))==b'public'
 assert int(v2c.apiPDU.get_request_id(pdu))==v['rid']
 assert int(v2c.apiPDU.get_error_status(pdu))==0 and int(v2c.apiPDU.get_error_index(pdu))==0
 bindings=v2c.apiPDU.get_varbinds(pdu);assert len(bindings)==len(v['expected_oids'])
 for (oid,value),want_oid,want_value in zip(bindings,v['expected_oids'],v['expected_values']):
  assert str(oid)==want_oid,(oid,want_oid)
  if want_value=='noSuchObject':assert value.tagSet==v2c.NoSuchObject('').tagSet
  elif want_value=='endOfMibView':assert value.tagSet==v2c.EndOfMibView('').tagSet
  else:assert int(value)==want_value,(value,want_value)
 assert encoder.encode(message)==wire,'noncanonical/trailing response representation'
 rows.append({'case':v['name'],'rid':v['rid'],'status':'PASS','response_bytes':len(wire)})
out=Path(sys.argv[1]).parent/'pysnmp_verification.json';out.write_text(json.dumps({'library':'pysnmp7.1.22/pyasn1 0.6.1','results':rows},indent=2));print('PYSNMP_INTEROP_PASS',len(rows),out)
