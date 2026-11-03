`timescale 1ns/1ps
// Independent reference clock; no expected timestamp is read from the DUT.
module tb_contest_rtc_convergence;
localparam integer HZ=100000;localparam [63:0] SECOND=64'h100000000;
reg clk=0;always #5 clk=~clk;reg rst=1,poll=0,rx=0;reg [383:0] response=0;
wire tv,locked,se;wire [383:0] request;wire [63:0] utc,mono;integer errors=0,cycle=0,i,j;
reg [63:0] reference=0,t1,t2,t3,difference,max_error=0;
reg signed [63:0] bias=64'sh0000000500000000;integer drift_ppm=20;
afdx_rtc_ntp #(.CLK_HZ(HZ),.RESPONSE_TIMEOUT(100),.HOLDOVER_CYCLES(500)) dut(
.clk(clk),.rst(rst),.poll(poll),.server_ip(32'h0a000001),.tx_valid(tv),.tx_ready(1'b1),.tx_bytes(request),
.rx_valid(rx),.rx_source_ip(32'h0a000001),.rx_source_port(16'd123),.rx_length(8'd48),.rx_bytes(response),
.utc_ntp(utc),.monotonic_ticks(mono),.synchronized(locked),.sync_event(se),.reject_event(),.timeout_event(),.last_offset(),.last_delay(),.sync_count(),.reject_count(),.timeout_count(),.busy());
always @(posedge clk)begin
 if(rst)cycle=0;
 else cycle=cycle+1;
 // Distinct reference with a controllable frequency error, represented without
 // using any DUT state. Integer remainder is recomputed from absolute cycles.
 reference=bias+(SECOND*cycle)/HZ+((SECOND*cycle)/HZ*drift_ppm)/1000000;
end
task fail;input [511:0] s;begin errors=errors+1;$display("FAIL CLOCK_REF %0s",s);end endtask
task stamp;input integer n;input [63:0] value;integer k;begin for(k=0;k<8;k=k+1)response[(n+k)*8+:8]=value[63-k*8-:8];end endtask
task synchronize;begin
 @(negedge clk);poll=1;@(negedge clk);poll=0;t1=0;
 for(j=0;j<8;j=j+1)t1={t1[55:0],request[(40+j)*8+:8]};
 repeat(4)@(negedge clk);t2=reference;
 repeat(2)@(negedge clk);t3=reference;
 repeat(4)@(negedge clk);response=0;response[7:0]=8'h24;response[15:8]=1;stamp(24,t1);stamp(32,t2);stamp(40,t3);rx=1;
 @(negedge clk);rx=0;difference=utc>reference?utc-reference:reference-utc;if(difference>max_error)max_error=difference;
 if(!locked||difference>3*(SECOND/HZ))fail("did not converge to independent reference within3 local ticks");
end endtask
initial begin
 repeat(4)@(negedge clk);rst=0;
 for(i=0;i<10;i=i+1)begin synchronize;repeat(50)@(negedge clk);end
 bias=64'h0000000200000000; // backward UTC correction; monotonic counter still free-runs
 for(i=0;i<10;i=i+1)begin synchronize;repeat(50)@(negedge clk);end
 repeat(510)@(negedge clk);if(locked)fail("missed-sync holdover not reported");
 synchronize;
 $display("RTC_REFERENCE_SYNCS=21 HZ=%0d DRIFT_PPM=%0d MAX_ERROR_NTP=%0d MAX_ERROR_NS=%0d ERRORS=%0d",HZ,drift_ppm,max_error,(max_error*1000000000)>>32,errors);
 if(errors==0)$display("TB_CONTEST_RTC_CONVERGENCE_PASS");else $display("TB_CONTEST_RTC_CONVERGENCE_FAIL");$finish;
end
endmodule
