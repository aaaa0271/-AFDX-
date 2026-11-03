`timescale 1ns/1ps
module tb_afdx_m6f_system_top;
reg clk=0; always #4 clk=~clk;
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
afdx_m6f_system_top #(.CLK_HZ(1000),.MANAGEMENT_BAG_CYCLES(1200)) dut (
 .mib_live(),
    .rx_cfg_table(672'd0),
 .clk(clk),.rst(rst),.tx_enable(tx_enable),.network_a_enable(network_a_enable),.network_b_enable(network_b_enable),
 .cfg_we(cfg_we),.cfg_vl_id(cfg_vl_id),.cfg_bag(cfg_bag),.cfg_destination(cfg_destination),
 .app_wr_len(16'd4),.app_wr_sof(1'b0),.app_wr_eof(1'b0),.cfg_lmax(16'd1518),.app_wr_ready(),.app_len_error(),
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
integer idx=0, case_id=0, cycles=0, last_start=-10000, expected_len=104, expected_error=0;
reg in_tx=0;
integer j, walk_id;
integer fault_mode=0;
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
if(cycles-last_start<1200) fail("BAG start spacing");
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
for(k=0;k<4000 && (frames!=target_frames || busy || boundary_busy);k=k+1) @(negedge clk);
repeat(250) @(negedge clk);
if(frames!=target_frames || commits!=target_commits || rejects!=target_rejects || busy || boundary_busy) fail("settle/counts");
$display("CASE_DONE id=%0d errors=%0d frames=%0d commits=%0d rejects=%0d crc=%0d",case_id,errors,frames,commits,rejects,crc_errors);
end endtask
initial begin
repeat(5) @(negedge clk); rst=0;
case_id=1; golden(32'hc0a80164,40000,0); send_frame(GET,32'hc0a80164,40000,161,0,0); settle(1,1,0);
case_id=2; send_frame(GET,32'hc0a80199,40999,161,1,1); settle(1,1,0); if(crc_errors!=1) fail("missing CRC rejection");
case_id=3; send_frame(GET,32'hc0a80199,40999,162,1,0); settle(1,1,0);
case_id=4; request_bytes=GET; request_bytes[367-7*8 -:8]=8'h78; expected_error=2;
send_frame(request_bytes,32'hc0a80166,40002,161,1,0); settle(1,2,1);
case_id=5; request_bytes=GET; request_bytes[367-13*8 -:8]=8'ha3; expected_error=4;
send_frame(request_bytes,32'hc0a80166,40002,161,2,0); settle(1,3,2);
case_id=6; request_bytes=GET; request_bytes[367-1*8 -:8]=8'h2b; expected_error=1;
send_frame(request_bytes,32'hc0a80166,40002,161,3,0); settle(1,4,3);
case_id=7; golden(32'hc0a80165,40001,1); send_frame(GET,32'hc0a80165,40001,161,4,0); settle(2,5,3);
case_id=8; send_frame(GET,32'hc0a80165,40001,161,4,0); settle(2,5,3);
if(seq!=2) fail("TX sequence advanced on reject");
case_id=9; request_bytes=GET; request_bytes[367-13*8 -:8]=8'ha1;
request_bytes[367-43*8 -:8]=0; golden(32'hc0a80167,40003,2);
send_frame(request_bytes,32'hc0a80167,40003,161,5,0); settle(3,6,3);
case_id=10; request_bytes[367-43*8 -:8]=25;
golden_ber={END_RESP,24'd0}; golden_ber_length=46; golden(32'hc0a80168,40004,3);
send_frame(request_bytes,32'hc0a80168,40004,161,6,0); settle(4,7,3);
case_id=11; golden_ber=RESP; golden_ber_length=49; golden(32'hc0a80169,40005,4);
send_frame(GET,32'hc0a80169,40005,161,7,0);
for(j=0;j<500 && !busy;j=j+1) @(negedge clk);
if(!busy) fail("busy-drop not exercised");
send_frame(GET,32'hc0a80199,40999,161,8,0); settle(5,8,3);
case_id=12; golden(32'hc0a80170,40006,5);
send_frame(GET,32'hc0a80170,40006,161,8,0); settle(6,9,3);
request_bytes=GET; request_bytes[367-13*8 -:8]=8'ha1;
request_bytes[367-43*8 -:8]=0;
for(walk_id=1;walk_id<=26;walk_id=walk_id+1) begin
case_id=12+walk_id;
if(walk_id==1) begin golden_ber=RESP; golden_ber_length=49; end
else if(walk_id==26) begin golden_ber={END_RESP,24'd0}; golden_ber_length=46; end
else begin
    golden_ber={GET,24'd0}; golden_ber_length=47;
    golden_ber[391-1*8 -:8]=45;
    golden_ber[391-13*8 -:8]=8'ha2;
    golden_ber[391-14*8 -:8]=32;
    golden_ber[391-28*8 -:8]=18;
    golden_ber[391-30*8 -:8]=16;
    golden_ber[391-43*8 -:8]=walk_id;
    walk_type=8'h41; if(walk_id==3) walk_type=8'h43;
    if(walk_id==4 || walk_id==5) walk_type=8'h02;
    walk_value=0; if(walk_id==2) walk_value=1; if(walk_id==4) walk_value=8'h3b;
    golden_ber[391-44*8 -:8]=walk_type;
    golden_ber[391-45*8 -:8]=1;
    golden_ber[391-46*8 -:8]=walk_value;
end
golden(32'hc0a80171,40007,5+walk_id);
send_frame(request_bytes,32'hc0a80171,40007,161,8+walk_id,0);
settle(6+walk_id,9+walk_id,3);
if(returned_oid != (walk_id==26 ? 25 : walk_id)) fail("walk OID progression");
request_bytes[367-43*8 -:8]=returned_oid;
end
for(j=1;j<=4;j=j+1) begin
case_id=37+2*j; fault_mode=j;
send_frame(GET,32'hc0a80172,40008,161,34+j,0); settle(31+j,34+j,3);
case_id=38+2*j; fault_mode=0; golden_ber=RESP; golden_ber_length=49;
golden(32'hc0a80172,40008,31+j);
send_frame(GET,32'hc0a80172,40008,161,34+j,0); settle(32+j,35+j,3);
end
$display("M6E_GMII_ERRORS=%0d frames=%0d commits=%0d rejects=%0d",errors,frames,commits,rejects);
if(errors==0) $display("M6E_GMII_SMOKE_PASS"); else $display("M6E_GMII_SMOKE_FAIL");
$finish;
end
initial begin #490000; $display("M6E_GMII_TIMEOUT case=%0d frames=%0d commits=%0d state=%0d parser_meta=%b parser_done=%b",case_id,frames,commits,dut.u_management.u_rx.u_boundary.state,dut.u_management.u_rx.parser_meta,dut.u_management.u_rx.parser_done); $finish; end
endmodule

