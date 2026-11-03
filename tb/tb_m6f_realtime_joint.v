`timescale 1ns/1ps
module tb_m6f_realtime_joint;
reg clk=0; always #40 clk=~clk;
reg rst=1;
reg [7:0] rxd=0;
reg dv=0;
reg tx_enable=0, network_a_enable=1, network_b_enable=1;
reg cfg_we=0;
reg [1:0] cfg_vl_id=0;
reg [31:0] cfg_bag=32'd1200;
reg [7:0] cfg_destination=8'h02;
reg app_wr_en=0;
reg [1:0] app_wr_vl_id=0;
reg [7:0] app_wr_data=0;
reg fault_enable=0;
reg [15:0] app_length=0;reg app_sof=0,app_eof=0;wire app_ready,app_error;
reg loopback=0;integer business_index=0, business_frames=0,business_bytes=0,physical_a=0,physical_b=0,business_crc_errors=0;
integer offered_length[0:7],offered_seed[0:7];integer offered=0;integer wire_index=0,wire_n,wire_k;
reg [31:0] wire_crc=32'hffffffff;reg wire_previous=0;
reg [7:0] business_wire[0:1537];
reg [7:0] management_rx_seq=39;
reg saw_concurrent=0;
time input_fcs_time=0,rx_latency_max=0,rx_latency;
reg [7:0] data_a_rxd=0, data_b_rxd=0;
reg data_a_rx_dv=0, data_b_rx_dv=0, data_a_rx_er=0, data_b_rx_er=0;
reg payload_ready=1;
wire app_wr_accept;
wire [7:0] data_a_txd, data_b_txd, payload_data, txd;
wire data_a_tx_en, data_b_tx_en, data_a_tx_er, data_b_tx_er;
wire data_a_done, data_b_done, payload_valid, payload_sof, payload_eof, payload_network;
wire txen, txer, txdone, underrun, busy, commit, rd, re;
wire [7:0] error_code;
wire [31:0] ip;
wire [15:0] sp, dp;
wire [10:0] len;
wire [7:0] pd, seq;
wire rv, result_valid, accept, reject, crc_error, boundary_busy;
assign result_valid = dut.management_rx_result_valid;
assign accept = dut.management_rx_accept;
assign reject = dut.management_rx_reject;
assign crc_error = dut.management_crc_error;
assign boundary_busy = dut.management_boundary_busy;
afdx_m6f_system_top #(.CLK_HZ(12_500_000),.MANAGEMENT_BAG_CYCLES(50000)) dut (
 .mib_live(),
    .rx_cfg_table(672'd0),
 .clk(clk),.rst(rst),.tx_enable(tx_enable),.network_a_enable(network_a_enable),.network_b_enable(network_b_enable),
 .cfg_we(cfg_we),.cfg_vl_id(cfg_vl_id),.cfg_bag(cfg_bag),.cfg_destination(cfg_destination),
 .app_wr_len(app_length),.app_wr_sof(app_sof),.app_wr_eof(app_eof),.cfg_lmax(16'd1518),.app_wr_ready(app_ready),.app_len_error(app_error),
 .app_wr_en(app_wr_en),.app_wr_vl_id(app_wr_vl_id),.app_wr_data(app_wr_data),.app_wr_accept(app_wr_accept),.fault_enable(fault_enable),
 .data_a_txd(data_a_txd),.data_b_txd(data_b_txd),.data_a_tx_en(data_a_tx_en),.data_b_tx_en(data_b_tx_en),.data_a_tx_er(data_a_tx_er),.data_b_tx_er(data_b_tx_er),
 .data_a_done(data_a_done),.data_b_done(data_b_done),.data_a_rxd(data_a_rxd),.data_b_rxd(data_b_rxd),.data_a_rx_dv(data_a_rx_dv),.data_b_rx_dv(data_b_rx_dv),.data_a_rx_er(data_a_rx_er),.data_b_rx_er(data_b_rx_er),
 .payload_data(payload_data),.payload_valid(payload_valid),.payload_sof(payload_sof),.payload_eof(payload_eof),.payload_network(payload_network),.payload_ready(payload_ready),
 .management_rxd(rxd),.management_rx_dv(dv),.management_rx_er(1'b0),.management_txd(txd),.management_tx_en(txen),.management_tx_er(txer),.management_done(txdone),.management_busy(busy),.management_commit(commit),.management_response_done(rd),.management_response_error(re),.management_error_code(error_code));
localparam [367:0] GET=368'h302c02010104067075626c6963a01f0204123456780201000201003011300f060b2b0601040181fd590101010500;
localparam [391:0] RESP=392'h302f02010104067075626c6963a22202041234567802010002010030143012060b2b0601040181fd590101010203060a01;
reg [7:0] input_bytes[0:191], expected[0:127];
reg [367:0] request_bytes;
reg [391:0] golden_ber=RESP;
integer golden_ber_length=49;
localparam [367:0] END_RESP=368'h302c02010104067075626c6963a21f0204123456780201000201003011300f060b2b0601040181fd590101198200;
integer errors=0, frames=0, commits=0, results=0, rejects=0, crc_errors=0;
integer idx=0, case_id=0, cycles=0, last_start=-1000000, expected_len=104, expected_error=0;
reg in_tx=0;
integer j, walk_id;
integer fault_mode=0;
integer udp_test_mode=0;
reg [7:0] walk_type, walk_value;
reg [7:0] returned_oid;
// Independent uptime clock and snapshot-request scoreboard. Rebuild the
// expected UDP/IP lengths and FCS before serialization, never from response data.
integer oracle_cycles=0, oracle_snaps=0, oracle_value, oracle_n, oracle_k;
always @(posedge clk) begin
 if(rst) begin oracle_cycles=0;oracle_snaps=0;end
 else begin
  if(dut.u_management.u_integration.u_m6d.snapshot_req_q) begin
   oracle_snaps=oracle_snaps+1;
   if(case_id==14 || case_id==15) begin
    oracle_value=(case_id==14)?oracle_snaps:(oracle_cycles/10);
    oracle_n=(oracle_value>32767)?3:((oracle_value>127)?2:1);
    golden_ber_length=46+oracle_n;
    golden_ber[391-1*8 -:8]=golden_ber_length-2;
    golden_ber[391-14*8 -:8]=golden_ber_length-15;
    golden_ber[391-28*8 -:8]=17+oracle_n;
    golden_ber[391-30*8 -:8]=15+oracle_n;
    golden_ber[391-45*8 -:8]=oracle_n;
    for(oracle_k=0;oracle_k<oracle_n;oracle_k=oracle_k+1)
     golden_ber[391-(46+oracle_k)*8 -:8]=oracle_value>>((oracle_n-oracle_k-1)*8);
    golden(32'hc0a80171,40007,5+walk_id);
   end
  end
  oracle_cycles=oracle_cycles+1;
 end
end
always @(negedge clk) if(loopback)begin
 data_a_rxd=data_a_txd;data_b_rxd=data_b_txd;
 data_a_rx_dv=data_a_tx_en;data_b_rx_dv=data_b_tx_en;
 data_a_rx_er=data_a_tx_er;data_b_rx_er=data_b_tx_er;
 payload_ready=(cycles%7)!=0;
end
function [31:0] crc_business;input [31:0] c;input [7:0] x;integer b;reg [31:0] v;begin
 v=c^x;for(b=0;b<8;b=b+1)v=v[0]?(v>>1)^32'hedb88320:v>>1;crc_business=v;end endfunction
always @(posedge clk)if(!rst)begin
 if(payload_valid && payload_ready)begin
  if(payload_sof!==(business_index==0) || payload_eof!==(business_index==offered_length[business_frames]-1) ||
     payload_data!==((offered_seed[business_frames]+business_index*7)&255))fail("business committed payload/SOF/EOF");
  business_bytes=business_bytes+1;
  if(payload_eof)begin business_frames=business_frames+1;business_index=0;end else business_index=business_index+1;
 end
 if(dut.m5_rx_b_l2_crc_error)business_crc_errors=business_crc_errors+1;
 if(dut.u_management.u_integration.u_m6d.snapshot_req_q && (data_a_tx_en||data_b_tx_en))saw_concurrent=1;
 #1;
 if(data_a_tx_en)begin
  if(!wire_previous)begin wire_index=0;wire_crc=32'hffffffff;end
  business_wire[wire_index]=data_a_txd;
  if(wire_index>=8)wire_crc=crc_business(wire_crc,data_a_txd);
  wire_index=wire_index+1;
 end else if(wire_previous)begin
  wire_n=offered_length[physical_a];
  if(wire_index!=(wire_n<=17?72:wire_n+55)||wire_crc!=32'hdebb20e3)fail("business GMII length/FCS");
  for(wire_k=0;wire_k<wire_n;wire_k=wire_k+1)
   if(business_wire[50+wire_k]!==((offered_seed[physical_a]+wire_k*7)&255))fail("business GMII payload bytes");
  physical_a=physical_a+1;
 end
 if(data_b_done)physical_b=physical_b+1;
 wire_previous=data_a_tx_en;
end

always @(posedge clk)begin
 if(payload_valid && payload_ready && payload_sof)begin
  rx_latency=$time-input_fcs_time;
  if(rx_latency>rx_latency_max)rx_latency_max=rx_latency;
  $display("REAL_RX input_FCS_to_first_payload_ns=%0d",rx_latency);
 end
 #1;if(data_a_done)input_fcs_time=$time;
end

task fail; input [511:0] reason; begin
errors=errors+1;
$display("FAIL case=%0d t=%0t frames=%0d commits=%0d rxstate=%0d txstate=%0d: %0s",case_id,$time,frames,commits,dut.u_management.u_rx.u_boundary.state,dut.u_management.u_integration.state,reason);
end endtask
task golden; input [31:0] destination; input [15:0] port; input [7:0] sequence_value;
integer k,b,sum; reg [31:0] crc; begin
for(k=0;k<128;k=k+1) expected[k]=0;
for(k=0;k<7;k=k+1) expected[k]=8'h55;
expected[7]=8'hd5; expected[8]=2; expected[13]=2; expected[14]=2; expected[19]=1;
expected_len=55+golden_ber_length;
expected[20]=8'h08; expected[22]=8'h45; expected[25]=28+golden_ber_length; expected[30]=64; expected[31]=17;
expected[34]=192; expected[35]=168; expected[36]=1; expected[37]=1;
for(k=0;k<4;k=k+1) expected[38+k]=destination[31-k*8 -:8];
expected[43]=161; expected[44]=port[15:8]; expected[45]=port[7:0]; expected[47]=8+golden_ber_length;
sum=0; for(k=22;k<42;k=k+2) sum=sum+{expected[k],expected[k+1]};
sum=(sum&65535)+(sum>>16); sum=(sum&65535)+(sum>>16); {expected[32],expected[33]}=~sum;
for(k=0;k<golden_ber_length;k=k+1) expected[50+k]=golden_ber[391-k*8 -:8];
expected[50+golden_ber_length]=sequence_value;
crc=32'hffffffff;
for(k=8;k<expected_len-4;k=k+1) for(b=0;b<8;b=b+1)
if(crc[0]^expected[k][b]) crc=(crc>>1)^32'hedb88320; else crc=crc>>1;
crc=~crc; for(k=0;k<4;k=k+1) expected[expected_len-4+k]=crc[k*8 +:8];
end endtask
task send_frame; input [367:0] message; input [31:0] source;
input [15:0] port,dport; input [7:0] sequence_value; input bad_crc;
integer k,b,sum,n; reg [31:0] crc; begin
n=(fault_mode==4)?97:46;
for(k=0;k<192;k=k+1) input_bytes[k]=0;
for(k=0;k<7;k=k+1) input_bytes[k]=8'h55;
input_bytes[7]=8'hd5; input_bytes[8]=3; input_bytes[13]=1; input_bytes[14]=2; input_bytes[19]=2;
input_bytes[20]=8'h08; input_bytes[22]=8'h45; input_bytes[25]=74;
input_bytes[30]=64; input_bytes[31]=17;
for(k=0;k<4;k=k+1) input_bytes[34+k]=source[31-k*8 -:8];
input_bytes[38]=192; input_bytes[39]=168; input_bytes[40]=1; input_bytes[41]=1;
{input_bytes[42],input_bytes[43]}=port; {input_bytes[44],input_bytes[45]}=dport; input_bytes[47]=54;
input_bytes[25]=28+n; input_bytes[47]=8+n;
if(fault_mode==1) input_bytes[13]=2;
if(fault_mode==2) input_bytes[41]=2;
if(fault_mode==3) input_bytes[31]=6;
sum=0; for(k=22;k<42;k=k+2) sum=sum+{input_bytes[k],input_bytes[k+1]};
sum=(sum&65535)+(sum>>16); sum=(sum&65535)+(sum>>16); {input_bytes[32],input_bytes[33]}=~sum;
for(k=0;k<46;k=k+1) input_bytes[50+k]=message[367-k*8 -:8];
input_bytes[50+n]=sequence_value;
if(udp_test_mode!=0)begin
 sum=17+8+n;
 for(k=34;k<42;k=k+2)sum=sum+{input_bytes[k],input_bytes[k+1]};
 for(k=42;k<50+n;k=k+2)sum=sum+{input_bytes[k],input_bytes[k+1]};
 sum=(sum&65535)+(sum>>16);sum=(sum&65535)+(sum>>16);sum=(~sum)&65535;
 if(sum==0)sum=65535;
 {input_bytes[48],input_bytes[49]}=sum;
 if(udp_test_mode==2)input_bytes[60]=input_bytes[60]^1; // good Ethernet CRC, bad UDP
end
crc=32'hffffffff;
for(k=8;k<51+n;k=k+1) for(b=0;b<8;b=b+1)
if(crc[0]^input_bytes[k][b]) crc=(crc>>1)^32'hedb88320; else crc=crc>>1;
crc=~crc; if(bad_crc) crc=crc^1;
for(k=0;k<4;k=k+1) input_bytes[51+n+k]=crc[k*8 +:8];
for(k=0;k<55+n;k=k+1) begin @(negedge clk); dv=1; rxd=input_bytes[k]; end
@(negedge clk); dv=0; rxd=0;
end endtask
always @(posedge clk) if(!rst) begin
cycles=cycles+1;
if(commit) commits=commits+1;
if(result_valid) results=results+1;
if(crc_error) crc_errors=crc_errors+1;
if(rd && re) begin rejects=rejects+1; if(error_code!=expected_error || rv) fail("decoder reject classification"); end
#1;
if(txer || underrun) fail("TX error");
if(txen) begin
if(!in_tx) begin
if(cycles-last_start<50000) fail("BAG start spacing");
last_start=cycles; idx=0; in_tx=1;
end
if(idx>=expected_len || txd!==expected[idx]) begin
$display("BYTE idx=%0d got=%02x expected=%02x",idx,txd,expected[idx]); fail("full GMII golden mismatch"); end
if(idx==93) returned_oid=txd;
if(txdone !== (idx==expected_len-1)) fail("last FCS done alignment");
idx=idx+1;
end else if(in_tx) begin
if(idx!=expected_len) fail("length/continuous tx_en"); in_tx=0;
end
if(txdone) frames=frames+1;
end
task settle; input integer target_frames,target_commits,target_rejects;
integer k; begin
for(k=0;k<60000 && (frames!=target_frames || busy || boundary_busy);k=k+1) @(negedge clk);
repeat(250) @(negedge clk);
if(frames!=target_frames || commits!=target_commits || rejects!=target_rejects || busy || boundary_busy) fail("settle/counts");
$display("CASE_DONE id=%0d errors=%0d frames=%0d commits=%0d rejects=%0d crc=%0d",case_id,errors,frames,commits,rejects,crc_errors);
end endtask
task business_send;input integer n,seed;integer k,t;begin
 offered_length[offered]=n;offered_seed[offered]=seed;offered=offered+1;
 for(k=0;k<n;k=k+1)begin
  @(negedge clk);app_wr_en=1;app_wr_data=(seed+k*7)&255;app_length=n;app_sof=k==0;app_eof=k==n-1;
  #1;t=0;while(!app_ready&&t<10000)begin @(negedge clk);t=t+1;end
  if(!app_ready)fail("business ingress timeout");
 end
 @(negedge clk);app_wr_en=0;app_sof=0;app_eof=0;
end endtask
task business_drain;input integer count;integer t;begin
 t=0;while((business_frames!=count||dut.m5_tx_core_busy||dut.m5_rx_payload_frame_active)&&t<10000)begin @(negedge clk);t=t+1;end
 repeat(500)@(negedge clk);
 if(business_frames!=count)fail("missing business commit");
end endtask
task management_query;input integer oid,value;integer n,k,oldframes,oldcommits;begin
 oldframes=frames;oldcommits=commits;
 request_bytes=GET;request_bytes[367-43*8-:8]=oid;
 n=value>32767?3:(value>127?2:1);golden_ber=0;golden_ber_length=46+n;
 for(k=0;k<44;k=k+1)golden_ber[391-k*8-:8]=GET[367-k*8-:8];
 golden_ber[391-1*8-:8]=golden_ber_length-2;golden_ber[391-13*8-:8]=8'ha2;
 golden_ber[391-14*8-:8]=golden_ber_length-15;golden_ber[391-28*8-:8]=17+n;
 golden_ber[391-30*8-:8]=15+n;golden_ber[391-43*8-:8]=oid;
 golden_ber[391-44*8-:8]=(oid==1||oid==4||oid==5)?2:65;
 golden_ber[391-45*8-:8]=n;
 for(k=0;k<n;k=k+1)golden_ber[391-(46+k)*8-:8]=value>>((n-k-1)*8);
 golden(32'hc0a80173,40009,frames);
 send_frame(request_bytes,32'hc0a80173,40009,161,management_rx_seq,0);
 management_rx_seq=management_rx_seq+1;
 settle(oldframes+1,oldcommits+1,0);
end endtask
initial begin
repeat(5)@(negedge clk);rst=0;case_id=60;loopback=1;tx_enable=1;
@(negedge clk);cfg_we=1;cfg_vl_id=0;cfg_bag=12500;cfg_destination=2;
@(negedge clk);cfg_we=0;
fork
 begin business_send(512,10);business_drain(1);end
 begin repeat(500)@(negedge clk);management_query(1,32'h060a01);end
join
management_query(6,1);
business_send(512,20);business_drain(2);management_query(6,2);
if(physical_a!=2 || physical_b!=2 || business_frames!=2 || business_bytes!=1024 || !saw_concurrent || rx_latency_max>150000)
 fail("real joint metrics");
$display("REAL_JOINT clock_hz=12500000 business_frames=%0d management_frames=%0d bytes=%0d max_RX_processing_ns=%0d ERRORS=%0d",business_frames,frames,business_bytes,rx_latency_max,errors);
if(errors==0)$display("M6F_REAL_JOINT_REPAIR_PASS");else $display("M6F_REAL_JOINT_REPAIR_FAIL");$finish;
end
initial begin #18000000;$display("M6F_REAL_JOINT_TIMEOUT");$finish;end
endmodule
