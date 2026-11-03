"""Independent raw shared-MAC and PySNMP audit of the actual integrated top."""
from pathlib import Path
import binascii,json,re,struct,sys
R=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(R/'vendor'))
from pysnmp.proto.api import v2c
from pyasn1.codec.ber import decoder,encoder
sys.path.insert(0,str(R/'scripts'))
from verify_service_wire import checksum,require,audit
p=Path(sys.argv[1]);text=p.read_text(errors='replace')
m=re.search(r'SHARED_FINAL mode=(\d+).*errors=0',text);require(m is not None,'missing shared final zero-error marker');mode=int(m[1])
bulk_run='BULK_PROFILE=1' in text
vectors=json.loads((R/('tb/snmp_bulk_vectors.json' if bulk_run else 'tb/snmp_extended_vectors.json')).read_text())
from snmp_bulk_oracle import expected_message
responses={int(i):bytes.fromhex(h) for i,h in re.findall(r'MAC_RESPONSE case=(\d+) hex=([0-9a-f]+)',text)}
snapshots={int(i):[int(h[n:n+8],16) for n in range(0,len(h),8)] for i,h in re.findall(r'MAC_SNAPSHOT case=(\d+) values=([0-9a-f]+)',text)}
base=(1,3,6,1,4,1,32473,1,1);known=[base+(i,) for i in range(1,26)];count=0;rows=[]
for i,v in enumerate(vectors):
 if v['reject']:
  require(i not in responses and i not in snapshots,'malformed request produced a response/snapshot');rows.append(dict(case=v['name'],status='REJECT_AS_EXPECTED'));continue
 count+=1;require(i in responses and i in snapshots,'missing real MAC reply or snapshot')
 msg,tail=decoder.decode(responses[i],asn1Spec=v2c.Message());require(not tail,'trailing BER')
 pd=v2c.apiMessage.get_pdu(msg);require(isinstance(pd,v2c.ResponsePDU),'not ResponsePDU')
 require(int(v2c.apiMessage.get_version(msg))==1 and bytes(v2c.apiMessage.get_community(msg)).decode()==v['community'],'version/community')
 require(int(v2c.apiPDU.get_request_id(pd))==v['rid'] and int(v2c.apiPDU.get_error_status(pd))==v['status'],'request-id/status')
 bindings=v2c.apiPDU.get_varbinds(pd)
 if v.get('bulk'):
  require(responses[i]==expected_message(v,snapshots[i],count),'independent RFC3416 GetBulk response mismatch')
 elif v['status']==1:require(not bindings,'tooBig list')
 elif v['status']==17:
  require(int(v2c.apiPDU.get_error_index(pd))==1 and len(bindings)==1 and tuple(bindings[0][0])==tuple(v['oids'][0]) and int(bindings[0][1])==99,'notWritable echo')
 else:
  require(len(bindings)==len(v['oids']),'VarBind count')
  for q,(oid,val) in zip(v['oids'],bindings):
   q=tuple(q);want=next((x for x in known if x>q),None) if v['next'] else q if q in known else None
   if want is None:
    require(tuple(oid)==q and val.tagSet==(v2c.EndOfMibView('') if v['next'] else v2c.NoSuchObject('')).tagSet,'exception')
   else:
    obj=want[-1];expected=count if obj==2 else snapshots[i][obj-1]
    require(tuple(oid)==want and int(val)==expected,'OID/snapshot value')
 require(encoder.encode(msg)==responses[i],'BER canonical roundtrip')
 rows.append(dict(case=v['name'],status='PASS',response_bytes=len(responses[i])))
require(len(responses)==len(snapshots)==(14 if bulk_run else 8),'response cardinality')
profile=re.search(r'BUSINESS_PROFILE bytes=(\d+) messages=(\d+)',text);require(profile is not None,'missing business fixture profile')
message_bytes,message_count=map(int,profile.groups());reassemblies={};business_messages=[]
wire={x:[] for x in ('A','B','RX_B')};wire_responses=[];last_start={};sequences={}
def _wire(name):
 # Canonical file as published by the bundled runner; fall back to the plugin
 # capture when the harness runs the testbench directly (the testbench has
 # already asserted byte-identical baseline/plugin captures with errors=0).
 q=p.with_name(name)
 if not q.exists() and p.with_name('plugin_'+name).exists():
  q=p.with_name('plugin_'+name)
 return q
for line in _wire('shared_wire.txt').read_text().splitlines():
 direction,stamp,h=line.split();raw=bytes.fromhex(h);require(direction in wire,'wire direction')
 require(raw[:8]==b'\x55'*7+b'\xd5','preamble');f=raw[8:-4]
 require(60<=len(f)<=1514 and binascii.crc32(f).to_bytes(4,'little')==raw[-4:],'FCS/length')
 require(f[6:9]==bytes.fromhex('020000') and f[11]==(0x20 if direction=='A' else 0x40),'AFDX source interface ID');require(f[:3]==bytes.fromhex('030000'),'AFDX destination prefix')
 ip=f[14:34];require(ip[0]==0x45 and ip[9]==17 and checksum(ip)==65535,'IPv4')
 total=int.from_bytes(ip[2:4],'big');fragment=f[34:14+total];flags=int.from_bytes(ip[6:8],'big');offset=(flags&8191)*8;more=bool(flags&8192)
 require(20<total<=len(f)-15 and not flags&0x8000 and not (flags&0x4000 and (more or offset)),'IPv4 fragment bounds/flags')
 require(not more or len(fragment)%8==0,'non-final alignment')
 is_business=f[:5]==bytes.fromhex('0300000000') and 2<=f[5]<=5
 sp=dp=0;udp=b''
 if is_business:
  require(ip[8]==1,'business TTL')
  key=(direction,f[:6],ip[12:20],ip[4:6])
  if offset==0:require(key not in reassemblies,'overlapping datagram ID');reassemblies[key]=bytearray()
  require(key in reassemblies and offset==len(reassemblies[key]),'wire fragment order/offset')
  reassemblies[key].extend(fragment)
  if not more:
   udp=bytes(reassemblies.pop(key));sp,dp,n,ck=struct.unpack('!HHHH',udp[:8]);require(n==len(udp),'reassembled UDP length')
   if ck:require(checksum(ip[12:20]+b'\0\x11'+udp[4:6]+udp)==65535,'UDP checksum')
   if direction=='B':
    ordinal=len(business_messages);require(len(udp)-8==message_bytes,'reassembled app length')
    require(udp[8:]==bytes((31+ordinal+i*7)&255 for i in range(message_bytes)),'independent application bytes')
    business_messages.append(dict(vl=f[5]-2,bytes=message_bytes,ip_id=int.from_bytes(ip[4:6],'big')))
 else:
  require(offset==0 and not more,'unexpected fragmented management/service fixture')
  udp=fragment;sp,dp,n,ck=struct.unpack('!HHHH',udp[:8]);require(n==len(udp),'UDP length')
  if ck:require(checksum(ip[12:20]+b'\0\x11'+udp[4:6]+udp)==65535,'UDP checksum')
 wire[direction].append(raw)
 if direction=='B':
  cls=f[5]-2 if f[:5]==bytes.fromhex('0300000000') and 2<=f[5]<=5 else 4 if sp==161 else 5
  start=int(stamp)-len(raw)*80000
  if cls in last_start:require(start-last_start[cls]>=12500*80000,'physical BAG')
  last_start[cls]=start
  seq=f[-1]
  if cls in sequences:require(seq==(1 if sequences[cls]==255 else sequences[cls]+1),'wire sequence')
  else:require(seq==0,'first sequence')
  sequences[cls]=seq
  if sp==161:require(dp==40009,'SNMP port');wire_responses.append(udp[8:])
require(not reassemblies and len(business_messages)==message_count,'incomplete or missing business messages')
require(wire_responses==list(responses.values()),'wire SNMP differs from receiver log')
def logical_copy(raw):return raw[:19]+b'\0'+raw[20:-4]
if mode!=2:require([logical_copy(x) for x in wire['A']]==[logical_copy(x) for x in wire['B']],'A/B logical frame identity')
else:require(0<len(wire['A'])<len(wire['B']) and [logical_copy(x) for x in wire['A']]==[logical_copy(x) for x in wire['B'][:len(wire['A'])]],'degraded B-only continuity')
measurements={'link_mbps':100,'cycle_ns':80,'tx':[],'rx':[]}
for ordinal,vl,app,start,end in re.findall(r'TX_MEASURE ordinal=(\d+) vl=(\d+) app_end=(\d+) wire_start=(\d+) wire_end=(\d+)',text):
 measurements['tx'].append(dict(ordinal=int(ordinal),vl=int(vl),queue_to_wire_start_ns=(int(start)-int(app))*80,queue_to_wire_end_ns=(int(end)-int(app))*80))
for ordinal,end,app in re.findall(r'RX_MEASURE ordinal=(\d+) wire_end=(\d+) app_end=(\d+)',text):
 measurements['rx'].append(dict(ordinal=int(ordinal),wire_end_to_application_end_ns=(int(app)-int(end))*80))
service=audit(_wire('service_wire.txt')) if mode else None
result=dict(status='PASS',mode=mode,business_messages=business_messages,measurements=measurements,snmp_cases=rows,physical_a_frames=len(wire['A']),physical_b_frames=len(wire['B']),service=service)
p.with_name('shared_audit.json').write_text(json.dumps(result,indent=2)+'\n')
print('SHARED_MAC_AUDIT_PASS',json.dumps(result))