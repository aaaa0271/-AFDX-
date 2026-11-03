"""Independent decoding of wire responses with vendored PySNMP ASN.1 types."""
from pathlib import Path
import re,sys,json
R=Path(__file__).resolve().parents[1];sys.path.insert(0,str(R/'vendor'))
from pyasn1.codec.ber import decoder
from pysnmp.proto.api import v1,v2c
from pysnmp.proto.mpmod.rfc3412 import SNMPv3Message
from pysnmp.proto.secmod.rfc3414.service import UsmSecurityParameters
rows=json.loads((R/'tb/snmp_versions.json').read_text())
log=Path(sys.argv[1]);matches=re.findall(r'VERSION_RESPONSE id=(\d+) drop=(\d+) hex=([0-9a-f]*)',log.read_text(errors='replace'))
assert len(matches)==len(rows),(len(matches),len(rows))
for (idx,drop,hexdata),row in zip(matches,rows):
 assert int(idx)==rows.index(row)
 assert bool(int(drop))==row['drop'],row['name']
 if row['drop']:assert not hexdata;continue
 raw=bytes.fromhex(hexdata)
 if row['version']==3:
  msg,tail=decoder.decode(raw,asn1Spec=SNMPv3Message());assert not tail
  request,_=decoder.decode(bytes.fromhex(row['request']),asn1Spec=SNMPv3Message())
  assert int(msg['msgGlobalData']['msgID'])==int(request['msgGlobalData']['msgID'])
  assert bytes(msg['msgGlobalData']['msgFlags'])==b'\0'
  assert int(msg['msgGlobalData']['msgSecurityModel'])==3
  assert len(raw)<=int(request['msgGlobalData']['msgMaxSize'])
  sec,tail=decoder.decode(bytes(msg['msgSecurityParameters']),asn1Spec=UsmSecurityParameters());assert not tail
  assert bytes(sec['msgAuthoritativeEngineId'])==bytes.fromhex('80007ed90541464458')
  assert int(sec['msgAuthoritativeEngineBoots'])==1
  assert not bytes(sec['msgAuthenticationParameters']) and not bytes(sec['msgPrivacyParameters'])
  scoped=msg['msgData']['plaintext'];assert bytes(scoped['contextEngineId'])==bytes(sec['msgAuthoritativeEngineId'])
  pdu=scoped['data'].getComponent();api=v2c.apiPDU
  assert scoped['data'].getName()==('report' if row['report'] else 'response')
 else:
  mod=v1 if row['version']==0 else v2c;msg,tail=decoder.decode(raw,asn1Spec=mod.Message());assert not tail
  assert int(msg['version'])==row['version'];assert bytes(msg['community'])==b'public'
  pdu=mod.apiMessage.get_pdu(msg);api=mod.apiPDU
 assert int(api.get_request_id(pdu))==row['rid'],row['name']
 assert int(api.get_error_status(pdu))==row['status'],(row['name'],pdu.prettyPrint())
 assert int(api.get_error_index(pdu))==row['index'],row['name']
 binds=api.get_varbinds(pdu)
 if row['report']:
  assert str(binds[0][0])=='1.3.6.1.6.3.15.1.1.'+str(row['report'])+'.0'
  assert int(binds[0][1])>0
 elif row['objects']:
  assert [str(b[0]) for b in binds]==['1.3.6.1.4.1.32473.1.1.'+str(i) for i in row['objects']]
  assert int(binds[0][1])==123456,row['name']
 if row['status']==1:assert not binds
print('SNMP_VERSIONS_INDEPENDENT_PASS cases='+str(len(rows)))
