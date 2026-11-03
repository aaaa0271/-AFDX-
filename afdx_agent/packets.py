"""Independent full-frame parsing and bounded laboratory packet mutation."""
import binascii,struct

def checksum(raw):
    raw=raw+b'\0'*(len(raw)%2);n=sum(int.from_bytes(raw[i:i+2],'big') for i in range(0,len(raw),2))
    while n>>16:n=(n&65535)+(n>>16)
    return ~n&65535

def parse(raw):
    d={'wire_length':len(raw),'issues':[]}
    if not 72<=len(raw)<=1526 or raw[:8]!=b'\x55'*7+b'\xd5':d['issues'].append('preamble_or_length');return d
    d['fcs_valid']=binascii.crc32(raw[8:-4]).to_bytes(4,'little')==raw[-4:]
    if not d['fcs_valid']:d['issues'].append('fcs')
    d.update(destination_mac=raw[8:14].hex(),source_mac=raw[14:20].hex(),sequence=raw[-5])
    if raw[20:22]!=b'\x08\0' or raw[22]>>4!=4:d['issues'].append('not_ipv4');return d
    ihl=(raw[22]&15)*4;total=int.from_bytes(raw[24:26],'big')
    if ihl<20 or 22+total>len(raw)-5 or total<ihl:d['issues'].append('ip_bounds');return d
    d['ip_checksum_valid']=checksum(raw[22:22+ihl])==0
    if not d['ip_checksum_valid']:d['issues'].append('ipv4_checksum')
    frag=int.from_bytes(raw[28:30],'big');offset=(frag&8191)*8
    d.update(source_ip=int.from_bytes(raw[34:38],'big'),destination_ip=int.from_bytes(raw[38:42],'big'),
             ip_id=int.from_bytes(raw[26:28],'big'),fragment_offset=offset,more_fragments=bool(frag&8192),protocol=raw[31])
    if raw[31]!=17 or offset or total<ihl+8:return d
    start=22+ihl;sp,dp,n,ck=struct.unpack('!HHHH',raw[start:start+8]);d.update(source_port=sp,destination_port=dp,udp_length=n)
    if not frag&8192:
        if n!=total-ihl or n<8:d['issues'].append('udp_length');return d
        udp=raw[start:start+n];d['udp_checksum_valid']=ck==0 or checksum(raw[34:42]+b'\0\x11'+n.to_bytes(2,'big')+udp)==0
        if not d['udp_checksum_valid']:d['issues'].append('udp_checksum')
        payload=udp[8:]
        if (sp==123 or dp==123) and len(payload)==48:
            d['ntp']=dict(mode=payload[0]&7,version=(payload[0]>>3)&7,stratum=payload[1],
                          origin=int.from_bytes(payload[24:32],'big'),receive=int.from_bytes(payload[32:40],'big'),transmit=int.from_bytes(payload[40:48],'big'))
        elif sp in (69,41000,40002,44000,44001) or dp in (69,41000,40002,44000,44001) or 42000<=sp<43000 or 42000<=dp<43000:
            if len(payload)>=2:
                op=int.from_bytes(payload[:2],'big');d['tftp']={'opcode':op}
                if op in (1,2):d['tftp']['filename']=payload[2:].split(b'\0')[0].decode('ascii',errors='replace')[:32]
                if op in (3,4) and len(payload)>=4:d['tftp']['block']=int.from_bytes(payload[2:4],'big');d['tftp']['data_bytes']=max(0,len(payload)-4)
    return d

def logical_key(raw):
    d=parse(raw)
    if 'source_ip' not in d:return None
    return (raw[8:19],raw[19]&0x9f,d['source_ip'],d['destination_ip'],d['ip_id'],d['fragment_offset'],d['more_fragments'],d['protocol'],d['sequence'])

def compare(first,second):
    a,b=parse(first),parse(second);same=logical_key(first) is not None and logical_key(first)==logical_key(second)
    differences=[]
    if same:
        for i in range(8,max(len(first),len(second))-4):
            x=first[i] if i<len(first)-4 else None;y=second[i] if i<len(second)-4 else None
            if i==19 and x is not None and y is not None:x,y=x&0x9f,y&0x9f
            if x!=y:differences.append(dict(wire_offset=i,first=x,second=y))
    valid=not a['issues'] and not b['issues']
    return dict(same_logical_message=same,both_protocol_checks_valid=valid,
                normalized_content_equal=(not differences) if same else None,differences=differences,
                first=a,second=b,trusted_side=None,
                finding='valid_replica_content_conflict' if same and valid and differences else 'no_matching_valid_conflict')

def packet(flow,payload=b'agent-test',sp=None,dp=None,sn=1,network='A',tx=False,ip_id=7,fragment=0,ip_payload=None):
    source,destination=flow['peer_ip'],flow['local_ip'];dm=flow['rx_mac'];sm=flow['peer_mac']
    sp=flow['source_port'] if sp is None else sp;dp=flow['destination_port'] if dp is None else dp
    if tx:source,destination=destination,source;dm=flow['tx_mac'];sm=0x020000000010
    sm=(sm&0xffffffffff9f)|(0x20 if network=='A' else 0x40)
    udp=struct.pack('!HHHH',sp,dp,len(payload)+8,0)+payload
    ck=checksum(source.to_bytes(4,'big')+destination.to_bytes(4,'big')+b'\0\x11'+len(udp).to_bytes(2,'big')+udp) or 65535
    udp=udp[:6]+ck.to_bytes(2,'big')+udp[8:];body=udp if ip_payload is None else ip_payload
    ip=struct.pack('!BBHHHBBHII',0x45,0,len(body)+20,ip_id,fragment,64,17,0,source,destination)
    ip=ip[:10]+checksum(ip).to_bytes(2,'big')+ip[12:]
    frame=dm.to_bytes(6,'big')+sm.to_bytes(6,'big')+b'\x08\0'+ip+body
    frame=frame.ljust(59,b'\0')+bytes([sn])
    return b'\x55'*7+b'\xd5'+frame+binascii.crc32(frame).to_bytes(4,'little')

def mutate_payload(raw):
    d=parse(raw)
    if d['issues'] or d.get('fragment_offset') or d.get('more_fragments') or d.get('udp_length',0)<=8:raise ValueError('need complete valid UDP data')
    b=bytearray(raw);start=22+(raw[22]&15)*4;b[start+8]^=1;b[start+6:start+8]=b'\0\0'
    n=d['udp_length'];ck=checksum(b[34:42]+b'\0\x11'+n.to_bytes(2,'big')+bytes(b[start:start+n])) or 65535
    b[start+6:start+8]=ck.to_bytes(2,'big');b[-4:]=binascii.crc32(b[8:-4]).to_bytes(4,'little')
    return bytes(b)
