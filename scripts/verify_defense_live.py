"""Actual ModelSim MAC traffic + four native workers + TCN CSR integration.

The loopback control socket is a trusted simulator transport. The simulator is
paused during host computation, then resumed for bounded hardware deadlines.
No Icarus, eLinx expansion, board or fabricated executor responses are used.
"""
import argparse
import hashlib
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import time
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
sys.path[:0]=[str(ROOT),str(ROOT/'host'),str(ROOT/'mimic_plugin'),str(ROOT/'aihw_plugin')]
from policy import Rule,COMMIT
from defense_runtime import DefenseRuntime
from afdx_mimic.build import build
from afdx_mimic.workers import WorkerPool
from afdx_agent.packets import packet,parse
from afdx_ai_hw.fixed import prepare_history,integer_tcn,load_model


TCL=r'''
onerror {quit -code 2 -f}
onbreak {resume}
vlib work
vmap work work
__COMPILE__
vsim -c -voptargs=+acc -onfinish stop -t 1ps -lib work tb_defense_live
run 1600 ns
set sock [socket 127.0.0.1 __PORT__]
fconfigure $sock -buffering line -translation lf
proc getv {name} { return [string trim [examine -radix unsigned sim:/tb_defense_live/$name]] }
proc drive {name value} {
 if {[string first # $value]<0} {set value 10#$value}
 force -freeze sim:/tb_defense_live/$name $value
}
proc access {addr value write secure} {
 if {$secure} {set p sec_;set a addr;set w wdata;set v write;set r rdata} else {set p defense_cfg_;set a addr;set w wdata;set v valid;set r rdata}
 drive ${p}${a} $addr
 if {$secure} {drive sec_write $write} else {drive defense_cfg_valid 1;drive defense_cfg_write $write}
 drive ${p}${w} $value
 run 0 ns
 set tries 0
 while {![getv ${p}ready]&&$tries<20000} {run 80 ns;incr tries}
 if {$tries==20000||[getv ${p}error]} {error "CSR rejected $addr ready=[getv ${p}ready] error=[getv ${p}error] actual_addr=[getv ${p}${a}]"}
 set result [getv ${p}${r}]
 run 80 ns
 if {$secure} {drive sec_write 0} else {drive defense_cfg_valid 0}
 return $result
}
puts $sock READY
flush $sock
while {[gets $sock line]>=0} {
 set fields [split $line]
 set op [lindex $fields 0]
 if {[catch {
  switch -- $op {
   R {set result [access [lindex $fields 1] 0 0 0]}
   W {set result [access [lindex $fields 1] [lindex $fields 2] 1 0]}
   S {set result [access [lindex $fields 1] [lindex $fields 2] 1 1]}
   RB {set result {};for {set n 0} {$n<[lindex $fields 2]} {incr n} {lappend result [access [expr {[lindex $fields 1]+$n*4}] 0 0 0]}}
   WB {foreach {addr value} [lrange $fields 1 end] {access $addr $value 1 0};set result 0}
   RUN {run [expr {[lindex $fields 1]*80}] ns;set result 0}
   EX {set result [getv [lindex $fields 1]]}
   INJ {
    set leg [expr {[llength $fields]>2&&[lindex $fields 2]==1?"b":"a"}]
    drive ${leg}_valid 1
    foreach {byte} [regexp -all -inline {..} [lindex $fields 1]] {drive ${leg}_rx 16#$byte;run 80 ns}
    drive ${leg}_valid 0;run 80 ns;set result 0
   }
   POLL {drive poll 1;run 80 ns;drive poll 0;run 80 ns;set result 0}
   IMAGE {
    drive image_file [lindex $fields 1];run 0 ns;set result {}
    set size [getv image_length]
    for {set n 0} {$n<$size} {incr n} {drive image_address $n;run 0 ns;append result [format %02x [getv image_data]]}
   }
   TX {
    set size [getv tx_head_length]
    if {$size==0} {set result "0 0"} else {
     set result "$size [string trim [examine -radix hex sim:/tb_defense_live/tx_head]]"
     drive tx_read [expr {[getv tx_read]+1}];run 0 ns
    }
   }
   QUIT {puts $sock "OK 0";flush $sock;close $sock;quit -code 0 -f}
   default {error "unknown trusted command"}
  }
 } why]} {puts $sock "ERROR $why";flush $sock;quit -code 3 -f}
 puts $sock "OK $result"
 flush $sock
}
quit -code 4 -f
'''


class Transport:
    def __init__(self,connection):
        connection.setsockopt(socket.IPPROTO_TCP,socket.TCP_NODELAY,1)
        self.stream=connection.makefile('rwb',buffering=0)
        self.commands=[]
        self.cache={};self.pending=[];self.packet_length=0
        if self.stream.readline().strip()!=b'READY':raise RuntimeError('simulator handshake')
    def command(self,line):
        self.stream.write((line+'\n').encode('ascii'))
        reply=self.stream.readline().decode('ascii').strip()
        self.commands.append(dict(command=line,response=reply))
        if not reply.startswith('OK '):raise RuntimeError(reply or 'simulator disconnected')
        return reply[3:]
    def read(self,address):
        self.flush()
        if address in self.cache:return self.cache.pop(address)
        if address in (0x100,0x1008,0x1800):
            count=64 if address==0x100 else 9 if address==0x1008 else (self.packet_length+3)//4
            values=[int(x) for x in self.command(f'RB {address} {count}').split()]
            self.cache.update({address+i*4:value for i,value in enumerate(values)})
            if address==0x1008:self.packet_length=values[5]&0x7ff
            return self.cache.pop(address)
        value=int(self.command('R '+str(address)))
        if address==8 and not value&1 and not value&4:self.run(128)
        return value
    def write(self,address,value):
        if address==0x20 or 0x1100<=address<0x1200:
            self.pending.extend((address,value))
            if address==0x20 and value&65536:self.flush()
            return
        self.flush();self.cache={};self.command(f'W {address} {value}')
    def flush(self):
        if self.pending:self.command('WB '+' '.join(map(str,self.pending)));self.pending=[]
    def run(self,cycles):self.flush();self.cache={};self.command('RUN '+str(cycles))
    def inject(self,raw,channel=0):self.command('INJ '+raw.hex()+' '+str(channel))
    def value(self,name):return int(self.command('EX '+name))
    def tx(self):
        size,hexstr=self.command('TX').split()
        return int(hexstr,16).to_bytes(1536,'little')[:int(size)]


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,required=True)
    p.add_argument('--modelsim',default='C:/modeltech64_2020.4/win64/vsim.exe')
    def compiler(name):
        found=shutil.which(name)
        candidate=Path('C:/Program Files/RedPanda-Cpp/mingw64/bin')/(name+'.exe')
        return found or (str(candidate) if candidate.is_file() else None)
    p.add_argument('--cc',default=compiler('gcc'));p.add_argument('--cxx',default=compiler('g++'))
    args=p.parse_args();out=args.out.resolve()
    if args.cc:os.environ['PATH']=str(Path(args.cc).parent)+os.pathsep+os.environ.get('PATH','')
    if out.exists():raise RuntimeError('choose a fresh output directory')
    out.mkdir(parents=True)
    roots=('rtl','host','mimic_plugin','aihw_plugin','scripts','tb')
    sources={f.relative_to(ROOT).as_posix():hashlib.sha256(f.read_bytes()).hexdigest() for d in roots for f in (ROOT/d).rglob('*') if f.is_file() and '__pycache__' not in f.parts and 'reports' not in f.parts and f.suffix!='.pyc'}
    (out/'source_hashes.json').write_text(json.dumps(sources,indent=2)+'\n')
    build(ROOT/'mimic_plugin',out/'native',args.cc,args.cxx)
    pool=WorkerPool(ROOT/'mimic_plugin',out/'native')
    listener=socket.socket();listener.bind(('127.0.0.1',0));listener.listen(1);listener.settimeout(120)
    production=sorted((ROOT/'rtl').glob('*.v'))+[ROOT/'aihw_plugin/rtl/afdx_ai_tcn_plugin.v',ROOT/'tb/tb_defense_live.v']
    rom=out/'aihw_plugin/rtl';rom.mkdir(parents=True)
    for file in (ROOT/'aihw_plugin/rtl').glob('*.mem'):shutil.copyfile(file,rom/file.name)
    compile_line='vlog -vlog01compat -work work {+incdir+'+(ROOT/'aihw_plugin/rtl').as_posix()+'} '+' '.join('{'+f.as_posix()+'}' for f in production)
    (out/'run.do').write_text(TCL.replace('__PORT__',str(listener.getsockname()[1])).replace('__COMPILE__',compile_line))
    process=None;transport=None
    try:
        with (out/'console.log').open('wb') as log:
            process=subprocess.Popen([args.modelsim,'-c','-do','run.do','-l','result.log'],cwd=out,stdout=log,stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NO_WINDOW if os.name=='nt' else 0)
            connection,_=listener.accept();connection.settimeout(180);transport=Transport(connection)
            flow=dict(peer_ip=0x0a000020,local_ip=0x0a000010,rx_mac=0x030000000040,peer_mac=0x020000000002,source_port=10000,destination_port=20000,tx_mac=0x030000000041)
            clock_flow=dict(flow,peer_ip=0x0a000101,rx_mac=0x030000000010,tx_mac=0x030000000012,source_port=123,destination_port=40001)
            loader_flow=dict(flow,peer_ip=0x0a000001,rx_mac=0x030000000010,tx_mac=0x030000000012,source_port=0,destination_port=0)
            rules={0:Rule(**{k:v for k,v in flow.items() if k in Rule.__dataclass_fields__},fragments=True),1:Rule(**{k:v for k,v in clock_flow.items() if k in Rule.__dataclass_fields__},kind=3),2:Rule(**{k:v for k,v in loader_flow.items() if k in Rule.__dataclass_fields__},kind=2)}
            for index,rule in rules.items():
                for address,value in rule.writes(index):transport.command(f'S {address} {value}')
            transport.command(f'S {COMMIT[0]} {COMMIT[1]}');transport.run(30)
            epoch=transport.value('sec_epoch')
            policy=dict(schema=1,epoch=epoch,rules=[dict(id=i,**{k:getattr(rule,k) for k in ('peer_ip','local_ip','rx_mac','peer_mac','source_port','destination_port','max_mac')},require_udp_checksum=False) for i,rule in rules.items()])
            policy['rules'][0]['allow_fragments']=True
            try:runtime=DefenseRuntime(transport.read,transport.write,pool,policy,source='rtl_simulation',advance=transport.run,multiplexed_rules=(2,))
            finally:(out/'native_startup.json').write_text(json.dumps(getattr(pool,'startup_certificates',[]),indent=2)+'\n')
            print('DEFENSE_STAGE native_startup_pass',flush=True)
            # First establish an actual NTP session through security + quorum.
            transport.command('POLL');transport.run(2500)
            request_raw=transport.tx();request_info=parse(request_raw)
            if 'ntp' not in request_info or request_info['issues']:raise RuntimeError('no independently valid real NTP request')
            origin=request_info['ntp']['transmit'];reply=bytearray(48);reply[0]=0x24;reply[1]=1
            for start,value in ((24,origin),(32,origin+(1<<32)),(40,origin+(1<<32))):reply[start:start+8]=value.to_bytes(8,'big')
            transport.inject(packet(clock_flow,bytes(reply),sn=0));transport.run(400)
            first=runtime.service_one()
            if first is None or not first['rtl_allow']:
                debug={name:transport.value(name) for name in ('sec_allow','sec_block','dut.security.engine.flags','dut.security.engine.ntp_waiting','dut.security.engine.state','dut.mimic.requests','dut.mimic.state','dut.security.engine.rule_q')}
                raise RuntimeError('NTP not released by live quorum '+repr(debug))
            transport.run(2500)
            if not transport.value('locked'):raise RuntimeError('NTP failed after added defense queues')
            print('DEFENSE_STAGE ntp_security_mimic_core_pass',flush=True)
            # Drive the real 615A target from actual wire exchanges. The host
            # bridge services every accepted loader frame through native votes.
            loader_sequence=1;processed_tx=set();current_file=None;position=0;block_number=0;final_report=False
            file_data={'APP.LUH':(ROOT/'tb/APP.LUH').read_bytes(),'A.LUP':(ROOT/'tb/A.LUP').read_bytes(),'B.LUP':(ROOT/'tb/B.LUP').read_bytes()}
            def send_loader(payload,source_port,destination_port):
                nonlocal loader_sequence
                raw=packet(loader_flow,payload,sp=source_port,dp=destination_port,sn=loader_sequence)
                loader_sequence=(loader_sequence+1)%256 or 1
                blocked_before=transport.value('sec_block')
                transport.inject(raw);transport.run(max(300,len(raw)*3+200))
                # A long target DATA frame is still being checked on the TX
                # tap when the peer ACK arrives. Wait for this injected frame
                # to finish security processing before consuming its quorum job.
                for _ in range(300):
                    if transport.read(0x1004)&1 or transport.value('sec_block')>blocked_before:break
                    transport.run(128)
                result=runtime.service_one()
                if result is None or not result['rtl_allow']:raise RuntimeError('live loader frame denied '+repr((source_port,destination_port,payload[:4].hex())))
                print('DEFENSE_LOADER_RX',source_port,destination_port,payload[:4].hex(),flush=True)
                transport.run(600)
            def next_tx():
                for _ in range(300):
                    raw=transport.tx()
                    if raw:return raw
                    transport.run(128)
                raise TimeoutError('no target loader response')
            processed_tx.add(transport.value('tx_frames'))
            send_loader(b'\0\1TARGET.LUI\0octet\0',32000,69)
            lui_received=False;lur_sent=False
            for exchange in range(60):
                raw=next_tx();info=parse(raw)
                if info['issues']:raise RuntimeError('independent target wire audit failed '+repr(info['issues']))
                if 'tftp' not in info:continue
                payload=raw[50:50+info['udp_length']-8];sport=info['source_port'];dport=info['destination_port'];op=int.from_bytes(payload[:2],'big')
                if sport==41000 and op==3:
                    if payload[4:14]!=bytes.fromhex('0000000a413400010100'):raise RuntimeError('unexpected LUI bytes')
                    send_loader(b'\0\4\0\1',32000,41000);lui_received=True
                    send_loader(b'\0\2TARGET.LUR\0octet\0',32000,69)
                elif sport==41000 and op==4 and payload[2:4]==b'\0\0':
                    lur=bytes.fromhex('000000174134000108')+b'APP.LUH\0'+bytes([5])+b'PN-1\0'
                    send_loader(b'\0\3\0\1'+lur,32000,41000);lur_sent=True
                elif 42000<=sport<43000 and op==1:
                    name=payload[2:].split(b'\0')[0].decode('ascii');current_file=file_data[name];position=0;block_number=1
                    send_loader(b'\0\3'+block_number.to_bytes(2,'big')+current_file[:512],30000,sport)
                elif 42000<=sport<43000 and op==4:
                    if current_file is not None and len(current_file)-position>=512:
                        position+=512;block_number+=1
                        send_loader(b'\0\3'+block_number.to_bytes(2,'big')+current_file[position:position+512],30000,sport)
                elif sport==40002 and op==2:send_loader(b'\0\4\0\0',30002,40002)
                elif sport==40002 and op==3:
                    final_report=payload[10:12]==b'\0\3'
                    send_loader(b'\0\4\0\1',30002,40002)
                    if final_report:break
            if not lui_received or not lur_sent or not final_report or not transport.value('dut.core.image_valid'):raise RuntimeError('integrated package did not atomically commit')
            for file,name in enumerate(('A.LUP','B.LUP')):
                actual=bytes.fromhex(transport.command('IMAGE '+str(file)))
                if actual!=file_data[name]:raise RuntimeError('actual integrated package bytes differ: '+name)
            if transport.value('package_generation')!=1:raise RuntimeError('unexpected integrated package generation')
            print('DEFENSE_STAGE full_loader_security_mimic_core_pass',flush=True)
            # Operator-selected download crosses the same default ENFORCE
            # security engine, real heterogeneous host quorum and GMII core.
            from download615a import DownloadReceiver, selection_file, parse_directory
            receiver=DownloadReceiver()
            # Respect the upload control server's final-ACK dally interval.
            transport.run(101000)
            send_loader(b'\x00\x01TARGET.LNO\x00octet\x00',32004,69)
            directory_seen=False;selection_sent=False;unload_done=False
            for exchange in range(100):
                raw=next_tx();info=parse(raw)
                if info['issues']:raise RuntimeError('download MAC audit '+repr(info['issues']))
                payload=raw[50:50+info['udp_length']-8];sport=info['source_port'];op=int.from_bytes(payload[:2],'big')
                # TX A/B learning must finish before a fast simulated peer
                # can respond. This advances the actual security RTL.
                transport.run(max(600,len(raw)*6))
                if sport==44000 and op==3:
                    if payload[4:]!=bytes.fromhex('000000094134000100'):raise RuntimeError('LNO initialization')
                    send_loader(b'\x00\x04\x00\x01',32004,44000)
                elif sport==44000 and op==4 and payload[2:4]==b'\x00\x00':
                    send_loader(b'\x00\x03\x00\x01'+selection_file(['A.LUP','B.LUP']),32005,44000)
                elif sport==44001:
                    response,event=receiver.receive(payload)
                    send_loader(response,30004,44001)
                    if event and event['name']=='TARGET.LNL':
                        directory=parse_directory(event['data'])
                        if [x['name'] for x in directory]!=['A.LUP','B.LUP']:raise RuntimeError('download directory')
                        directory_seen=True
                        send_loader(b'\x00\x02TARGET.LNA\x00octet\x00',32005,69);selection_sent=True
                    if event and event['name']=='TARGET.LNS' and event['status']['code']==3:
                        unload_done=True;break
            if not (directory_seen and selection_sent and unload_done):raise RuntimeError('integrated download lifecycle')
            for name in ('A.LUP','B.LUP'):
                if receiver.files.get(name)!=file_data[name]:raise RuntimeError('integrated downloaded bytes: '+name)
            if transport.value('package_generation')!=1:raise RuntimeError('download mutated package bank')
            receiver.save(out/'download')
            print('DEFENSE_STAGE full_download_security_mimic_core_pass',flush=True)
            baseline=transport.value('payload_frames')
            checks=[dict(case='actual_615A_665_loading_through_security_and_mimic',status='PASS',files=list(file_data)),
                    dict(case='actual_615A_download_through_security_mimic_and_GMII',status='PASS',files=['A.LUP','B.LUP'])]

            runtime.collect_window()
            for index in range(8):
                transport.inject(packet(flow,bytes([0x1a,13,10,index])*4,sn=index))
                transport.run(250)
                result=runtime.service_one()
                if result is None or not result['rtl_allow']:raise RuntimeError('healthy frame not released')
                transport.run(600)
                metrics=runtime.collect_window()
                checks.append(dict(case='healthy_live',index=index,allow=result['rtl_allow'],metrics=metrics))
                print('DEFENSE_STAGE live_window',index,metrics['status'],flush=True)
            if transport.value('payload_frames')!=baseline+8:raise RuntimeError('quorum did not reach actual application')
            transport.inject(packet(flow,bytes([0x1a,13,10,7])*4,sn=7,network='B'),channel=1);transport.run(400)
            duplicate=runtime.service_one();transport.run(600)
            if duplicate is None or not duplicate['rtl_allow'] or duplicate['channel']!=1 or transport.value('payload_frames')!=baseline+8:raise RuntimeError('B-network quorum or core duplicate suppression failed')
            checks.append(dict(case='actual_B_network_and_AB_duplicate_suppression',status='PASS'))
            full=packet(flow,bytes(range(32)),sn=8,ip_id=10)
            udp=full[42:82]
            for offset,chunk,more,sn in ((0,udp[:24],True,8),(24,udp[24:],False,9)):
                fragment=packet(flow,b'',sn=sn,ip_id=10,fragment=(offset//8)|(8192 if more else 0),ip_payload=chunk)
                transport.inject(fragment);transport.run(250)
                result=runtime.service_one()
                if result is None or not result['rtl_allow']:raise RuntimeError('heterogeneous fragment validation failed')
                transport.run(600)
            if transport.value('payload_frames')!=baseline+9:raise RuntimeError('fragmented datagram did not reach actual application')
            checks.append(dict(case='actual_fragment_quorum_and_core_reassembly',status='PASS'))
            # Corrupt FCS must be stopped by the existing security baseline.
            corrupt=bytearray(packet(flow,b'bad-fcs',sn=20));corrupt[-1]^=1
            before=transport.value('sec_block');transport.inject(bytes(corrupt));transport.run(500)
            if transport.value('sec_block')<=before or transport.read(0x1004)&1:raise RuntimeError('security baseline bypassed')
            checks.append(dict(case='security_denies_before_mimic',status='PASS'))
            # A real executor process returns a semantic minority; the other
            # two independent processes agree, and the fourth is scheduled.
            offender=runtime.mimic.active[0];runtime.mimic.pool.set_lab_fault(offender,'wrong_semantics')
            transport.inject(packet(flow,b'minority-isolation',sn=21));transport.run(250)
            minority=runtime.service_one();transport.run(600)
            if not minority['rtl_allow'] or offender not in runtime.mimic.quarantined:raise RuntimeError('minority isolation failed')
            runtime.mimic.pool.set_lab_fault(offender,None)
            checks.append(dict(case='real_process_minority_quarantined',offender=offender,next_active=runtime.mimic.active,status='PASS'))
            # No host result: no frame bytes may reach the application.
            before=transport.value('payload_frames');transport.inject(packet(flow,b'host-offline',sn=22));transport.run(101000)
            if transport.value('payload_frames')!=before or transport.value('timeouts')<1:raise RuntimeError('missing host failed open')
            checks.append(dict(case='host_absence_fails_closed',status='PASS'))
            transport.run(100100)
            # Exercise the actual TCN on measured windows. Model-derived
            # invalid results must never arm an actuator.
            cfg,params=load_model()
            history=[row['metrics'] for row in runtime.history]
            if len(history)!=8:raise RuntimeError('no eight-window measured history')
            ordered=[[row[key] for key in __import__('afdx_ai_hw.fixed',fromlist=['FEATURES']).FEATURES] for row in history]
            result=runtime.last_inference
            if result is None:raise RuntimeError('live measured windows never reached hardware inference')
            qx,flags,_=prepare_history(ordered,cfg,params);expected,_=integer_tcn(qx[None],cfg,params)
            if result['raw_logits_q']!=expected[0].tolist():raise RuntimeError('integrated TCN differs from integer reference')
            checks.append(dict(case='live_measurements_to_actual_TCN',status='PASS',result=result))
            # A declared synthetic validation window exercises the actuator's
            # positive branch; it is never labelled a live measurement.
            import numpy as np
            data=np.load(ROOT/'aihw_plugin/source_model/data/test.npz',allow_pickle=False)['X']
            chosen=None
            for candidate in data:
                q,f,_=prepare_history(candidate,cfg,params)
                logits,saturation=integer_tcn(q[None],cfg,params)
                mask=sum(int(logits[0,i]>=params['thresholds_q'][i])<<i for i in range(8))
                if f==0 and mask and saturation[0]==0:
                    chosen=candidate;break
            if chosen is None:raise RuntimeError('no supported positive actuator validation vector')
            runtime.configure_ai_response(True)
            acted=runtime.ai.analyze(chosen,job_id=101)
            if acted['status']!='candidate' or acted['candidate_mask']==0 or not transport.value('ai_block'):raise RuntimeError('AI candidate did not arm bounded RX action')
            before=transport.value('payload_frames');transport.inject(packet(flow,b'AI-temporary-block',sn=23));transport.run(250)
            blocked_by_ai=runtime.service_one();transport.run(500)
            if blocked_by_ai is None or blocked_by_ai['rtl_reason']!=4 or transport.value('payload_frames')!=before:raise RuntimeError('AI did not affect actual frame admission')
            transport.run(6000)
            if transport.value('ai_block'):raise RuntimeError('AI action did not expire')
            runtime.configure_ai_response(False)
            checks.append(dict(case='actual_TCN_to_bounded_RX_block',status='PASS',input_source='declared_synthetic_validation_vector',result=acted))
            agent=runtime.investigate(out/'live_agent')
            if agent['status']!='PASS':raise RuntimeError('existing agent did not consume live evidence')
            checks.append(dict(case='existing_agent_with_live_evidence',status='PASS',steps=agent['report']['steps']))
            summary=dict(status='PASS',source='actual_ModelSim_and_native_processes',checks=checks,
                         frames=len(runtime.records),executors=list(pool.info['executors']),startup_checks=sum(len(x['vectors']) for x in pool.startup_certificates),
                         main_data_path_connected=True,security_connected=True,mimic_connected=True,ai_connected=True,
                         board_tested=False,elaboration_performed=False,synthesis_performed=False)
            if transport.value('errors')!=0:raise RuntimeError('RTL testbench assertions')
            changed=[name for name,value in sources.items() if not (ROOT/name).is_file() or hashlib.sha256((ROOT/name).read_bytes()).hexdigest()!=value]
            if changed:raise RuntimeError('integrated sources changed during verification: '+repr(changed))
            transport.command('QUIT');process.wait(timeout=20)
            (out/'summary.json').write_text(json.dumps(summary,indent=2)+'\n',encoding='utf-8')
            (out/'mimic_records.json').write_text(json.dumps(runtime.records,indent=2)+'\n',encoding='utf-8')
            (out/'transport.json').write_text(json.dumps(transport.commands,indent=2)+'\n',encoding='utf-8')
            print('DEFENSE_LIVE_INTEGRATION_PASS',json.dumps({k:v for k,v in summary.items() if k!='checks'}),flush=True)
    finally:
        listener.close()
        if process is not None and process.poll() is None:
            try:
                if transport is not None:transport.command('QUIT')
                process.wait(timeout=10)
            except Exception:
                if os.name=='nt':subprocess.run(['taskkill','/PID',str(process.pid),'/T','/F'],capture_output=True,creationflags=subprocess.CREATE_NO_WINDOW)
                else:process.kill()
                process.wait()
        if transport is not None:(out/'transport.json').write_text(json.dumps(transport.commands,indent=2)+'\n',encoding='utf-8')


if __name__=='__main__':main()
