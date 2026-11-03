`timescale 1ns/1ps
module tb_contest_rtc_timebase;
reg clk=0;always #5 clk=~clk;reg rst=1;wire [63:0] utc,mono;integer errors=0,i;reg [63:0] expected;
afdx_rtc_ntp #(.CLK_HZ(3)) dut(.clk(clk),.rst(rst),.poll(1'b0),.server_ip(32'd0),.tx_valid(),.tx_ready(1'b1),.tx_bytes(),
.rx_valid(1'b0),.rx_source_ip(32'd0),.rx_source_port(16'd0),.rx_length(8'd0),.rx_bytes(384'd0),.utc_ntp(utc),.monotonic_ticks(mono),
.synchronized(),.sync_event(),.reject_event(),.timeout_event(),.last_offset(),.last_delay(),.sync_count(),.reject_count(),.timeout_count(),.busy());
initial begin repeat(3)@(negedge clk);rst=0;
for(i=1;i<=300;i=i+1)begin @(negedge clk);expected=64'h100000000+(64'h100000000*i)/3;
if(utc!==expected||mono!==i)begin errors=errors+1;$display("FAIL fraction cycle=%0d utc=%h expected=%h",i,utc,expected);end end
if(errors==0)$display("TB_CONTEST_RTC_TIMEBASE_PASS");else $display("TB_CONTEST_RTC_TIMEBASE_FAIL");$finish;end
endmodule
