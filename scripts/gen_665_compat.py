"""Byte fixtures for the implemented subset; not an edition oracle."""
from pathlib import Path
import binascii,json,struct
ROOT=Path(__file__).resolve().parents[1]
def u16(n):return struct.pack('>H',n)
def u32(n):return struct.pack('>I',n)
def string(s):
    b=s.encode();return u16(len(b))+b+(b'\0' if len(b)%2 else b'')
def c32(data,state=0xffffffff):
    for b in data:
        state^=b<<24
        for _ in range(8):state=((state<<1)^(0x04c11db7 if state&0x80000000 else 0))&0xffffffff
    return state
def finish(b,files=()):
    b=bytearray(b);b[-6:-4]=u16(binascii.crc_hqx(b[:-6],65535));c=c32(b[:-4])
    for f in files:c=c32(f,c)
    b[-4:]=u32(c^0xffffffff);return bytes(b)
def header(version=0x8004,hardware=('SIM',),names=('A.LUP','B.LUP')):
    fixed=40 if version==0x8004 else 28
    part=string('PN-1');hw=u16(len(hardware))+b''.join(map(string,hardware))
    files=[bytes((3+7*i)&255 for i in range(700)),bytes((225-3*i)&255 for i in range(1024))]
    entries=[]
    for i,(name,data) in enumerate(zip(names,files)):
        entry=string(name)+string('PN-1')+u32(len(data)//2)+u16(binascii.crc_hqx(data,65535))
        if version==0x8004:entry+=u32(0)+u32(len(data))+u16(0)
        entries.append(u16((len(entry)+2)//2 if i+1<len(names) else 0)+entry)
    b=bytearray(fixed)+part+hw+u16(len(entries))+b''.join(entries)+bytearray(6)
    b[0:8]=u32(len(b)//2)+u16(version)+u16(0)
    b[8:20]=u32(fixed//2)+u32((fixed+len(part))//2)+u32((fixed+len(part)+len(hw))//2)
    return finish(b,files)
def main():
    base=header()
    original=bytes(int(x,16) for x in (ROOT/'tb/APP.LUH.hex').read_text().split())
    assert base==original,'fixture differs from original known answer'
    rows=[('8004_original',base,0),('8003_supplement2',header(0x8003),0),
          ('8004_multi_hardware',header(hardware=('OTHER','SIM')),0),
          ('hardware_mismatch',header(hardware=('OTHER',)),8),
          ('duplicate_name',header(names=('A.LUP','A.LUP')),12)]
    for name,offset,data,code in [('unsupported_8002_legacy_prefix',4,u16(0x8002),2),
        ('unknown_format',4,u16(0x8005),2),('part_pointer_overlap',8,u32(1),4),
        ('part_pointer_overflow',8,u32(0x80000000),4),('hardware_pointer_overflow',12,u32(0xffffffff),4),
        ('support_pointer_inside_prefix',20,u32(1),4),('udd_pointer_inside_prefix',24,u32(1),4),('reserved_nonzero',6,u16(1),2)]:
        b=bytearray(base);b[offset:offset+len(data)]=data;rows.append((name,finish(b),code))
    b=bytearray(base);b[-6]^=1;rows.append(('bad_header_crc',bytes(b),3))
    packed=[];vh=[];metadata=[]
    for i,(name,data,code) in enumerate(rows):
        offset=len(packed);packed.extend(data)
        vh.append(f'run_case({i}, {offset}, {len(data)}, {code});')
        metadata.append(dict(id=i,name=name,length=len(data),expected_error=code))
    (ROOT/'tb/compat665.hex').write_text(''.join(f'{b:02x}\n' for b in packed))
    (ROOT/'tb/compat665.vh').write_text('\n'.join(vh)+'\n')
    (ROOT/'tb/compat665.json').write_text(json.dumps(dict(scope='SDK-based 8003/8004 bounded LUH; 8002 rejected by default',bytes=len(packed),cases=metadata),indent=2)+'\n')
    print('665_COMPAT_FIXTURES',len(rows),len(packed))
if __name__=='__main__':main()
