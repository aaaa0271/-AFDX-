"""Actual standalone voter RTL and unchanged security RTL comparisons."""
import json,os,re,shutil,subprocess,sys
from pathlib import Path
R=Path(__file__).resolve().parents[1];sys.path.insert(0,str(R));sys.path.insert(0,str(R/'scripts'))
from fixtures import FLOW,vectors
from afdx_mimic.contract import sha
from security_lab.policy import Rule,COMMIT

def execute(argv,log,cwd,timeout=60):
    env=dict(os.environ,TMPDIR=str(cwd));r=subprocess.run([str(a) for a in argv],cwd=cwd,env=env,capture_output=True,text=True,timeout=timeout)
    log.write_text(r.stdout+r.stderr)
    if r.returncode:raise RuntimeError('RTL command failed: '+log.name)
    return dict(argv=[str(a) for a in argv],exit_code=r.returncode)

def check_rtl(output,iverilog=None,vvp=None,ivl_base=None):
    out=Path(output).resolve()
    if out.exists():raise ValueError('new RTL output directory required')
    iv=iverilog or shutil.which('iverilog');vp=vvp or shutil.which('vvp')
    if not iv or not vp:raise RuntimeError('actual RTL checks require Icarus')
    out.mkdir(parents=True);prefix=[iv]+(['-B',ivl_base] if ivl_base else [])
    voter=out/'quorum';voter.mkdir();commands=[]
    commands.append(execute(prefix+['-g2012','-s','tb_mimic_quorum','-o',voter/'quorum.vvp',R/'rtl/afdx_mimic_quorum_gate.v',R/'rtl/tb_mimic_quorum.v'],voter/'compile.log',voter))
    commands.append(execute([vp,'-n',voter/'quorum.vvp'],voter/'simulation.log',voter));log=(voter/'simulation.log').read_text()
    match=re.search(r'MIMIC_RTL_PASS cases=(\d+) done=(\d+)',log)
    if not match or 'MIMIC_FAIL' in log or 'MIMIC_RTL_FAIL' in log or int(match[1])!=int(match[2]):raise RuntimeError('voter assertions/final marker failed')
    cases=int(match[1]);assert log.count('MIMIC_CASE_PASS')==cases
    # Original testbench and eight security modules are byte-identical copies.
    for path,h in json.loads((R/'security_lab/manifest.json').read_text()).items():
        if sha((R/path).read_bytes())!=h:raise RuntimeError('upstream security RTL source changed')
    original=out/'security';original.mkdir();flow=dict(FLOW,tx_mac=0x030000000012)
    rule=Rule(**flow,timeout=30000);cmd=[]
    def op(code,*args,case_id=0):cmd.append([code,*args,*([0]*(6-len(args))),case_id])
    op(0)
    for a,b in rule.writes(0):op(1,a,b)
    op(1,0,2);op(1,*COMMIT);op(4,20);op(5,0,2)
    selected={'normal_A':0,'normal_B':0,'empty_payload':0,'max_frame':0,'fcs':1,'acl':2,'udp_length':1,'udp_checksum':1,'ip_checksum':1}
    rows=[(n,raw,w,selected[n]) for n,raw,w in vectors() if n in selected]
    ordered=[]
    for i,(name,raw,want,flags) in enumerate(rows):
        # Give each independent replay a distinct AFDX sequence to avoid adding
        # history-dependent A/B semantics to this stateless comparison scope.
        b=bytearray(raw);b[-5]=i+1
        if name!='fcs':
            import binascii
            b[-4:]=binascii.crc32(b[8:-4]).to_bytes(4,'little')
        ordered.append((name,bytes(b),flags));op(2,0,len(b),i,flags,int(flags==0),2,case_id=i+1)
    lines=[raw[::-1].hex().rjust(3072,'0') for _,raw,_ in ordered]+['0'*3072]*(256-len(ordered))
    (original/'frames.hex').write_text('\n'.join(lines)+'\n');(original/'commands.hex').write_text('\n'.join(' '.join(f'{x:08x}' for x in row) for row in cmd)+'\n')
    (original/'vectors.json').write_text(json.dumps([dict(id=i+1,name=n,flags=f,allow=f==0,wire_length=len(raw)) for i,(n,raw,f) in enumerate(ordered)],indent=2)+'\n')
    commands.append(execute(prefix+['-g2001','-s','tb_security_plugin','-o',original/'security.vvp',*sorted((R/'security_lab/rtl').glob('*.v')),R/'security_lab/tb_security_plugin.v'],original/'compile.log',original))
    commands.append(execute([vp,'-n',original/'security.vvp'],original/'simulation.log',original))
    log=(original/'simulation.log').read_text()
    if 'SEC_PLUGIN_PASS' not in log or re.search(r'\bFAIL\b|_FAIL\b|TIMEOUT',log) or log.count('SCENARIO_PASS')!=len(ordered):raise RuntimeError('original security RTL final marker failure')
    events={};forward={}
    for line in (original/'security_events.txt').read_text().splitlines():
        ident,cycle,value=line.split();events.setdefault(int(ident),[]).append(int(value,16))
    for line in (original/'forwarded_wire.txt').read_text().splitlines():
        ident,ch,cycle,raw=line.split();forward.setdefault(int(ident),[]).append((int(ch),bytes.fromhex(raw)))
    checks=[]
    for i,(name,raw,flags) in enumerate(ordered,1):
        e=events.get(i,[]);expected=[(0,raw)] if flags==0 else []
        if len(e)!=1 or (e[0]>>48)&65535!=flags or bool(e[0]&(1<<41))!=(flags==0) or forward.get(i,[])!=expected:raise RuntimeError('independent event/forward-byte audit: '+name)
        checks.append(dict(name=name,flags=flags,forwarded=len(expected),status='PASS'))
    if len(events)!=len(ordered):raise RuntimeError('unexpected security events')
    result=dict(status='PASS',quorum_rtl_cases=cases,original_security_packet_checks=len(checks),checks=checks,commands=commands,
      new_voter_connected_to_original_security=False,complete_mac_wrapper=False,board_validation=False,
      scope='independent voter RTL assertions plus separate original-security frame replay; not integrated end-to-end hardware')
    (out/'summary.json').write_text(json.dumps(result,indent=2)+'\n');return result

if __name__=='__main__':
    import argparse
    p=argparse.ArgumentParser();p.add_argument('--out',type=Path,required=True);p.add_argument('--iverilog');p.add_argument('--vvp');p.add_argument('--ivl-base');a=p.parse_args();print(json.dumps(check_rtl(a.out,a.iverilog,a.vvp,a.ivl_base),indent=2))
