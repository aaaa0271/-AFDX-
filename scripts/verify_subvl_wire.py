"""Independent byte-level audit of integrated four-VL/four-Sub-VL traffic."""
from pathlib import Path
import binascii,json,struct,sys

def require(ok,why):
 if not ok:raise ValueError(why)
def checksum(b):
 b+=b'\0'*(len(b)&1);n=sum(int.from_bytes(b[i:i+2],'big') for i in range(0,len(b),2))
 while n>>16:n=(n&65535)+(n>>16)
 return n
p=Path(sys.argv[1]);contexts={};counts={};lastseq={};laststart={};lastend={};selections={};messages=[];gaps=[];frames=0
for line in p.read_text().splitlines():
 direction,stamp,h=line.split();raw=bytes.fromhex(h);end=int(stamp);start=end-len(raw)*80000
 require(direction in ('A','B') and raw[:8]==b'\x55'*7+b'\xd5','preamble/network')
 f=raw[8:-4];require(60<=len(f)<=1514 and binascii.crc32(f).to_bytes(4,'little')==raw[-4:],'FCS/length')
 require(f[:5]==bytes.fromhex('0300000000') and 2<=f[5]<=5,'configured VL address')
 require(f[6:11]==bytes.fromhex('0200000010') and f[11]==(0x20 if direction=='A' else 0x40),'A/B source Interface ID')
 vl=f[5]-2;key=(direction,vl);ip=f[14:34];total=int.from_bytes(ip[2:4],'big');flag=int.from_bytes(ip[6:8],'big');off=(flag&8191)*8;more=bool(flag&8192)
 require(ip[0]==0x45 and ip[8:10]==b'\x01\x11' and checksum(ip)==65535,'IPv4 fields/checksum')
 require(ip[12:16]==bytes([10,0,0,1]) and ip[16:20]==bytes([10,0,0,vl+2]),'configured IP tuple')
 require(20<total<=len(f)-15 and not flag&0xc000,'IPv4/sequence boundary')
 payload=f[34:14+total];require(not more or len(payload)%8==0,'fragment alignment')
 expected_seq=0 if key not in lastseq else 1 if lastseq[key]==255 else lastseq[key]+1
 require(f[-1]==expected_seq,'Sub-VLs did not share one ordered VL sequence domain');lastseq[key]=f[-1]
 if key in laststart:
  gap=start-laststart[key];require(gap>=12500*80000,'Sub-VLs exceeded aggregate per-VL BAG');gaps.append(gap)
 laststart[key]=start
 if direction in lastend:require(start-lastend[direction]>=12*80000,'physical IFG')
 lastend[direction]=end
 ctx=(direction,vl,int.from_bytes(ip[4:6],'big'))
 if off==0:
  require(ctx not in contexts and len(payload)>=8,'first fragment uniqueness')
  sp,dp,n,ck=struct.unpack('!HHHH',payload[:8]);port=sp-10000
  require(0<=port<16 and port%4==vl and dp==20000+port,'SAP/communication port UDP routing')
  contexts[ctx]=dict(port=port,udp=bytearray(),length=n,checksum=ck)
 require(ctx in contexts and off==len(contexts[ctx]['udp']),'fragment context/order')
 context=contexts[ctx];context['udp'].extend(payload);selections.setdefault(key,[]).append(context['port'])
 if not more:
  context=contexts.pop(ctx);port=context['port'];ordinal=counts.get((direction,port),0);udp=bytes(context['udp'])
  require(len(udp)==context['length'],'UDP datagram length')
  if context['checksum']:require(checksum(ip[12:20]+b'\0\x11'+udp[4:6]+udp)==65535,'UDP checksum')
  if ordinal==0:n=1800+port if port<4 else 1700+port%4 if 8<=port<12 else 40+port;seed=20+port
  elif port==12 and ordinal==1:n=21;seed=200
  elif port==4 and ordinal in (1,2):n=26+ordinal;seed=55 if ordinal==1 else 66
  elif port==15 and ordinal in (1,2):n=1;seed=209+ordinal
  else:raise ValueError('Extra/unrequested message or overwritten sampling value transmitted')
  require(len(udp)==n+8 and udp[8:]==bytes((seed+i*7)&255 for i in range(n)),'Application payload/length/ordering')
  counts[(direction,port)]=ordinal+1;messages.append(dict(network=direction,vl=vl,port=port,ordinal=ordinal,bytes=n,seed=seed))
 frames+=1
require(not contexts,'incomplete reassembly')
for d in ('A','B'):
 for port in range(16):require(counts.get((d,port))==(3 if port in (4,15) else 2 if port==12 else 1),'Missing/extra port message')
 for vl in range(4):require(selections[(d,vl)][:4]==[vl,4+vl,8+vl,12+vl],'Frame-granularity round-robin across Sub-VLs')
require(frames==58 and len(messages)==42,'frame/message cardinality')
result=dict(status='PASS',physical_frames=frames,wire_messages=len(messages),ports=16,subvls_per_vl=4,minimum_same_vl_start_gap_ps=min(gaps),details=messages,scope='Actual redundant MAC bytes; this bounded fixture is not a whole-standard worst-case proof')
p.with_name('subvl_audit.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8');print('SUBVL_WIRE_AUDIT_PASS',frames,len(messages))