"""Independent bounded A4 download peer/decoder, usable by UDP or MAC adapters.

No RTL memory access is used. Receive complete UDP payloads from the configured
target only, bind the first response TID in the adapter, and return its ACK.
"""
import hashlib
import json
import struct
from pathlib import Path


def require(condition, message):
    if not condition:
        raise ValueError(message)


def string(value):
    raw=value.encode('ascii')
    require(0<len(raw)<=31 and b'\0' not in raw, 'A4 filename length')
    return bytes([len(raw)+1])+raw+b'\0'


def get_string(buf,pos):
    require(pos<len(buf),'missing string length')
    length=buf[pos];pos+=1
    require(pos+length<=len(buf),'truncated string')
    if not length:return '',pos
    value=buf[pos:pos+length]
    require(value[-1:]==b'\0' and b'\0' not in value[:-1],'invalid string terminator')
    return value[:-1].decode('ascii'),pos+length


def envelope(body):
    return struct.pack('>I',len(body)+6)+b'A4'+body


def check_header(buf):
    require(len(buf)>=8 and int.from_bytes(buf[:4],'big')==len(buf) and buf[4:6]==b'A4','invalid A4 header')


def selection_file(names,media=False):
    names=list(names)
    require(1<=len(names)<=4 and len(names)==len(set(names)),'selection count or duplicates')
    return envelope(struct.pack('>H',len(names))+b''.join(string(n) for n in names)+(b'\0' if media else b''))


def parse_directory(buf):
    check_header(buf);count=int.from_bytes(buf[6:8],'big');pos=8;rows=[]
    require(1<=count<=4,'directory count')
    for _ in range(count):
        name,pos=get_string(buf,pos);description,pos=get_string(buf,pos)
        require(name and name not in [r['name'] for r in rows],'directory duplicate')
        rows.append(dict(name=name,description=description))
    require(pos==len(buf),'directory trailing bytes')
    return rows


def parse_status(buf):
    check_header(buf);code=int.from_bytes(buf[6:8],'big');description,pos=get_string(buf,8)
    require(pos+11<=len(buf),'status fixed fields')
    counter,exception,estimate=struct.unpack_from('>HHh',buf,pos);pos+=6
    ratio=buf[pos:pos+3];pos+=3
    require(ratio.isdigit() and int(ratio)<=100,'status ratio')
    count=int.from_bytes(buf[pos:pos+2],'big');pos+=2;rows=[]
    require(count<=4,'status file count')
    for _ in range(count):
        name,pos=get_string(buf,pos);require(pos+2<=len(buf),'status file code')
        file_code=int.from_bytes(buf[pos:pos+2],'big');pos+=2
        desc,pos=get_string(buf,pos);rows.append(dict(name=name,code=file_code,description=desc))
    require(pos==len(buf),'status trailing bytes')
    return dict(code=code,description=description,counter=counter,exception_timer=exception,estimated_time=estimate,ratio=int(ratio),files=rows)


class DownloadReceiver:
    """One octet-mode target WRQ at a time, duplicate-safe, bounded to 4096B.

    The enclosing adapter owns source-IP/TID validation and timeouts. Completed
    protocol files are decoded before ACK, so corrupt LNS never reports success.
    """
    def __init__(self,max_file_bytes=4096):
        self.limit=max_file_bytes;self.name=None;self.block=0;self.data=bytearray()
        self.last=None;self.finished=False;self.files={};self.events=[]

    def receive(self,payload):
        require(len(payload)>=2,'short TFTP packet')
        opcode=int.from_bytes(payload[:2],'big')
        if opcode==2:
            parts=payload[2:].split(b'\0')
            require(len(parts)==3 and parts[1]==b'octet' and parts[2]==b'','WRQ shape/mode/options')
            name=parts[0].decode('ascii')
            require(1<=len(name)<=31 and all(c.isascii() and (c.isalnum() or c in '._-') for c in name) and name not in ('.','..'),'unsafe filename')
            if self.name==name and self.block==0 and not self.finished:
                return b'\0\4\0\0',None
            require(self.name is None or self.finished,'WRQ during active transfer')
            self.name=name;self.block=0;self.data=bytearray();self.last=None;self.finished=False
            return b'\0\4\0\0',None
        require(opcode==3 and 4<=len(payload)<=516 and self.name is not None,'unexpected DATA')
        block=int.from_bytes(payload[2:4],'big');data=payload[4:]
        if block==self.block:
            require(self.last==data,'changed duplicate DATA')
            return b'\0\4'+payload[2:4],None
        require(not self.finished and block==self.block+1,'DATA order')
        require(len(self.data)+len(data)<=self.limit,'file too large')
        new_data=bytes(self.data)+data;event=None
        if len(data)<512:
            event=dict(name=self.name,data=new_data)
            if self.name=='TARGET.LNS':event['status']=parse_status(new_data)
            elif self.name=='TARGET.LNL':event['directory']=parse_directory(new_data)
            self.finished=True
            self.files[self.name]=new_data;self.events.append(event)
        self.data.extend(data);self.block=block;self.last=data
        return b'\0\4'+payload[2:4],event

    def save(self,directory):
        directory=Path(directory);directory.mkdir(parents=True,exist_ok=False)
        for name,data in self.files.items():(directory/name).write_bytes(data)
        report=dict(files={n:dict(length=len(b),sha256=hashlib.sha256(b).hexdigest()) for n,b in self.files.items()},
                    statuses=[e['status'] for e in self.events if 'status' in e])
        (directory/'download_audit.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
        return report
