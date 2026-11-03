from pathlib import Path
import sys,json,hashlib,random,struct,binascii,tempfile
R=Path(__file__).resolve().parents[1];sys.path.insert(0,str(R/'host'))
from policy import Rule,COMMIT,ROLLBACK
from authorizer import canonical,initialize_state,authorize
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
TB=R/'tb';frames=[];commands=[];cases=[];serial=0
SRC=0x0a000001;DST=0x0a000010;RM=0x030000000010;PM=0x020000000002;TM=0x030000000012
business=Rule(SRC,DST,RM,PM,source_port=100,destination_port=200,tx_mac=TM,timeout=30000)
loader=Rule(SRC,DST,RM,PM,kind=2,tx_mac=TM,timeout=30000)
clock=Rule(SRC,DST,RM,PM,kind=3,source_port=123,destination_port=40001,tx_mac=TM,timeout=30000)
def checksum(b):
 if len(b)%2:b+=b'\0'
 n=sum(int.from_bytes(b[i:i+2],'big') for i in range(0,len(b),2))
 while n>>16:n=(n&65535)+(n>>16)
 return (~n)&65535
def packet(payload=b'hello',sp=100,dp=200,sn=None,tx=False,src=SRC,dst=DST,rm=RM,sm=PM,ip_id=7,fragment=0,ip_payload=None,udp_checksum=True):
 global serial
 if sn is None:sn=serial%255+1;serial+=1
 if tx:src,dst=dst,src;rm=TM;sm=0x020000000010
 u=struct.pack('!HHHH',sp,dp,len(payload)+8,0)+payload
 if udp_checksum:
  c=checksum(src.to_bytes(4,'big')+dst.to_bytes(4,'big')+b'\0\x11'+len(u).to_bytes(2,'big')+u) or 65535;u=u[:6]+c.to_bytes(2,'big')+u[8:]
 data=ip_payload if ip_payload is not None else u
 ip=struct.pack('!BBHHHBBHII',0x45,0,20+len(data),ip_id,fragment,64,17,0,src,dst);ip=ip[:10]+checksum(ip).to_bytes(2,'big')+ip[12:]
 body=rm.to_bytes(6,'big')+sm.to_bytes(6,'big')+b'\x08\0'+ip+data
 body=body.ljust(59,b'\0')+bytes([sn]);return b'\x55'*7+b'\xd5'+body+binascii.crc32(body).to_bytes(4,'little')
def cmd(op,*args,case=0):commands.append([op,*list(args)+[0]*(6-len(args)),case])
def write(addr,val,fail=False):cmd(11 if fail else 1,addr,val)
def reset():cmd(0)
def setup(rule=business,mode=2):
 reset()
 for a,v in rule.writes(0):write(a,v)
 write(0,mode);write(*COMMIT);cmd(4,20);cmd(5,0,mode)
def frame(name,p,ch=0,flags=0,mode=2):
 index=len(frames);frames.append(p);case=len(cases)+1;cases.append(dict(id=case,name=name,frame=index,channel=ch,expected_flags=flags,expected_allow=flags==0,mode=mode));cmd(2,ch,len(p),index,flags,int(flags==0),mode,case=case)
def req(name,op=1):return struct.pack('!H',op)+name.encode()+b'\0octet\0'
def data(block,content):return struct.pack('!HH',3,block)+content
def ack(block):return struct.pack('!HH',4,block)
# Basic ACL, format, true normalized A/B payload comparison.
setup();p=packet(sn=9);frame('whitelist_valid_A',p);q=bytearray(p);q[19]=0x42;q[-4:]=binascii.crc32(q[8:-4]).to_bytes(4,'little');frame('AB_interface_id_difference_legal',bytes(q),ch=1)
frame('unknown_source_ip',packet(src=SRC+9),flags=2)
p=bytearray(packet());p[54]^=1;frame('bad_fcs',bytes(p),flags=1)
p=packet(b'content-one',sn=30);frame('AB_reference',p);q=packet(b'content-two',sn=30);frame('AB_valid_checksums_content_conflict',q,ch=1,flags=4)
# Frozen raw evidence is readable, and only trusted ACK releases it.
cmd(5,0x2000,1);cmd(5,0x2004,next(i for i,(a,b) in enumerate(zip(p[8:-4],q[8:-4]),8) if a!=b))
cmd(5,0x2008,len(p));cmd(5,0x200c,len(q));cmd(5,0x2100,int.from_bytes(p[:4],'little'));cmd(5,0x2900,int.from_bytes(q[:4],'little'))
for base,raw in ((0x2100,p),(0x2900,q)):
 for off in range(0,len(raw),4):cmd(5,base+off,int.from_bytes(raw[off:off+4].ljust(4,b'\0'),'little'))
frame('additional_conflict_reference',packet(b'new-1',sn=31));frame('additional_conflict_evidence_overrun',packet(b'new-2',sn=31),ch=1,flags=4)
cmd(5,0x2020,1);cmd(5,0x2008,len(p))
write(0x2000,0,True);write(0x2000,0x41434b31);cmd(5,0x2000,0)

setup(mode=1);frame('shadow_does_not_block_unknown_source',packet(src=SRC+9),flags=2,mode=1)
setup(mode=0);frame('bypass_preserves_invalid_crc',bytes(p[:-1]+bytes([p[-1]^1])),flags=1,mode=0)
# Denied A copy must not gain permission merely by arriving through B.
setup();p=packet(src=SRC+9,sn=44);frame('denied_A',p,flags=2);frame('denied_B',p,ch=1,flags=2)
# Resource budgets and fragment-state isolation.
f=Rule(**dict(business.__dict__,fragments=True,max_contexts=1))
setup(f)
u=struct.pack('!HHHH',100,200,40,0)+bytes(range(16));frame('reserve_fragment_context',packet(ip_id=90,fragment=0x2000,ip_payload=u))
frame('second_unfinished_message_quota',packet(ip_id=91,fragment=0x2000,ip_payload=u),flags=32)
frame('orphan_fragment',packet(ip_id=92,fragment=3,ip_payload=bytes(16)),flags=512)
frame('wrong_fragment_offset',packet(ip_id=90,fragment=4,ip_payload=bytes(16)),flags=2048)
frame('finish_fragment_context',packet(ip_id=90,fragment=3,ip_payload=bytes(16)))
frame('quota_released_after_completion',packet(ip_id=91,fragment=0x2000,ip_payload=u))
cmd(4,31000);frame('orphan_after_reservation_timeout',packet(ip_id=91,fragment=3,ip_payload=bytes(16)),flags=512)
# Distinct port-qualified flows sharing VL/IP/MAC retain their own fragment rule.
setup(f)
f2=Rule(**dict(f.__dict__,source_port=101,destination_port=201))
for a,v in f2.writes(1):write(a,v)
write(*COMMIT);cmd(4,20)
frame('first_flow_reservation',packet(ip_id=95,fragment=0x2000,ip_payload=u))
u2=struct.pack('!HHHH',101,201,25,0)+bytes(range(16))
frame('other_flow_has_independent_quota',packet(ip_id=96,fragment=0x2000,ip_payload=u2))
frame('tiny_final_fragment_uses_original_rule',packet(ip_id=96,fragment=3,ip_payload=b'X'))
frame('original_flow_context_unchanged',packet(ip_id=95,fragment=3,ip_payload=bytes(16)))
# Explicit trusted safe boundary and failed writes while commit is pending.
setup();cmd(6,0);write(0,1);write(*COMMIT);cmd(4,10);cmd(5,0,2);write(0,0,True);cmd(6,1);cmd(4,20);cmd(5,0,1)
# Unconfigured fail-closed boot has no implicit allow rule.
reset();frame('default_boot_denies_unconfigured_peer',packet(),flags=2)
# Rate window: physical A/B duplicates only debit one logical packet.
r=Rule(**dict(business.__dict__,window=20000,max_frames=1))
setup(r);p=packet(sn=51);frame('one_budgeted_message',p);frame('duplicate_not_charged_twice',p,ch=1);frame('window_budget_denies_extra',packet(),flags=16);cmd(4,21000);frame('budget_recovers',packet())
# Session stage and dynamic TID authorization.
setup(loader);frame('LUR_before_LUI',packet(req('TARGET.LUR',2),sp=32000,dp=69),flags=8)
frame('initialize_stage',packet(req('TARGET.LUI'),sp=32000,dp=69));frame('LUI_ack',packet(ack(1),sp=32000,dp=41000))
frame('LUR_stage',packet(req('TARGET.LUR',2),sp=32000,dp=69));frame('wrong_control_tid',packet(data(1,b'X'),sp=32001,dp=41000),flags=128)
frame('legal_control_data',packet(data(1,b'X'),sp=32000,dp=41000));frame('local_file_request',packet(req('A.LUP'),sp=42000,dp=69,tx=True),ch=2)
frame('out_of_order_file_block',packet(data(2,b'abc'),sp=30000,dp=42000),flags=128)
frame('file_data',packet(data(1,b'abc'),sp=30000,dp=42000));frame('legal_retransmission',packet(data(1,b'abc'),sp=30000,dp=42000));frame('same_block_changed_data',packet(data(1,b'abd'),sp=30000,dp=42000),flags=128)
frame('file_wrong_tid',packet(data(1,b'abc'),sp=30001,dp=42000),flags=128)
frame('final_report_open',packet(req('TARGET.LUS',2),sp=40002,dp=69,tx=True),ch=2);frame('report_tid_negotiation',packet(ack(0),sp=30002,dp=40002))
lus=bytearray(32);lus[6:8]=b'\0\3';frame('success_status',packet(data(1,bytes(lus)),sp=40002,dp=30002,tx=True),ch=2);frame('final_status_ack',packet(ack(1),sp=30002,dp=40002));frame('next_session_initialization',packet(req('TARGET.LUI'),sp=32000,dp=69))
# Atomic commit waits for session expiry; no half-updated active rule.
setup(loader);frame('policy_wait_session',packet(req('TARGET.LUI'),sp=32000,dp=69));write(0,1);write(*COMMIT);cmd(4,20);cmd(5,0,2);cmd(5,4,6);cmd(4,31000);cmd(5,0,1);write(*ROLLBACK);cmd(4,20);cmd(5,0,2)
write(0,7,True);write(0x82,1,True);write(0x80,5);write(0x80,4,True)
# NTP origin, stratum, latency and time-step policy.
setup(Rule(**dict(clock.__dict__,strict_initial_time=True)));request=bytearray(48);request[0]=0x23;t1=0x1234567800000000;request[40:48]=t1.to_bytes(8,'big')
frame('NTP_poll',packet(bytes(request),sp=40001,dp=123,tx=True),ch=2)
response=bytearray(48);response[0]=0x24;response[1]=1;response[24:32]=t1.to_bytes(8,'big');response[32:40]=(t1+100).to_bytes(8,'big');response[40:48]=(t1+200).to_bytes(8,'big')
bad=bytearray(response);bad[31]^=1;frame('NTP_wrong_origin',packet(bytes(bad),sp=123,dp=40001),flags=256)
bad=bytearray(response);bad[1]=0;frame('NTP_unsynchronized_stratum',packet(bytes(bad),sp=123,dp=40001),flags=256)
bad=bytearray(response);bad[40:48]=(t1+(4<<32)).to_bytes(8,'big');frame('NTP_jump_above_limit',packet(bytes(bad),sp=123,dp=40001),flags=256)
frame('NTP_valid_recovery',packet(bytes(response),sp=123,dp=40001))
frame('NTP_unsolicited_replay',packet(bytes(response),sp=123,dp=40001),flags=256)
setup(clock);write(0x20,1000);write(*COMMIT);cmd(4,20)
frame('delayed_NTP_poll',packet(bytes(request),sp=40001,dp=123,tx=True),ch=2);cmd(4,1100)
frame('NTP_excess_round_trip',packet(bytes(response),sp=123,dp=40001),flags=256)
# Cold acquisition may establish an unknown epoch; later steps are bounded.
setup(clock);frame('cold_NTP_poll',packet(bytes(request),sp=40001,dp=123,tx=True),ch=2)
cold=bytearray(response);cold[40:48]=(t1+(100<<32)).to_bytes(8,'big')
frame('cold_NTP_acquisition_reanchors',packet(bytes(cold),sp=123,dp=40001))
frame('established_NTP_poll',packet(bytes(request),sp=40001,dp=123,tx=True),ch=2)
frame('established_NTP_jump_rejected',packet(bytes(cold),sp=123,dp=40001),flags=256)
# Real host Ed25519 authorization drives RTL SHA256 grants.
key=Ed25519PrivateKey.generate();hw=f'{0x4d4953:064x}';contents={}
for name,n in [('EMPTY.LUP',0),('SMALL.LUP',3),('EXACT.LUP',512),('MAX.LUP',4096)]:contents[name]=bytes((k*17+3)%256 for k in range(n))
document=dict(schema=1,target='SIM',hardware_id=hw,nonce='ab'*32,version=7,issued_at=100,expires_at=200,files=[dict(name=n,length=len(c),sha256=hashlib.sha256(c).hexdigest()) for n,c in contents.items()])
with tempfile.TemporaryDirectory() as temp:
 state=Path(temp)/'state.json';initialize_state(state,'SIM',hw,6)
 receipt=authorize(document,key.sign(canonical(document)),key.public_key().public_bytes_raw(),state_path=state,target='SIM',hardware_id=hw,nonce='ab'*32,now=150,rule_id=0,lease_cycles=10000000)
(TB/'authorization_receipt.json').write_text(json.dumps(receipt,indent=2)+'\n');(TB/'signed_manifest.json').write_text(json.dumps(document,indent=2)+'\n');(TB/'manifest.sig').write_bytes(key.sign(canonical(document)));(TB/'manifest_public_key.bin').write_bytes(key.public_key().public_bytes_raw())
signed_loader=Rule(**dict(loader.__dict__,signed_loading=True))
def signed_setup():
 setup(signed_loader)
 for w in receipt['writes']:write(w['address'],w['value'])
 write(*COMMIT);cmd(4,20)
 frame('signed_initialize',packet(req('TARGET.LUI'),sp=32000,dp=69));frame('signed_LUR',packet(req('TARGET.LUR',2),sp=32000,dp=69))
signed_setup();frame('unsigned_filename_request',packet(req('UNKNOWN.LUP'),sp=42000,dp=69,tx=True),ch=2,flags=64);frame('unauthorized_data_denied',packet(data(1,b'evil'),sp=30000,dp=42000),flags=8)
for ix,(name,content) in enumerate(contents.items()):
 tid=42001+ix;frame('authorized_RRQ_'+name,packet(req(name),sp=tid,dp=69,tx=True),ch=2)
 chunks=[content[i:i+512] for i in range(0,len(content),512)]
 if len(content)%512==0:chunks.append(b'')
 for block,chunk in enumerate(chunks,1):frame('authorized_DATA_'+name+'_'+str(block),packet(data(block,chunk),sp=30000,dp=tid))
 frame('authorized_final_duplicate_'+name,packet(data(len(chunks),chunks[-1]),sp=30000,dp=tid))
frame('completed_contexts_still_charge_rule_quota',packet(req('SMALL.LUP'),sp=42009,dp=69,tx=True),ch=2,flags=32)
frame('no_receive_context_after_cache_quota',packet(data(1,b'abc'),sp=30000,dp=42009),flags=8)
signed_setup();frame('tamper_RRQ',packet(req('SMALL.LUP'),sp=42000,dp=69,tx=True),ch=2);frame('valid_crc_but_sha_mismatch',packet(data(1,b'bad'),sp=30000,dp=42000),flags=1024)
signed_setup();frame('short_length_RRQ',packet(req('SMALL.LUP'),sp=42000,dp=69,tx=True),ch=2);frame('signed_length_mismatch',packet(data(1,b'ab'),sp=30000,dp=42000),flags=1024)
# Revocation affects a transfer already in progress, including terminal SHA delay.
signed_setup();frame('floor_RRQ',packet(req('SMALL.LUP'),sp=42000,dp=69,tx=True),ch=2)
write(0x80,8);frame('floor_raised_during_transfer',packet(data(1,b'abc'),sp=30000,dp=42000),flags=64)
signed_setup();frame('identity_RRQ',packet(req('SMALL.LUP'),sp=42000,dp=69,tx=True),ch=2)
cmd(10,0x4d4954);frame('identity_changed_during_transfer',packet(data(1,b'abc'),sp=30000,dp=42000),flags=64)
# Event overflow is observable and cannot stall forwarding.
setup();cmd(7,0)
for j in range(40):
 pp=packet();ix=len(frames);frames.append(pp);cmd(3,0,len(pp),ix)
cmd(4,15000);cmd(12,0x4c,1);cmd(7,1);cmd(4,100);frame('event_overflow_recovery',packet())
# B-leg full-frame comparisons deliberately occupy the engine; queue loss is counted.
setup();big=packet(bytes(1400),sn=222);frame('queue_pressure_reference',big)
for j in range(30):
 ix=len(frames);frames.append(big);cmd(3,1,len(big),ix)
cmd(4,150000);cmd(12,0x48,1);frame('queue_overflow_recovery',packet())
# Lease expiry after an admitted RRQ must revoke later DATA.
setup(signed_loader)
for w in receipt['writes']:write(w['address'],20000 if (w['address']-0x1000)%128==12 else w['value'])
write(*COMMIT);cmd(4,20)
frame('lease_live_initialize',packet(req('TARGET.LUI'),sp=32000,dp=69));frame('lease_live_lur',packet(req('TARGET.LUR',2),sp=32000,dp=69))
frame('lease_live_rrq',packet(req('SMALL.LUP'),sp=42000,dp=69,tx=True),ch=2)
cmd(4,20100);frame('lease_expired_during_transfer',packet(data(1,b'abc'),sp=30000,dp=42000),flags=64)
# A rollback never resurrects an old authorization or lowers a floor.
cmd(4,31000);write(0x80,8);write(*ROLLBACK);cmd(4,20);cmd(5,0x1000,0);cmd(5,0x80,8)
# Grant version floor is also checked in RTL, independent of the host tool.
setup(signed_loader)
for w in receipt['writes']:write(w['address'],w['value'])
write(0x80,8);write(*COMMIT,fail=True)
# UTC/monotonic monitor: acquisition reanchors, step and backwards mono alarm.
setup();cmd(8,1,1,0,0,100,1);cmd(4,100);cmd(5,0x58,0)
cmd(8,1,9,0,0,210,0);cmd(4,40);cmd(5,0x58,1)
cmd(8,1,9,0,0,0,0);cmd(4,40);cmd(5,0x58,2)
cmd(8,0,9,0,0,100,0);cmd(4,3);cmd(5,0x58,3)
cmd(8,1,100,0,0,300,1);cmd(4,80);cmd(5,0x58,3)
# Expiry/replay protection under a short grant lease.
setup(signed_loader)
for w in receipt['writes']:write(w['address'],10 if (w['address']-0x1000)%128==12 else w['value'])
write(*COMMIT);cmd(4,100);frame('expired_grant_init',packet(req('TARGET.LUI'),sp=32000,dp=69));frame('expired_grant_lur',packet(req('TARGET.LUR',2),sp=32000,dp=69));frame('expired_grant_RRQ',packet(req('SMALL.LUP'),sp=42000,dp=69,tx=True),ch=2,flags=64)
assert len(frames)<=256
(TB/'frames.hex').write_text('\n'.join(p[::-1].hex().rjust(3072,'0') for p in frames)+('\n'+'0'*3072)*(256-len(frames))+'\n')
(TB/'commands.hex').write_text('\n'.join(' '.join(f'{v:08x}' for v in row) for row in commands)+'\n')
(TB/'scenarios.json').write_text(json.dumps({'cases':cases,'commands':commands,'frame_lengths':[len(p) for p in frames]},indent=2)+'\n')
random_bytes=bytes((i*29+11)%256 for i in range(4096));lengths=[0,1,3,55,56,63,64,65,511,512,513,1024,2048,4096]
(TB/'sha_bytes.hex').write_text('\n'.join(f'{b:02x}' for b in random_bytes)+'\n');(TB/'sha_lengths.hex').write_text('\n'.join(f'{n:04x}' for n in lengths)+'\n');(TB/'sha_expected.hex').write_text('\n'.join(hashlib.sha256(random_bytes[:n]).hexdigest() for n in lengths)+'\n')
print('generated',len(cases),'packet scenarios',len(commands),'commands; real signed grants and SHA known answers')
