"""Reproducible community/USM BER test vectors and expected semantics."""
from pathlib import Path
import json,sys
R=Path(__file__).resolve().parents[1];sys.path.insert(0,str(R/'vendor'))
from pyasn1.codec.ber import encoder
from pyasn1.type import univ
ENGINE=bytes.fromhex('80007ed90541464458')
def tlv(t,b):
 n=len(b);return bytes([t])+ (bytes([n]) if n<128 else bytes([0x81,n]) if n<256 else b'\x82'+n.to_bytes(2,'big'))+b
def integer(n):return encoder.encode(univ.Integer(n))
def oid(n):return encoder.encode(univ.ObjectIdentifier(n))
PREFIX='1.3.6.1.4.1.32473.1.1.'
def pdu(op=0xa0,oids=(1,),rid=7,repetitions=0):
 bindings=b''.join(tlv(0x30,oid(PREFIX+str(n) if isinstance(n,int) else n)+(integer(9) if op==0xa3 else b'\x05\0')) for n in oids)
 return tlv(op,integer(rid)+integer(0)+integer(repetitions)+tlv(0x30,bindings))
def community(version,p,comm=b'public'):return tlv(0x30,integer(version)+tlv(4,comm)+p)
def v3(p,engine=ENGINE,user=b'afdx',flags=4,maxsize=512,model=3,context=b'',ctxengine=ENGINE,auth=b'',priv=b'',msgid=22,encrypted=False):
 head=tlv(0x30,integer(msgid)+integer(maxsize)+tlv(4,bytes([flags]))+integer(model))
 sec=tlv(0x30,tlv(4,engine)+integer(1)+integer(0)+tlv(4,user)+tlv(4,auth)+tlv(4,priv))
 scoped=tlv(4,b'ciphertext') if encrypted else tlv(0x30,tlv(4,ctxengine)+tlv(4,context)+p)
 return tlv(0x30,integer(3)+head+tlv(4,sec)+scoped)
rows=[]
def add(name,raw,version=3,status=0,index=0,report=0,drop=False,rid=7,objects=None):
 rows.append(dict(name=name,request=raw.hex(),version=version,status=status,index=index,report=report,drop=drop,rid=rid,objects=objects))
for ver in (0,1):
 add(f'community{ver}_get',community(ver,pdu()),ver,objects=[1])
 add(f'community{ver}_next',community(ver,pdu(0xa1,(0,))),ver,objects=[1])
 add(f'community{ver}_missing',community(ver,pdu(0xa0,(1,26))),ver,status=2 if ver==0 else 0,index=2 if ver==0 else 0)
 add(f'community{ver}_end',community(ver,pdu(0xa1,(25,))),ver,status=2 if ver==0 else 0,index=1 if ver==0 else 0)
 add(f'community{ver}_set',community(ver,pdu(0xa3)),ver,status=2 if ver==0 else 17,index=1)
 add(f'community{ver}_badcommunity',community(ver,pdu(),b'bad'),ver,drop=True)
add('v1_bulk_rejected',community(0,pdu(0xa5,repetitions=2)),0,drop=True)
add('discovery',v3(pdu(oids=()),engine=b'',user=b'',ctxengine=b''),report=4,rid=0)
add('v3_get',v3(pdu()),objects=[1])
add('v3_next',v3(pdu(0xa1,(0,),rid=-129),msgid=0x7fffffff),rid=-129,objects=[1])
add('v3_set',v3(pdu(0xa3)),status=17,index=1)
add('v3_bulk',v3(pdu(0xa5,(0,),repetitions=2)),objects=[1,2])
add('v3_long_lengths',v3(pdu(oids=tuple(range(1,17)))))
add('v3_tooBig',v3(pdu(0xa5,(0,),repetitions=25),maxsize=484),status=1)
add('v3_wrong_engine',v3(pdu(),engine=b'wrong'),report=4,rid=0)
add('v3_wrong_user',v3(pdu(),user=b'bad'),report=3,rid=0)
add('v3_auth_unsupported',v3(pdu(),flags=5,auth=b'0'*12),report=1,rid=0)
add('v3_priv_unsupported',v3(pdu(),flags=7,auth=b'0'*12,priv=b'1'*8,encrypted=True),report=1,rid=0)
add('v3_silent_security_failure',v3(pdu(),engine=b'',flags=0),drop=True)
add('v3_priv_without_auth',v3(pdu(),flags=6),drop=True)
add('v3_reserved_flags',v3(pdu(),flags=0x84),drop=True)
add('v3_bad_model',v3(pdu(),model=2),drop=True)
add('v3_small_max',v3(pdu(),maxsize=483),drop=True)
add('v3_bad_context',v3(pdu(),context=b'other'),drop=True)
add('v3_bad_context_engine',v3(pdu(),ctxengine=b'other'),drop=True)
add('v3_nonempty_auth_noauth',v3(pdu(),auth=b'0'),drop=True)
add('v3_truncated',v3(pdu())[:-1],drop=True)
add('v3_trailing',v3(pdu())+b'\0',drop=True)
for ver in (0,1,3):
 raw=community(ver,pdu()) if ver!=3 else v3(pdu())
 add(f'recovery_{ver}',raw,ver,objects=[1])
(R/'tb/snmp_versions.json').write_text(json.dumps(rows,indent=2)+'\n')
(R/'tb/snmp_versions.vh').write_text('\n'.join(f'query({i},4096\'h{bytes.fromhex(r["request"])[::-1].hex()},{len(bytes.fromhex(r["request"]))},{int(r["drop"])});' for i,r in enumerate(rows))+'\n')
print('SNMP_VERSION_VECTORS',len(rows))
