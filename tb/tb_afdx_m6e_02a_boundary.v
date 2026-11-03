`timescale 1ns/1ps
module tb_afdx_m6e_02a_boundary;
reg clk=0; always #5 clk=~clk;
reg rst=1, meta_valid=0, payload_valid=0, payload_sof=0, payload_eof=0;
reg rx_result_valid=0, rx_accept=0, rx_reject=0, ready=1;
reg [31:0] src_ip=0;
reg [15:0] udp_src_port=0, udp_dst_port=161;
reg [10:0] payload_length=0;
reg [7:0] payload_data=0;
wire payload_ready, mo, vo, so, eo, done, valid, busy;
wire [31:0] ip;
wire [15:0] sp, dp;
wire [10:0] len;
wire [7:0] data;
wire commit;
wire [767:0] message;
wire [10:0] message_length;
wire [31:0] requester;
wire [15:0] port;
integer errors=0, commits=0, bytes=0, case_id=0, baseline=0;
integer expected_len=0, expected_base=0;
reg [31:0] expected_ip;
reg [15:0] expected_port;
reg meta_seen=0, stalled=0;
reg [9:0] stalled_data;
afdx_m6e_02a_boundary dut (
.clk(clk),.rst(rst),.src_ip(src_ip),.udp_src_port(udp_src_port),.udp_dst_port(udp_dst_port),
.payload_length(payload_length),.meta_valid(meta_valid),.payload_data(payload_data),
.payload_valid(payload_valid),.payload_ready(payload_ready),.payload_sof(payload_sof),.payload_eof(payload_eof),
.rx_result_valid(rx_result_valid),.rx_accept(rx_accept),.rx_reject(rx_reject),
.meta_valid_out(mo),.src_ip_out(ip),.udp_src_port_out(sp),.udp_dst_port_out(dp),.payload_length_out(len),
.payload_data_out(data),.payload_valid_out(vo),.payload_ready_out(ready),.payload_sof_out(so),.payload_eof_out(eo),
.frame_done(done),.frame_valid(valid),.busy(busy));
// Gate valid at the real 01A sink to model an intervening ready/valid stall.
afdx_m6e_udp_rx_buffer sink (
.clk(clk),.rst(rst),.m6e_busy(1'b0),.meta_valid(mo),.src_ip(ip),.udp_src_port(sp),.udp_dst_port(dp),
.payload_length(len),.payload_data(data),.payload_valid(vo && ready),.payload_ready(),
.payload_sof(so),.payload_eof(eo),.frame_done(done),.frame_valid(valid),.rx_commit(commit),
.active_msg_bytes(message),.active_msg_length(message_length),.active_requester_ip(requester),.active_requester_port(port));
task fail; input [511:0] reason; begin
errors=errors+1;
$display("FAIL case=%0d t=%0t state=%0d drop=%b bytes=%0d commits=%0d: %0s",case_id,$time,dut.state,dut.dropping,bytes,commits,reason);
end endtask
integer k;
always @(posedge clk) if (!rst) begin
    if (mo) begin meta_seen=1; bytes=0; if(vo) fail("payload on metadata edge"); end
    if (stalled && {data,so,eo} !== stalled_data) fail("unstable stalled output");
    stalled=vo && !ready; stalled_data={data,so,eo};
    if(vo && ready) begin
        if(!meta_seen) fail("payload before metadata");
        if(data !== ((expected_base+bytes)&255)) fail("replay data");
        if(so !== (bytes==0) || eo !== (bytes==expected_len-1)) fail("replay markers");
        bytes=bytes+1;
    end
    if(done) begin
        if(!valid || bytes!=expected_len) fail("done/valid/count contract");
        meta_seen=0;
    end
    if(commit) begin
        commits=commits+1;
        if(requester!==expected_ip || port!==expected_port || message_length!=expected_len) fail("01A requester/length");
        for(k=0;k<expected_len;k=k+1)
            if(message[k*8 +: 8] !== ((expected_base+k)&255)) fail("01A committed byte");
    end
end
task metadata; input integer n; input integer id; begin
    @(negedge clk); meta_valid=1; payload_length=n; src_ip=32'h0a000000+id; udp_src_port=40000+id;
    @(negedge clk); meta_valid=0;
end endtask
task result; input integer accept_value; begin
    @(negedge clk); rx_result_valid=1; rx_accept=accept_value; rx_reject=!accept_value;
    @(negedge clk); rx_result_valid=0; rx_accept=0; rx_reject=0;
end endtask
task payload; input integer n; input integer base; integer j; begin
    for(j=0;j<n;j=j+1) begin
        @(negedge clk); payload_valid=1; payload_data=base+j; payload_sof=j==0; payload_eof=j==n-1;
        while(!payload_ready) @(negedge clk);
    end
    @(negedge clk); payload_valid=0; payload_sof=0; payload_eof=0;
end endtask
task settle; input integer delta; integer j; begin
    for(j=0;j<300 && (busy || commits!=baseline+delta);j=j+1) @(negedge clk);
    repeat(4) @(negedge clk);
    if(busy || commits!=baseline+delta) fail("release/commit timeout");
    $display("CASE_DONE id=%0d errors=%0d commits=%0d",case_id,errors,commits);
end endtask
task expect_frame; input integer n; input integer id; input integer base; begin
    baseline=commits; expected_len=n; expected_ip=32'h0a000000+id; expected_port=40000+id; expected_base=base;
end endtask
initial begin #490000; $display("M6E_02A_TIMEOUT case=%0d state=%0d drop=%b commits=%0d",case_id,dut.state,dut.dropping,commits); $finish; end

initial begin
repeat(4) @(negedge clk); rst=0;
case_id=1; expect_frame(46,1,128); metadata(46,1); result(1); payload(46,128); settle(1);
case_id=2; expect_frame(4,2,32); ready=0; metadata(4,2); payload(4,32); result(1);
repeat(20) @(negedge clk); ready=1; settle(1);
case_id=3; baseline=commits; metadata(4,3); result(0); settle(0);
case_id=4; baseline=commits; metadata(0,4); result(1); settle(0);
case_id=5; baseline=commits; metadata(100,5); result(1); payload(100,64); settle(0);
case_id=6; baseline=commits; udp_dst_port=162; metadata(4,6); payload(4,80); result(1); settle(0); udp_dst_port=161;
case_id=7; expect_frame(3,7,160); metadata(3,7); payload(3,160); result(1); settle(1);
case_id=8; expect_frame(3,8,176); metadata(3,8); result(1); payload(3,176); settle(1);
// A second metadata pulse during stalled replay must remain drain-only even
// when its payload/result arrive after the owned replay has completed.
case_id=9; expect_frame(3,9,192); ready=0; metadata(3,9); payload(3,192); result(1);
repeat(6) @(negedge clk); metadata(4,99); ready=1;
repeat(12) @(negedge clk); result(1); payload(4,16); settle(1);
case_id=10; expect_frame(1,10,208); metadata(1,10); payload(1,208); result(1); settle(1);
case_id=11; expect_frame(2,11,224);
@(negedge clk); meta_valid=1; payload_length=2; src_ip=32'h0a00000b; udp_src_port=40011;
rx_result_valid=1; rx_accept=1;
@(negedge clk); meta_valid=0; rx_result_valid=0; rx_accept=0;
payload(2,224); settle(1);
case_id=12; baseline=commits;
@(negedge clk); meta_valid=1; payload_length=2; rx_result_valid=1; rx_reject=1;
@(negedge clk); meta_valid=0; rx_result_valid=0; rx_reject=0;
// Earliest new metadata after the rejected capture returns to IDLE.
@(negedge clk);
case_id=13; expect_frame(2,13,240); metadata(2,13); payload(2,240); result(1); settle(1);
case_id=14; expect_frame(2,14,16); ready=0; metadata(2,14); payload(2,16); result(1);
repeat(6) @(negedge clk);
@(negedge clk); meta_valid=1; payload_length=2; rx_result_valid=1; rx_reject=1;
@(negedge clk); meta_valid=0; rx_result_valid=0; rx_reject=0; ready=1;
settle(1);
case_id=15; expect_frame(1,15,48); metadata(1,15); payload(1,48); result(1); settle(1);
$display("M6E_02A_FAILS=%0d commits=%0d",errors,commits);
if(errors==0 && commits==10) $display("M6E_02A_TB_PASS"); else $display("M6E_02A_TB_FAIL");
$finish;
end
endmodule
