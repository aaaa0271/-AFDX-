`timescale 1ns/1ps
module tb_contest_rtc_ntp;
reg clk=0;always #5 clk=~clk;reg rst=1,poll=0,ready=1,rx=0;
reg [31:0] ip=32'h0a000064,rip=32'h0a000064;reg [15:0] port=123;reg [7:0] len=48;reg [383:0] rb=0;
wire tv,locked,se,re,te,busy;wire [383:0] tb;wire [63:0] utc,mono,delay;wire signed [63:0] off;
wire [31:0] sc,rc,tc;integer errors=0,cases=0,i;reg [63:0] last_mono=0,origin,baseline,expect_time;
reg signed [63:0] desired;
localparam [63:0] STEP=64'h0000000000400000; // clock1024Hz => exact 1/1024 second
// Clock is accelerated but all reference values are independent integer NTP units.
afdx_rtc_ntp #(.CLK_HZ(1024),.RESPONSE_TIMEOUT(32),.HOLDOVER_CYCLES(128)) dut(
.clk(clk),.rst(rst),.poll(poll),.server_ip(ip),.tx_valid(tv),.tx_ready(ready),.tx_bytes(tb),
.rx_valid(rx),.rx_source_ip(rip),.rx_source_port(port),.rx_length(len),.rx_bytes(rb),.utc_ntp(utc),.monotonic_ticks(mono),
.synchronized(locked),.sync_event(se),.reject_event(re),.timeout_event(te),.last_offset(off),.last_delay(delay),.sync_count(sc),.reject_count(rc),.timeout_count(tc),.busy(busy));
task fail;input [511:0] why;begin errors=errors+1;$display("FAIL RTC case=%0d %0s",cases,why);end endtask
always @(negedge clk)if(!rst)begin if(mono<last_mono)fail("monotonic time moved backwards");last_mono=mono;end
function [63:0] stamp;input [383:0] p;input integer n;integer j;reg [63:0] x;begin x=0;for(j=0;j<8;j=j+1)x={x[55:0],p[(n+j)*8+:8]};stamp=x;end endfunction
task puttime;input integer n;input [63:0] value;integer j;begin for(j=0;j<8;j=j+1)rb[(n+j)*8+:8]=value[63-j*8-:8];end endtask
task request;begin
 @(negedge clk);poll=1;@(negedge clk);poll=0;
 if(!tv||tb[7:0]!=8'h23)fail("NTP client request");origin=stamp(tb,40);
 @(negedge clk);repeat(9)@(negedge clk);
end endtask
task response;input signed [63:0] delta;input integer bad;
 reg [63:0] midpoint;begin
 cases=cases+1;rb=0;rb[7:0]=8'h24;rb[15:8]=1;
 // Sample current DUT time only as T4 probe; oracle arithmetic is independently
 // constructed from known T1 and the elapsed integral STEP clock count.
 midpoint=origin+6*STEP+delta;
 puttime(24,origin);puttime(32,midpoint);puttime(40,midpoint);
 if(bad==1)rb[24*8+:8]=rb[24*8+:8]^1;
 if(bad==2)rb[15:8]=0;
 if(bad==3)rb[7:0]=8'he4;
 if(bad==4)rip=32'h0a000065;
 if(bad==5)port=124;
 if(bad==6)len=47;
 expect_time=utc;
 // Origin is an echoed token; this datagram test accepts TX one tick later.
 desired=($signed(midpoint-(origin+STEP))+$signed(midpoint-utc))>>>1;
 rx=1;@(posedge clk);#1;
 if(bad==0)begin
  if(!se||!locked||off!==desired||utc!==(expect_time+desired+STEP))fail("four timestamp correction");
 end else if(!re||se||utc!==expect_time+STEP)fail("invalid response changed RTC");
 @(negedge clk);rx=0;rip=ip;port=123;len=48;
end endtask
initial begin
 repeat(4)@(negedge clk);rst=0;repeat(5)@(negedge clk);
 request;response(64'h0000000200000000,0);
 request;response(-64'sh0000000100000000,0);
 for(i=1;i<=6;i=i+1)begin request;response(0,i);repeat(40)@(negedge clk);end
 request;repeat(40)@(negedge clk);if(tc!=7)fail("missing request timeout");
 // Drift/offset changes in successive server replies remain correctable.
 for(i=0;i<12;i=i+1)begin request;response(i*10000,0);end
 repeat(140)@(negedge clk);if(locked)fail("holdover expiry");
 request;response(0,0);if(!locked)fail("reacquisition");
 $display("RTC_SYNCS=%0d REJECTS=%0d TIMEOUTS=%0d ERRORS=%0d",sc,rc,tc,errors);
 if(errors==0)$display("TB_CONTEST_RTC_NTP_PASS");else $display("TB_CONTEST_RTC_NTP_FAIL");$finish;
end
initial begin #100000;$display("RTC_TIMEOUT");$finish;end
endmodule
