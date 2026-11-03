"""Run fixed, hash-checked security RTL in an isolated experiment directory."""
import hashlib,json,os,re,shutil,struct,subprocess
from pathlib import Path
from security_lab.policy import Rule,COMMIT
from afdx_ai.bridge import decode_event
from .case import sha
from .packets import packet,mutate_payload,compare,parse

PROFILES={'ab_integrity','loader_phase','time_response','fragment_budget','rate_baseline','rate_candidate'}

class Vectors:
    def __init__(self,flow,kind=0,**overrides):
        self.flow=flow;self.frames=[];self.commands=[];self.cases=[]
        self.cmd(0)
        rule=Rule(**flow,kind=kind,timeout=30000,**overrides)
        for a,v in rule.writes(0):self.cmd(1,a,v)
        self.cmd(1,0,2);self.cmd(1,*COMMIT);self.cmd(4,20);self.cmd(5,0,2)
    def cmd(self,op,*args,case=0):self.commands.append([op,*args,*([0]*(6-len(args))),case])
    def add(self,name,raw,channel=0,flags=0,gap=0):
        index=len(self.frames);self.frames.append(raw);ident=len(self.cases)+1
        self.cases.append(dict(id=ident,name=name,index=index,channel=channel,flags=flags,allow=flags==0,length=len(raw)))
        self.cmd(2,channel,len(raw),index,flags,int(flags==0),2,case=ident)
        if gap:self.cmd(4,gap)
    def save(self,directory):
        lines=[b[::-1].hex().rjust(3072,'0') for b in self.frames]+['0'*3072]*(256-len(self.frames))
        (directory/'frames.hex').write_text('\n'.join(lines)+'\n')
        (directory/'commands.hex').write_text('\n'.join(' '.join(f'{v:08x}' for v in row) for row in self.commands)+'\n')
        (directory/'vectors.json').write_text(json.dumps(self.cases,indent=2)+'\n')

def build_profile(profile,flow,max_frames=20,window=125000):
    if profile not in PROFILES:raise ValueError('unknown fixed RTL experiment')
    if profile=='ab_integrity':
        v=Vectors(flow);a=packet(flow,sn=41);b=packet(flow,sn=41,network='B')
        v.add('valid_A',a);v.add('interface_only_B',b,1)
        a=packet(flow,sn=42);b=mutate_payload(packet(flow,sn=42,network='B'))
        v.add('conflict_reference_A',a);v.add('valid_crc_content_changed_B',b,1,4)
        broken=bytearray(packet(flow,sn=43));broken[52]^=1;v.add('bad_fcs',bytes(broken),flags=1)
        bad=dict(flow,peer_ip=flow['peer_ip']^0x100);v.add('unknown_peer',packet(bad,sn=44),flags=2)
        v.add('normal_recovery',packet(flow,sn=45))
    elif profile=='loader_phase':
        v=Vectors(flow,kind=2)
        req=lambda name,op=1:struct.pack('!H',op)+name.encode()+b'\0octet\0'
        data=lambda block,payload:struct.pack('!HH',3,block)+payload
        v.add('LUR_before_LUI',packet(flow,req('TARGET.LUR',2),sp=32000,dp=69,sn=1),flags=8)
        v.add('LUI',packet(flow,req('TARGET.LUI'),sp=32000,dp=69,sn=2))
        v.add('LUR',packet(flow,req('TARGET.LUR',2),sp=32000,dp=69,sn=3))
        v.add('local_RRQ',packet(flow,req('A.LUP'),sp=42000,dp=69,tx=True,sn=4),2)
        v.add('wrong_block',packet(flow,data(2,b'abc'),sp=30000,dp=42000,sn=5),flags=128)
        v.add('valid_DATA',packet(flow,data(1,b'abc'),sp=30000,dp=42000,sn=6))
        v.add('valid_retransmit',packet(flow,data(1,b'abc'),sp=30000,dp=42000,sn=7))
        v.add('changed_retransmit',packet(flow,data(1,b'abd'),sp=30000,dp=42000,sn=8),flags=128)
    elif profile=='time_response':
        flow=dict(flow,source_port=123,destination_port=40001)
        v=Vectors(flow,kind=3,strict_initial_time=True)
        t1=0x1234567800000000;poll=bytearray(48);poll[0]=0x23;poll[40:48]=t1.to_bytes(8,'big')
        v.add('NTP_poll',packet(flow,bytes(poll),sp=40001,dp=123,tx=True,sn=1),2)
        response=bytearray(48);response[0]=0x24;response[1]=1;response[24:32]=t1.to_bytes(8,'big');response[32:40]=(t1+100).to_bytes(8,'big');response[40:48]=(t1+200).to_bytes(8,'big')
        bad=bytearray(response);bad[31]^=1
        v.add('wrong_origin',packet(flow,bytes(bad),sp=123,dp=40001,sn=2),flags=256)
        bad=bytearray(response);bad[40:48]=(t1+(4<<32)).to_bytes(8,'big')
        v.add('time_jump',packet(flow,bytes(bad),sp=123,dp=40001,sn=3),flags=256)
        v.add('valid_recovery',packet(flow,bytes(response),sp=123,dp=40001,sn=4))
    elif profile=='fragment_budget':
        v=Vectors(flow,fragments=True,max_contexts=1)
        payload=struct.pack('!HHHH',flow['source_port'],flow['destination_port'],40,0)+bytes(range(16))
        v.add('first_context',packet(flow,ip_id=90,fragment=0x2000,ip_payload=payload,sn=1))
        v.add('second_context_over_budget',packet(flow,ip_id=91,fragment=0x2000,ip_payload=payload,sn=2),flags=32)
        v.add('orphan',packet(flow,ip_id=92,fragment=3,ip_payload=bytes(16),sn=3),flags=512)
        v.add('finish_first',packet(flow,ip_id=90,fragment=3,ip_payload=bytes(16),sn=4))
        v.add('budget_recovered',packet(flow,ip_id=91,fragment=0x2000,ip_payload=payload,sn=5))
    else:
        if type(max_frames) is not int or not 1<=max_frames<=80 or type(window) is not int or not 125000<=window<=1250000:raise ValueError('fixed lab rate bounds')
        limited=profile=='rate_candidate';v=Vectors(flow,window=window if limited else 0,max_frames=max_frames if limited else 0)
        for i in range(3):v.add('normal_'+str(i),packet(flow,sn=i+1),gap=12500)
        v.cmd(4,window+100)
        for i in range(max_frames+4):v.add('burst_'+str(i),packet(flow,sn=i+10),flags=16 if limited and i>=max_frames else 0)
        v.cmd(4,window+100);v.add('window_recovery',packet(flow,sn=120))
    return v

def audit_outputs(directory,vectors):
    events={};forward={}
    for line in (directory/'security_events.txt').read_text().splitlines():
        ident,cycle,raw=line.split();events.setdefault(int(ident),[]).append(decode_event(int(raw,16)))
    for line in (directory/'forwarded_wire.txt').read_text().splitlines():
        ident,ch,cycle,raw=line.split();forward.setdefault(int(ident),[]).append((int(ch),bytes.fromhex(raw)))
    result=[]
    for c in vectors.cases:
        e=events.get(c['id'],[])
        if len(e)!=1 or e[0]['flags']!=c['flags'] or e[0]['allow']!=c['allow'] or e[0]['channel']!=c['channel']:raise ValueError('independent RTL event audit failed')
        expected=[(c['channel'],vectors.frames[c['index']])] if c['channel']<2 and c['allow'] else []
        if forward.get(c['id'],[])!=expected:raise ValueError('independent RTL forwarded-byte audit failed')
        result.append(dict(name=c['name'],flags=e[0]['flags'],allow=e[0]['allow'],forwarded=len(expected)))
    if len(events)!=len(vectors.cases):raise ValueError('unexpected RTL event count')
    return result

class RTLRunner:
    def __init__(self,root,output,iverilog=None,vvp=None,ivl_base=None,mode='auto'):
        if mode not in ('auto','off','required'):raise ValueError('RTL mode')
        self.root=Path(root);self.output=Path(output);self.output.mkdir(parents=True,exist_ok=True)
        self.iv=iverilog or shutil.which('iverilog');self.vvp=vvp or shutil.which('vvp');self.base=ivl_base;self.mode=mode;self.compiled=None
    def run(self,profile,flow,capture=None,**parameters):
        if self.mode=='off' or not self.iv or not self.vvp:
            if self.mode=='required':raise RuntimeError('Icarus iverilog/vvp required but unavailable')
            return dict(status='unavailable',profile=profile,reason='RTL disabled or Icarus unavailable',proves_current_case_cause=False)
        d=self.output/f'{profile}_{len(list(self.output.glob(profile+"_*"))):02d}';d.mkdir()
        env=dict(os.environ,TMPDIR=str(d),PYTHONDONTWRITEBYTECODE='1')
        manifest=json.loads((self.root/'security_lab/manifest.json').read_text())
        for relative,digest in manifest.items():
            if sha((self.root/relative).read_bytes())!=digest:raise ValueError('lab source hash mismatch')
        commands=[]
        def execute(argv,log,timeout):
            with log.open('w') as f:r=subprocess.run([str(a) for a in argv],cwd=d,env=env,stdout=f,stderr=subprocess.STDOUT,timeout=timeout,creationflags=subprocess.CREATE_NO_WINDOW if os.name=='nt' else 0)
            commands.append(dict(argv=[str(a) for a in argv],exit=r.returncode))
            if r.returncode:raise RuntimeError('RTL command failed: '+log.name)
        if self.compiled is None:
            self.compiled=self.output/'security_lab.vvp'
            cmd=[self.iv]+(['-B',self.base] if self.base else [])+['-g2001','-s','tb_security_plugin','-o',self.compiled,*sorted((self.root/'security_lab/rtl').glob('*.v')),self.root/'security_lab/tb_security_plugin.v']
            execute(cmd,d/'compile.log',45)
        if profile=='captured_pair':
            if capture is None or len(capture)!=2:raise ValueError('capture pair required')
            pair=compare(*capture);first=pair['first']
            if (not pair['both_protocol_checks_valid'] or not pair['same_logical_message'] or
                first.get('fragment_offset') or first.get('more_fragments') or capture[0][22]!=0x45 or capture[1][22]!=0x45):
                return dict(status='inconclusive',reason='capture is not a valid same-message pair',proves_current_case_cause=False)
            if (first.get('source_ip')!=flow['peer_ip'] or first.get('destination_ip')!=flow['local_ip'] or
                first.get('destination_mac')!=flow['rx_mac'].to_bytes(6,'big').hex() or
                first.get('source_port')!=flow['source_port'] or first.get('destination_port')!=flow['destination_port'] or
                (int(first['source_mac'],16)^flow['peer_mac'])&0xffffffffff9f):
                return dict(status='inconclusive',reason='capture does not match trusted lab flow',proves_current_case_cause=False)
            vectors=Vectors(flow);vectors.add('captured_A',capture[0]);vectors.add('captured_B',capture[1],1,0 if pair['normalized_content_equal'] else 4)
        else:vectors=build_profile(profile,flow,**parameters)
        vectors.save(d)
        execute([self.vvp,'-n',self.compiled],d/'simulation.log',60)
        log=(d/'simulation.log').read_text(encoding='utf8',errors='replace')
        if 'SEC_PLUGIN_PASS' not in log or re.search(r'\bFAIL\b|_FAIL\b|TIMEOUT',log) or log.count('SCENARIO_PASS')!=len(vectors.cases):raise RuntimeError('RTL final marker/assertion failure')
        audit=audit_outputs(d,vectors)
        artifact_hashes={p.name:sha(p.read_bytes()) for p in d.iterdir() if p.is_file()}
        result=dict(status='passed',profile=profile,domain='isolated_real_security_RTL',cases=audit,
            commands=commands,directory=str(d.relative_to(self.output.parent)),artifact_sha256=artifact_hashes,
            proves_current_case_cause=False,conclusion='已复现实验机制及完整帧准入行为；未证明当前设备物理根因。')
        (d/'audit.json').write_text(json.dumps(result,indent=2,ensure_ascii=False)+'\n',encoding='utf8')
        return result
