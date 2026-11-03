from pathlib import Path
import sys,json,tempfile,hashlib
R=Path(__file__).resolve().parents[1];sys.path.insert(0,str(R/'host'))
from policy import Rule,COMMIT
from authorizer import *
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
s=(R/'reference_core/tb/tb_integration_multi_services.v').read_text()
s=s.replace('module tb_integration_multi_services;','module tb_security_core_multi;').replace('AFDX_competition_top #(','AFDX_security_plugin_top #(').replace('dut.MULTI_SERVICES','dut.core.MULTI_SERVICES')
s=s.replace('.clk(clk),.rst(rst),.cfg_port_write', '.sec_cfg_write(sec_write),.sec_cfg_read(1\'b0),.sec_cfg_address(sec_address),.sec_cfg_wdata(sec_data),.sec_cfg_ready(sec_ready),.sec_cfg_error(sec_error),.sec_cfg_commit_pulse(sec_commit),.sec_mode(sec_mode),.sec_event_valid(sec_ev),.sec_event_ready(1\'b1),.sec_event_record(sec_record),.sec_queue_overflows(sec_overflows),.sec_hash_failures(sec_hash_fails),.clk(clk),.rst(rst),.cfg_port_write',1)
insert='''
reg sec_write=0;reg [15:0] sec_address=0;reg [31:0] sec_data=0;
wire sec_ready,sec_error,sec_commit,sec_ev;wire [1:0] sec_mode;wire [159:0] sec_record;wire [31:0] sec_overflows,sec_hash_fails;
integer sec_config,sec_n,sec_a,sec_v,sec_fd,security_violations=0;
always @(posedge clk)if(!rst&&sec_ev)begin
 $fwrite(sec_fd,"%0t %040x\\n",$time,sec_record);
 if(sec_record[63:48]!=0)begin security_violations=security_violations+1;$display("SEC_CORE_VIOLATION record=%040x",sec_record);end
end
task configure_security;begin
 sec_fd=$fopen("core_security_events.txt","w");sec_config=$fopen("core_config.hex","r");
 while(!$feof(sec_config))begin
  sec_n=$fscanf(sec_config,"%h %h\\n",sec_a,sec_v);
  if(sec_n==2)begin wait(sec_ready);@(negedge clk);sec_address=sec_a;sec_data=sec_v;sec_write=1;@(negedge clk);sec_write=0;if(sec_error)fail("security configuration");end
 end
 $fclose(sec_config);repeat(20)@(negedge clk);
 if(sec_mode!=2)fail("security enforcement not active");
end endtask
'''
s=s.replace('wire [31:0] peers_tx;',insert+'\nwire [31:0] peers_tx;')
s=s.replace('rst=0;repeat(20)', 'rst=0;configure_security;repeat(20)')
s=s.replace('$display("MULTI_FINAL', '''if(sec_overflows!=0||sec_hash_fails!=0||security_violations!=0)fail("security plugin rejects normal baseline flow");
 $fclose(sec_fd);$display("SEC_CORE_FINAL violations=%0d queue_overflows=%0d hash_failures=%0d",security_violations,sec_overflows,sec_hash_fails);
 $display("MULTI_FINAL''')
s=s.replace('TB_INTEGRATION_MULTI_SERVICES_PASS','SEC_CORE_MULTI_PASS').replace('TB_INTEGRATION_MULTI_SERVICES_FAIL','SEC_CORE_MULTI_FAIL')
(R/'tb/tb_security_core_multi.v').write_text(s)
# Signed manifests for each independent baseline loader; actual peer fixtures.
contents={name:bytes(int(x,16) for x in (R/'reference_core/tb'/f'{name}.hex').read_text().split()) for name in ('APP.LUH','A.LUP','B.LUP')}
assert [len(contents[n]) for n in contents]==[126,700,1024]
key=Ed25519PrivateKey.generate();writes=[];public=key.public_key().public_bytes_raw();receipts=[];grant_index=0
for domain in range(2):
 for kind in (2,3):
  rule_id=domain if kind==2 else domain+2
  rule=Rule(0x0a000001+domain if kind==2 else 0x0a000101+domain,0x0a000010,0x030000000010+domain*2+(kind==3),0x020000000002,kind=kind,source_port=123 if kind==3 else 0,destination_port=40001 if kind==3 else 0,tx_mac=0x030000000020+domain*2+(kind==3),signed_loading=kind==2,timeout=300000,max_contexts=4)
  writes+=rule.writes(rule_id)
 if True:
  doc=dict(schema=1,target='SIM',hardware_id=f'{0x4d4953:064x}',nonce=f'{domain+1:064x}',version=7,issued_at=100,expires_at=200,files=[dict(name=n,length=len(c),sha256=hashlib.sha256(c).hexdigest()) for n,c in contents.items()])
  with tempfile.TemporaryDirectory() as t:
   state=Path(t)/'state.json';initialize_state(state,'SIM',doc['hardware_id'],6)
   receipt=authorize(doc,key.sign(canonical(doc)),public,state_path=state,target='SIM',hardware_id=doc['hardware_id'],nonce=doc['nonce'],now=150,rule_id=domain,lease_cycles=5000000)
  receipts.append(dict(document=doc,signature=key.sign(canonical(doc)).hex(),receipt=receipt))
  # Compose disjoint grants into one complete shadow transaction.
  for item in receipt['writes']:
   a=item['address'];v=item['value']
   if a<0x1000:writes.append((a,v))
   elif a<0x1000+len(contents)*128:writes.append((a+grant_index*128,v))
  grant_index+=len(contents)
for index in range(grant_index,16):writes.append((0x1000+index*128,0))
writes+=[(0,2),COMMIT]
(R/'tb/core_config.hex').write_text('\n'.join(f'{a:04x} {v:08x}' for a,v in writes)+'\n')
(R/'tb/core_signed_authorizations.json').write_text(json.dumps(dict(public_key=public.hex(),domains=receipts),indent=2)+'\n')
print('INTEGRATION_GENERATED two signed loaders / two clock peers; all baseline ports retained')
