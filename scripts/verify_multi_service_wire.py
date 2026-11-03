"""Independent audit of actual integrated A/B service frames (no RTL imports)."""
from pathlib import Path
from collections import defaultdict
import binascii,json,sys
from verify_service_wire import checksum,status_file

def audit(path):
    frames=defaultdict(list);domains=defaultdict(list);rrqs=defaultdict(set);final=defaultdict(int);seqs={};starts={}
    for line in path.read_text().splitlines():
        net,time,hexstr=line.split();time=int(time);raw=bytes.fromhex(hexstr)
        assert raw[:8]==bytes.fromhex('55555555555555d5'),'preamble'
        body=raw[8:-4]
        assert binascii.crc32(body)==int.from_bytes(raw[-4:],'little'),'FCS'
        assert body[12:14]==b'\x08\x00' and body[14]==0x45,'IPv4'
        assert checksum(body[14:34])==65535,'IP checksum'
        total=int.from_bytes(body[16:18],'big');udplen=int.from_bytes(body[38:40],'big')
        assert total==20+udplen and 8<=udplen<=524,'IP/UDP length'
        dst=int.from_bytes(body[:6],'big');src=int.from_bytes(body[6:12],'big')
        assert dst in (0x030000000020,0x030000000021,0x030000000022,0x030000000023),'VL route'
        route=dst-0x030000000020;lane=route//2;clock=route%2
        assert body[30:34]==(0x0a000101+lane if clock else 0x0a000001+lane).to_bytes(4,'big'),'endpoint IP'
        sp=int.from_bytes(body[34:36],'big');dp=int.from_bytes(body[36:38],'big')
        assert src&0xe0==(0x20 if net=='A' else 0x40),'source Interface_ID'
        assert len(body)==max(60,43+udplen-8),'padding/sequence size'
        seq=body[-1];key=(net,route)
        expected=0 if key not in seqs else (1 if seqs[key]==255 else seqs[key]+1)
        assert seq==expected,(key,seq,expected)
        seqs[key]=seq
        # Shared egress BAG applies to all service frames, regardless of lane.
        start=time-len(raw)*80000
        if net in starts:assert start-starts[net]>=1_000_000_000,'shared 1ms BAG (ps timestamps)'
        starts[net]=start
        payload=body[42:42+udplen-8]
        if clock:
            assert sp==40001 and dp==123 and len(payload)==48 and payload[0]==0x23,'NTP client'
        else:
            op=int.from_bytes(payload[:2],'big')
            assert sp in (41000,40002) or 42000<=sp<43000,'TFTP local TID'
            if op==1:rrqs[(net,lane)].add(payload[2:].split(b'\0')[0].decode())
            if sp==40002 and op==3 and int.from_bytes(payload[2:4],'big')==1:
                status=status_file(payload[4:]);final[(net,lane)]+=status['status']==3
        normalized=bytearray(body);normalized[11]&=31
        frames[net].append(bytes(normalized));domains[key].append(seq)
    assert frames['A']==frames['B'],'redundant stream content/order'
    assert len(domains)==8,'all four VLs on each redundant network'
    for net in ('A','B'):
        for lane in range(2):
            assert rrqs[(net,lane)]=={'APP.LUH','A.LUP','B.LUP'},'each loader fetched every package file'
            assert final[(net,lane)]==1,'each loader has exactly one successful final status'
            assert len(domains[(net,lane*2+1)])==2,'initial clock request plus recovery poll'
    return dict(status='PASS',a_frames=len(frames['A']),b_frames=len(frames['B']),
                independent_sequence_domains_per_network=4,loaders=2,clock_servers=2,
                audited=['FCS','IP checksum','UDP lengths','MAC/IP/UDP routes','A/B equality','per-VL sequence','shared BAG','package RRQs','final LUS','NTP requests'])
if __name__=='__main__':
    p=Path(sys.argv[1]);r=audit(p);p.with_suffix('.audit.json').write_text(json.dumps(r,indent=2)+'\n')
    print('MULTI_SERVICE_WIRE_AUDIT_PASS',json.dumps(r))