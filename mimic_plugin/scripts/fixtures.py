"""Independent packet construction and literal expected results, never a parser."""
import binascii,copy,json,struct,sys
from pathlib import Path
R=Path(__file__).resolve().parents[1];sys.path.insert(0,str(R))
FLOW=dict(peer_ip=0x0a000001,local_ip=0x0a000010,rx_mac=0x030000000010,peer_mac=0x020000000002,source_port=100,destination_port=200)
POLICY=dict(schema=1,epoch=3,rules=[dict(id=3,**FLOW,max_mac=1518,require_udp_checksum=True)])
def cksum(data):
    if len(data)%2:data+=b'\0'
    s=sum((data[i]<<8)+data[i+1] for i in range(0,len(data),2))
    while s>65535:s=(s&65535)+(s>>16)
    return (~s)&65535
def frame(payload=b'mimic-demo',sn=1,network='A',flow=None):
    f=flow or FLOW;ip_src=f['peer_ip'].to_bytes(4,'big');ip_dst=f['local_ip'].to_bytes(4,'big')
    udp=struct.pack('>HHHH',f['source_port'],f['destination_port'],8+len(payload),0)+payload
    uck=cksum(ip_src+ip_dst+b'\0\x11'+len(udp).to_bytes(2,'big')+udp) or 65535
    udp=udp[:6]+uck.to_bytes(2,'big')+udp[8:]
    ip=struct.pack('>BBHHHBBH',0x45,0,20+len(udp),7,0,64,17,0)+ip_src+ip_dst
    ip=ip[:10]+cksum(ip).to_bytes(2,'big')+ip[12:]
    sm=(f['peer_mac']&0xffffffffff9f)|(0x20 if network=='A' else 0x40)
    body=f['rx_mac'].to_bytes(6,'big')+sm.to_bytes(6,'big')+b'\x08\0'+ip+udp
    body=body.ljust(59,b'\0')+bytes([sn])
    return b'\x55'*7+b'\xd5'+body+binascii.crc32(body).to_bytes(4,'little')
def repair(raw,ip=False):
    b=bytearray(raw)
    if ip:
        ihl=(b[22]&15)*4;b[32:34]=b'\0\0';b[32:34]=cksum(bytes(b[22:22+ihl])).to_bytes(2,'big')
    b[-4:]=binascii.crc32(b[8:-4]).to_bytes(4,'little');return bytes(b)
def change(raw,offset,values,ip=False):
    b=bytearray(raw);b[offset:offset+len(values)]=values;return repair(b,ip)
def expected(raw,reason='OK',payload=b'mimic-demo',sn=1,network='A',rule=3):
    fields=[0]*9
    if reason=='OK':fields=[FLOW['rx_mac'],(FLOW['peer_mac']&0xffffffffff9f)|(0x20 if network=='A' else 0x40),FLOW['peer_ip'],FLOW['local_ip'],7,sn,FLOW['source_port'],FLOW['destination_port'],8+len(payload)]
    return dict(verdict='allow' if reason=='OK' else 'deny',reason=reason,rule_id=rule if reason=='OK' else -1,wire_length=len(raw),fields=fields,payload_hex=payload.hex() if reason=='OK' else '')
def vectors():
    a=frame();b=frame(network='B',sn=255);maximum=frame(b'x'*1471,sn=0)
    rows=[('normal_A',a,expected(a)),('normal_B',b,expected(b,sn=255,network='B')),('empty_payload',frame(b''),expected(frame(b''),payload=b'')),('max_frame',maximum,expected(maximum,payload=b'x'*1471,sn=0))]
    def add(name,raw,reason):rows.append((name,raw,expected(raw,reason)))
    add('min_short',a[:71],'WIRE_LENGTH');add('max_exceeded',frame(b'x'*1472),'WIRE_LENGTH');add('empty',b'','WIRE_LENGTH')
    add('preamble',change(a,0,b'\x54'),'PREAMBLE');bad=bytearray(a);bad[50]^=1;add('fcs',bytes(bad),'FCS')
    add('ethertype',change(a,20,b'\x86\xdd'),'ETHERTYPE');add('version',change(a,22,b'\x65'),'IP_VERSION')
    add('ihl_short',change(a,22,b'\x44'),'IP_BOUNDS');add('ip_total_large',change(a,24,b'\xff\xff',True),'IP_BOUNDS')
    options=bytearray(a[:-4]);options[42:42]=b'\0'*4;options[22]=0x46;options[24:26]=(int.from_bytes(a[24:26],'big')+4).to_bytes(2,'big');options.extend(b'\0'*4)
    add('options',repair(options,True),'IP_OPTIONS')
    add('ip_checksum',change(a,30,b'\x3f'),'IP_CHECKSUM');add('fragment',change(a,28,b'\x20\x00',True),'IP_FRAGMENT')
    add('protocol',change(a,31,b'\x06',True),'IP_PROTOCOL');add('ttl_zero',change(a,30,b'\x00',True),'IP_TTL')
    add('udp_length',change(a,46,b'\x00\x09'),'UDP_LENGTH');add('udp_checksum',change(a,50,b'X'),'UDP_CHECKSUM')
    add('acl',frame(flow=dict(FLOW,peer_ip=FLOW['peer_ip']^256)),'ACL')
    add('udp_zero',change(a,48,b'\0\0'),'UDP_CHECKSUM_REQUIRED')
    return rows
def generate(root=R):
    root=Path(root);rows=vectors();selftests=[]
    for name,raw,want in rows:selftests.append(dict(id=name,raw_hex=raw.hex(),expected=want))
    (root/'trusted_selftests.json').write_text(json.dumps(dict(schema=1,policy=POLICY,vectors=selftests),indent=2)+'\n',encoding='utf8',newline='\n')
    for name,selection in [('normal',['normal_A','normal_B','empty_payload']),('udp_length',['udp_length','normal_A']),('boundary_suite',[r[0] for r in rows])]:
        d=root/'cases'/name;d.mkdir(parents=True,exist_ok=False);(d/'policy.json').write_text(json.dumps(POLICY,indent=2)+'\n',encoding='utf8',newline='\n')
        frames=[]
        for i,(ident,raw,want) in enumerate([r for key in selection for r in rows if r[0]==key]):
            path=ident+'.bin';(d/path).write_bytes(raw);frames.append(dict(id=ident,path=path,channel=1 if ident=='normal_B' else 0,capture_ticks=i*10000))
        (d/'case.json').write_text(json.dumps(dict(schema=1,case_id=name,source='synthetic_lab',policy='policy.json',frames=frames),indent=2)+'\n',encoding='utf8',newline='\n')
    print('fixtures_generated',len(rows))
if __name__=='__main__':generate()
