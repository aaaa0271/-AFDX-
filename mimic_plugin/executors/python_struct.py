"""Executor A: struct-oriented decoder, stdlib CRC and folded word sums.

This file deliberately imports no parser or policy evaluator from the host or
other executors. Rules and inputs are received over the bounded binary ABI.
"""
import binascii,json,struct,sys

REASONS=('OK','WIRE_LENGTH','PREAMBLE','FCS','ETHERTYPE','IP_VERSION','IP_BOUNDS','IP_OPTIONS','IP_CHECKSUM','IP_FRAGMENT','IP_PROTOCOL','IP_TTL','UDP_LENGTH','UDP_CHECKSUM','ACL','UDP_CHECKSUM_REQUIRED')
class Denied(Exception):pass
def word_sum(raw):
    if len(raw)%2:raw+=b'\0'
    n=sum(struct.unpack('>'+str(len(raw)//2)+'H',raw))
    while n>65535:n=(n&65535)+(n>>16)
    return n

def main():
    data=sys.stdin.buffer.read(4097)
    if len(data)<96 or len(data)>4096:raise ValueError('request bounds')
    magic,rid,epoch,gen,tick,ch,count,n,ph,ih=struct.unpack('>4sQIIQBBH32s32s',data[:96])
    if magic!=b'MDH1' or ch>1 or not 1<=count<=8 or n>2048 or len(data)!=96+33*count+n:raise ValueError('request ABI')
    rules=[struct.unpack('>HIIQQHHHB',data[96+33*i:129+33*i]) for i in range(count)]
    raw=data[96+33*count:]
    out=dict(request_id=rid,epoch=epoch,generation=gen,policy_hash=ph.hex(),input_hash=ih.hex(),verdict='deny',reason='',rule_id=-1,wire_length=n,fields=[0]*9,payload_hex='')
    try:
        def check(ok,reason):
            if not ok:raise Denied(reason)
        check(72<=n<=1526,1);check(raw[:8]==b'\x55'*7+b'\xd5',2)
        check(binascii.crc32(raw[8:-4])==int.from_bytes(raw[-4:],'little'),3)
        check(raw[20:22]==b'\x08\x00',4);check(raw[22]>>4==4,5)
        ihl=(raw[22]&15)*4;total=struct.unpack_from('>H',raw,24)[0]
        check(ihl>=20 and total>=ihl and 22+total<=n-5,6);check(ihl==20,7)
        check(word_sum(raw[22:42])==65535,8)
        frag=struct.unpack_from('>H',raw,28)[0]
        if frag&0xbfff:
            check(any(r[8]&2 for r in rules),9)
            check(not frag&0x8000 and not(frag&0x4000 and frag&0x3fff) and total>20 and (not frag&0x2000 or (total-20)%8==0),9)
            check(raw[31]==17,10);check(raw[30]>0,11)
            first=frag&8191==0
            check(not first or total>=28,12)
            sp,dp=struct.unpack_from('>HH',raw,42) if first else (0,0)
            dm=int.from_bytes(raw[8:14],'big');sm=int.from_bytes(raw[14:20],'big');sip,dip=struct.unpack_from('>II',raw,34)
            hit=next((r for r in rules if r[8]&2 and r[1]==sip and r[2]==dip and r[3]==dm and (r[4]^sm)&0xffffffffff9f==0 and (not first or (r[5],r[6])==(sp,dp)) and n-8<=r[7]),None)
            check(hit is not None,14)
            check(not first or not hit[8]&1 or struct.unpack_from('>H',raw,48)[0]!=0,15)
            payload=raw[22:22+total]
            out.update(verdict='allow',reason='OK',rule_id=hit[0],fields=[dm,sm,sip,dip,int.from_bytes(raw[26:28],'big'),raw[-5],sp,dp,len(payload)+8],payload_hex=payload.hex())
            print(json.dumps(out,separators=(',',':')));return
        check(raw[31]==17,10);check(raw[30]>0,11);check(total>=28,12)
        sp,dp,udp_len,udp_ck=struct.unpack_from('>HHHH',raw,42)
        check(udp_len>=8 and udp_len==total-20,12)
        pseudo=raw[34:42]+b'\x00\x11'+udp_len.to_bytes(2,'big')
        check(udp_ck==0 or word_sum(pseudo+raw[42:42+udp_len])==65535,13)
        dm=int.from_bytes(raw[8:14],'big');sm=int.from_bytes(raw[14:20],'big')
        sip,dip=struct.unpack_from('>II',raw,34);mask=0xffffffffff9f
        hit=next((r for r in rules if r[1]==sip and r[2]==dip and r[3]==dm and r[4]&mask==sm&mask and r[5]==sp and r[6]==dp and n-8<=r[7]),None)
        check(hit is not None,14);check(udp_ck!=0 or not hit[8]&1,15)
        out.update(verdict='allow',reason='OK',rule_id=hit[0],fields=[dm,sm,sip,dip,int.from_bytes(raw[26:28],'big'),raw[-5],sp,dp,udp_len],payload_hex=raw[50:22+total].hex())
    except Denied as e:out['reason']=REASONS[e.args[0]]
    print(json.dumps(out,separators=(',',':')))

if __name__=='__main__':
    try:main()
    except Exception:sys.exit(2)
