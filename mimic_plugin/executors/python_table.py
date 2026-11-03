"""Executor D: declarative field layout, memoryview and bitwise CRC.

Independent spare implementation; no struct, binascii, shared parser or host
policy evaluator. Shared Python interpreter remains an explicit common risk.
"""
import json,sys

NAMES=['OK','WIRE_LENGTH','PREAMBLE','FCS','ETHERTYPE','IP_VERSION','IP_BOUNDS','IP_OPTIONS','IP_CHECKSUM','IP_FRAGMENT','IP_PROTOCOL','IP_TTL','UDP_LENGTH','UDP_CHECKSUM','ACL','UDP_CHECKSUM_REQUIRED']
def number(view,start,size):return int.from_bytes(view[start:start+size],'big')
def crc(view):
    c=0xffffffff
    for byte in view:
        c^=byte
        for _ in range(8):c=(c>>1)^(0xedb88320 if c&1 else 0)
    return c^0xffffffff
def internet_sum(parts):
    acc=0;pending=None
    for part in parts:
        for byte in part:
            if pending is None:pending=byte
            else:acc+=(pending<<8)|byte;pending=None
    if pending is not None:acc+=pending<<8
    while acc>>16:acc=(acc&65535)+(acc>>16)
    return acc

def examine(raw,rules):
    n=len(raw)
    if n<72 or n>1526:return 1,None
    if tuple(raw[:8])!=(85,85,85,85,85,85,85,213):return 2,None
    if crc(raw[8:-4])!=int.from_bytes(raw[-4:],'little'):return 3,None
    if number(raw,20,2)!=2048:return 4,None
    if raw[22]//16!=4:return 5,None
    width=(raw[22]%16)*4;size=number(raw,24,2)
    if width<20 or size<width or size>n-27:return 6,None
    if width!=20:return 7,None
    if internet_sum([raw[22:42]])!=65535:return 8,None
    fragmentation=number(raw,28,2)
    if fragmentation&49151:
        if not any(rule[8]&2 for rule in rules):return 9,None
        if fragmentation&32768 or (fragmentation&16384 and fragmentation&16383) or size<=20 or (fragmentation&8192 and (size-20)%8):return 9,None
        if raw[31]!=17:return 10,None
        if raw[30]==0:return 11,None
        first=fragmentation%8192==0
        if first and size<28:return 12,None
        dm,sm,sip,dip=(number(raw,o,w) for o,w in ((8,6),(14,6),(34,4),(38,4)))
        sp=number(raw,42,2) if first else 0;dp=number(raw,44,2) if first else 0
        for rule in rules:
            if rule[8]&2 and (sip,dip,dm,sm&281474976710559)==(rule[1],rule[2],rule[3],rule[4]&281474976710559) and (not first or (sp,dp)==(rule[5],rule[6])) and n-8<=rule[7]:
                if first and rule[8]&1 and number(raw,48,2)==0:return 15,None
                payload=bytes(raw[22:22+size])
                return 0,(rule[0],[dm,sm,sip,dip,number(raw,26,2),raw[-5],sp,dp,len(payload)+8],payload.hex())
        return 14,None
    if raw[31]!=17:return 10,None
    if not raw[30]:return 11,None
    if size<28:return 12,None
    length=number(raw,46,2);check=number(raw,48,2)
    if length<8 or length!=size-20:return 12,None
    if check and internet_sum([raw[34:42],bytes((0,17)),length.to_bytes(2,'big'),raw[42:42+length]])!=65535:return 13,None
    fields={name:number(raw,offset,width) for name,offset,width in [('dm',8,6),('sm',14,6),('sip',34,4),('dip',38,4),('ip_id',26,2),('sp',42,2),('dp',44,2)]}
    match=None
    for rule in rules:
        values=(fields['sip'],fields['dip'],fields['dm'],fields['sm']&281474976710559,fields['sp'],fields['dp'])
        expected=(rule[1],rule[2],rule[3],rule[4]&281474976710559,rule[5],rule[6])
        if values==expected and n-8<=rule[7]:match=rule;break
    if match is None:return 14,None
    if check==0 and match[8]&1:return 15,None
    return 0,(match[0],[fields['dm'],fields['sm'],fields['sip'],fields['dip'],fields['ip_id'],raw[-5],fields['sp'],fields['dp'],length],bytes(raw[50:22+size]).hex())

def main():
    request=memoryview(sys.stdin.buffer.read(4097))
    if len(request)<96 or len(request)>4096 or bytes(request[:4])!=b'MDH1':raise ValueError('ABI')
    count=request[29];length=number(request,30,2)
    if request[28]>1 or count<1 or count>8 or length>2048 or len(request)!=96+33*count+length:raise ValueError('ABI lengths')
    layout=[(0,2),(2,4),(6,4),(10,8),(18,8),(26,2),(28,2),(30,2),(32,1)]
    rules=[[number(request,96+i*33+start,width) for start,width in layout] for i in range(count)]
    reason,result=examine(request[96+33*count:],rules)
    out={'request_id':number(request,4,8),'epoch':number(request,12,4),'generation':number(request,16,4),'policy_hash':bytes(request[32:64]).hex(),'input_hash':bytes(request[64:96]).hex(),'verdict':'allow' if reason==0 else 'deny','reason':NAMES[reason],'rule_id':result[0] if result else -1,'wire_length':length,'fields':result[1] if result else [0]*9,'payload_hex':result[2] if result else ''}
    print(json.dumps(out,separators=(',',':')))

if __name__=='__main__':
    try:main()
    except Exception:sys.exit(2)
