`timescale 1ns/1ps
module tb_snmp_multi_varbind;
localparam MAX_MSG_BYTES=128, MAX_VB_BYTES=64, MAX_RESPONSE_BYTES=96;
reg clk=0; always #5 clk=~clk;
reg rst_n=0,req=0,fault=0,net_a=0;
reg [31:0] rx_count=0,tx_count=0;
reg [7:0] msg_length=0;
reg [1023:0] msg_bytes=0;
wire response_done,response_valid,response_error;
wire [7:0] response_error_code,response_length;
wire [767:0] response_bytes;
integer errors=0,cases=0,cycles=0,snaps=0,acks=0,txns=0,snap_tick=0;
reg previous_req=0,previous_ack=0;
always @(posedge clk) if(rst_n) begin
    if(dut.snapshot_req_q) begin
        snaps=snaps+1; snap_tick=cycles/10;
        if(previous_req) fail("snapshot request longer than one cycle");
    end
    if(dut.m6b_snapshot_ack) begin
        acks=acks+1;
        if(previous_ack || acks!=snaps) fail("unsolicited/repeated snapshot acknowledgement");
    end
    if(dut.transaction_req) begin
        txns=txns+1;
        if(acks!=snaps) fail("transaction before matching snapshot acknowledgement");
    end
    previous_req=dut.snapshot_req_q;previous_ack=dut.m6b_snapshot_ack;cycles=cycles+1;
end
    afdx_m6d_integration #(
        .MAX_MSG_BYTES(MAX_MSG_BYTES), .MAX_VB_BYTES(MAX_VB_BYTES),
        .MAX_RESPONSE_BYTES(MAX_RESPONSE_BYTES), .CLK_HZ(1000)
    ) dut (
        .clk(clk), .rst_n(rst_n), .req(req), .msg_length(msg_length), .msg_bytes(msg_bytes),
        .response_done(response_done), .response_valid(response_valid),
        .response_error(response_error), .response_error_code(response_error_code),
        .response_length(response_length), .response_bytes(response_bytes),
        .m5_network_a_enable(net_a), .m5_network_b_enable(1'b0), .m5_degraded_mode(1'b0),
        .m5_redundancy_ok(1'b0), .m5_frame_count_match(1'b0),
        .m5_active_byte_count_match(1'b0), .m5_fault_applied_event(fault),
        .m5_rx_accepted_count(rx_count), .m5_rx_accepted_a_count(32'd0),
        .m5_rx_accepted_b_count(32'd0), .m5_rx_duplicate_count(32'd0),
        .m5_rx_cross_network_duplicate_count(32'd0), .m5_rx_same_network_repeat_count(32'd0),
        .m5_rx_stale_count(32'd0), .m5_rx_sequence_gap_count(32'd0),
        .m5_tx_a_frame_count(tx_count), .m5_tx_b_frame_count(32'd0),
        .m5_tx_a_active_byte_count(32'd0), .m5_tx_b_active_byte_count(32'd0),
        .m5_tx_byte_mismatch_count(32'd0), .m5_tx_frame_skew_cycle_count(32'd0),
        .m5_tx_frame_done_skew_count(32'd0), .m5_tx_er_mismatch_count(32'd0),
        .m5_tx_a_error_cycle_count(32'd0), .m5_tx_b_error_cycle_count(32'd0),
        .m5_tx_a_underrun_count(32'd0), .m5_tx_b_underrun_count(32'd0)
    );


function [7:0] rb; input integer n; begin rb=response_bytes[767-n*8 -:8]; end endfunction
function integer minlen; input [31:0] v; reg [31:0] w; integer n; begin
 w=v; n=4;
 while(n>1 && ((w[31:24]==0 && !w[23]) || (w[31:24]==255 && w[23]))) begin w=w<<8;n=n-1;end
 minlen=n;
end endfunction
task fail;input [639:0] why;begin errors=errors+1;$display("FAIL case=%0d %0s",cases,why);end endtask
task put;input integer n;input [7:0] v;begin msg_bytes[n*8+:8]=v;end endtask
task build;input [31:0] rid;input [7:0] oid;input op;input root_oid;
 integer n,t,j,ol;reg [79:0] prefix; begin
 msg_bytes=0;n=minlen(rid);t=17+n;ol=root_oid?10:11;msg_length=t+14+ol;
 put(0,48);put(1,msg_length-2);put(2,2);put(3,1);put(4,1);put(5,4);put(6,6);
 put(7,"p");put(8,"u");put(9,"b");put(10,"l");put(11,"i");put(12,"c");
 put(13,op?8'ha1:8'ha0);put(14,msg_length-15);put(15,2);put(16,n);
 for(j=0;j<n;j=j+1) put(17+j,rid>>((n-j-1)*8));
 put(t,2);put(t+1,1);put(t+2,0);put(t+3,2);put(t+4,1);put(t+5,0);
 put(t+6,48);put(t+7,ol+6);put(t+8,48);put(t+9,ol+4);put(t+10,6);put(t+11,ol);
 prefix=80'h2b0601040181fd590101;
 for(j=0;j<10;j=j+1) put(t+12+j,prefix[79-j*8-:8]);
 if(!root_oid) put(t+22,oid);
 put(t+12+ol,5);put(t+13+ol,0);
 end endtask
task send;integer wait_cycles;begin
 @(negedge clk);req=1;@(negedge clk);req=0;
 wait_cycles=0;
 while(!response_done && wait_cycles<200) begin @(posedge clk);#1;wait_cycles=wait_cycles+1;end
 if(!response_done) fail("bounded response timeout");
 end endtask
task check_response;input [31:0] rid;input [7:0] oid;input [7:0] tag;input [31:0] value;
 integer n,t,j,vl;reg [31:0] decoded;begin
 n=minlen(rid);t=17+n;
 if(!response_done || !response_valid || response_error || response_error_code!=0) fail("response control");
 if(rb(0)!=48 || rb(1)+2!=response_length || rb(13)!=8'ha2 || rb(14)+15!=response_length) fail("outer/PDU length");
 if(rb(15)!=2 || rb(16)!=n) fail("request-id not minimal signed BER");
 for(j=0;j<n;j=j+1) if(rb(17+j)!==((rid>>((n-j-1)*8)) & 255)) fail("request-id content/sign");
 if(rb(t)!=2 || rb(t+1)!=1 || rb(t+2)!=0 || rb(t+3)!=2 || rb(t+4)!=1 || rb(t+5)!=0) fail("status/index");
 if(rb(t+6)!=48 || rb(t+7)+t+8!=response_length || rb(t+8)!=48 || rb(t+9)+t+10!=response_length) fail("VarBind boundaries");
 if(rb(t+10)!=6 || rb(t+11)!=11 || rb(t+22)!=oid) fail("OID");
 vl=rb(t+24);decoded=0;
 if(rb(t+23)!=tag || t+25+vl!=response_length || vl<1 || vl>5) fail("value boundary/type");
 for(j=0;j<vl;j=j+1) decoded=(decoded<<8)|rb(t+25+j);
 if(decoded!==value) begin $display("value got=%08h expected=%08h",decoded,value);fail("snapshot value");end
 for(j=response_length;j<96;j=j+1) if(rb(j)!==0) fail("stale trailing response data");
 @(posedge clk);#1;if(response_done) fail("response done must pulse");
 end endtask
task query;input [31:0] rid;input [7:0] oid;input [7:0] tag;input [31:0] value;begin
 cases=cases+1;build(rid,oid,0,0);send;check_response(rid,oid,tag,value);
 end endtask
integer p,t,x,base_len,before_snaps;reg [31:0] snap_rx;
task double_request;input [7:0] oid1,oid2;input op;begin
 build(1,oid1,op,0);base_len=msg_length;t=18;
 for(x=0;x<17;x=x+1)put(base_len+x,msg_bytes[(t+8+x)*8+:8]);
 put(base_len+14,oid2);msg_length=base_len+17;
 put(1,msg_length-2);put(14,msg_length-15);put(t+7,34);
end endtask
task check_vb;inout integer pos;input [7:0] oid,tag;input [31:0] value;
 integer j,l,e;reg [31:0] val;begin
 e=pos+2+rb(pos+1);
 if(rb(pos)!=48||rb(pos+2)!=6||rb(pos+3)!=11||rb(pos+14)!=oid||rb(pos+15)!=tag)fail("multi VarBind structure/OID");
 l=rb(pos+16);val=0;for(j=0;j<l;j=j+1)val=(val<<8)|rb(pos+17+j);
 if(val!==value||e!=pos+17+l)fail("multi VarBind value/length");
 if(tag>=128 && l!=0)fail("exception must be zero length");
 pos=e;
end endtask
task envelope;begin
 if(!response_valid||response_error||rb(16)!=1||rb(17)!=1||rb(1)+2!=response_length||rb(14)+15!=response_length||rb(25)+26!=response_length)fail("multi PDU envelope");
 p=26;
end endtask
initial begin
 repeat(4)@(negedge clk);rst_n=1;rx_count=100;tx_count=200;
 cases=1;double_request(6,14,0);before_snaps=snaps;
 fork
  begin send;envelope;check_vb(p,6,65,100);check_vb(p,14,65,200);end
  begin wait(dut.snapshot_req_q);@(posedge clk);@(negedge clk);rx_count=101;tx_count=201;end
 join
 if(p!=response_length||snaps!=before_snaps+1||txns!=2)fail("multi PDU atomic snapshot/cardinality");
 cases=2;double_request(6,14,0);send;envelope;check_vb(p,6,65,101);check_vb(p,14,65,201);
 cases=3;double_request(1,26,0);send;envelope;check_vb(p,1,2,32'h060a01);check_vb(p,26,128,0);
 cases=4;double_request(24,25,1);send;envelope;check_vb(p,25,65,0);check_vb(p,25,130,0);
 // Enterprise root (OID content length 8), not a fabricated leaf .0.
 cases=5;build(1,0,1,1);msg_length=40;put(1,38);put(14,25);put(25,14);put(27,12);put(29,8);put(38,5);put(39,0);
 send;check_response(1,1,2,32'h060a01);
 cases=6;double_request(1,2,0);put(27,127);before_snaps=snaps;send;
 if(response_valid||!response_error||snaps!=before_snaps)fail("malformed inner length must not query");
 cases=7;double_request(1,2,0);base_len=msg_length;
 for(x=0;x<17;x=x+1)put(base_len+x,msg_bytes[(26+x)*8+:8]);
 msg_length=base_len+17;put(1,msg_length-2);put(14,msg_length-15);put(25,51);send;
 if(response_valid||!response_error)fail("unsupported third VarBind must fail closed");
 $display("SNMP_MULTI_CASES=%0d ERRORS=%0d",cases,errors);
 if(errors==0)$display("SNMP_MULTI_REPAIR_PASS");else $display("SNMP_MULTI_REPAIR_FAIL");$finish;
end
initial begin #200000;$display("SNMP_MULTI_TIMEOUT");$finish;end
endmodule
