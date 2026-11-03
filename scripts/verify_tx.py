"""Decode captured TX independently; check exact fragmentation and app bytes."""
from pathlib import Path
import binascii,json,re,struct,sys
p=Path(sys.argv[1]);text=p.read_text(errors='replace')
def require(ok,why):
 if not ok:raise ValueError(why)
def checksum(b):
 b+=bytes(len(b)%2);s=sum(struct.unpack('!%dH'%(len(b)//2),b))
 while s>>16:s=(s&65535)+(s>>16)
 return s
expected={}
for case,vl,ident,n,seed in re.findall(r'TX_EXPECT case=(\d+) vl=(\d+) id=(\d+) bytes=(\d+) seed=(\d+)',text):
 expected[(int(case),int(vl),int(ident))]=(int(n),int(seed))
require(len(expected)==30,'missing TX fixture declarations')
for case,vl,ident in re.findall(r'TX_SUPERSEDED case=(\d+) vl=(\d+) id=(\d+)',text):
 key=tuple(map(int,(case,vl,ident)));require(key in expected,'unknown superseded sample');del expected[key]
contexts={};complete={};last_seq={};last_start={};frames=0
for line in p.with_name('tx_wire.txt').read_text().splitlines():
 case,end,lmax,h=line.split();case=int(case);lmax=int(lmax);raw=bytes.fromhex(h);f=raw[8:-4]
 require(raw[:8]==b'\x55'*7+b'\xd5','preamble');require(64<=len(raw)-8<=lmax,'LMAX')
 require(binascii.crc32(f).to_bytes(4,'little')==raw[-4:],'FCS')
 require(f[:5]==bytes.fromhex('0300000000') and f[6]&1==0 and f[12:14]==b'\x08\0','Ethernet addressing')
 vl=f[5]-2;ip=f[14:34];require(ip[0]==0x45 and ip[8:10]==b'\x01\x11' and checksum(ip)==65535,'IPv4 header')
 n,ident,flags=struct.unpack('!HHH',ip[2:8]);off=(flags&8191)*8;more=bool(flags&8192);payload=f[34:14+n]
 require(20<n<=len(f)-15 and flags&0xc000==0,'IP length/flags')
 require(not more or len(payload)%8==0,'fragment alignment')
 key=(case,vl,ident);require(key in expected and key not in complete,'unrequested datagram/id')
 size,seed=expected[key];remaining=size+8-off;cap=lmax-39
 require(len(payload)==(cap//8*8 if remaining>cap else remaining),'not using configured fragmentation boundary')
 require(more==(remaining>cap),'MF condition')
 if off==0:require(key not in contexts,'new first fragment overlaps');contexts[key]=bytearray()
 require(key in contexts and off==len(contexts[key]),'offset/order')
 contexts[key].extend(payload)
 skey=(case,vl);seq=f[-1]
 require(seq==(0 if skey not in last_seq else 1 if last_seq[skey]==255 else last_seq[skey]+1),'per-VL sequence')
 last_seq[skey]=seq;start=int(end)-len(raw)*80000
 if skey in last_start:require(start-last_start[skey]>=12500*80000,'BAG')
 last_start[skey]=start;frames+=1
 if not more:
  udp=bytes(contexts.pop(key));sp,dp,length,ck=struct.unpack('!HHHH',udp[:8])
  require((sp,dp,length,ck)==(10000,10001+vl,size+8,0),'UDP header')
  require(udp[8:]==bytes((seed+i*7)&255 for i in range(size)),'application bytes')
  complete[key]=dict(case=case,vl=vl,id=ident,bytes=size)
require(not contexts and set(complete)==set(expected),'incomplete TX messages')
result=dict(status='PASS',messages=len(complete),physical_frames=frames,details=list(complete.values()))
p.with_name('tx_audit.json').write_text(json.dumps(result,indent=2)+'\n');print('DATAGRAM_TX_AUDIT_PASS',json.dumps(result))