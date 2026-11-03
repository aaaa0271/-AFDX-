`timescale 1ns/1ps
module tb_review_control_budget;
reg clk=0;always #5 clk=~clk;
reg rst=1,rx=0,ready=1,accept=0;reg [15:0] source=30000,destination=69;
reg [10:0] length=19;reg [4127:0] packet=0;
wire tx,idle;wire [15:0] tx_port;integer errors=0,cases=0,k,n;
afdx_615a_control_tftp #(.TIMEOUT_CYCLES(20)) dut(
 .clk(clk),.rst(rst),.loader_ip(32'h0a000001),.rx_valid(rx),.rx_ip(32'h0a000001),.rx_sport(source),.rx_dport(destination),
 .rx_length(length),.rx_bytes(packet),.tx_valid(tx),.tx_ready(ready),.tx_dport(tx_port),.initialize(),.lui_valid(1'b0),
 .lui_ready(),.lui_bytes(80'd0),.lur_valid(),.lur_length(),.lur_bytes(),.lur_accept(accept),.lur_reject(1'b0),.loading(1'b0),.idle(idle));
task fail;input [511:0] why;begin errors=errors+1;$display("FAIL CONTROL_BUDGET %0s",why);end endtask
task begin_session;input integer op;begin
 cases=cases+1;rst=1;rx=0;ready=1;accept=0;source=30000;destination=69;
 repeat(3)@(negedge clk);rst=0;
 packet=0;packet[15:8]=op;packet[16+:80]=op==1?80'h49554c2e544547524154:80'h52554c2e544547524154;
 packet[104+:48]=48'h00746574636f;length=19;rx=1;
 @(negedge clk);rx=0;while(tx)@(negedge clk);
end endtask
initial begin
 for(k=0;k<3;k=k+1)begin
  begin_session(k==1?1:2);
  destination=41000;source=30001;packet=0;packet[15:8]=4;packet[31:24]=1;length=4;
  for(n=0;n<40;n=n+1)begin
   repeat(4)@(negedge clk);rx=1;@(negedge clk);rx=0;
   if(k==2&&n==0)ready=0;
   @(negedge clk);
  end
  if(dut.state!=0)fail("unknown TID traffic kept session alive");
  ready=1;repeat(2)@(negedge clk);
  if(tx_port!=30000)fail("peer TID not restored");
 end
 begin_session(2);destination=41000;
 while(dut.retry_count<3||tx)@(negedge clk);
 while(dut.age<19)@(negedge clk);
 packet=0;packet[15:8]=3;packet[31:24]=1;length=5;rx=1;
 @(negedge clk);rx=0;accept=1;@(negedge clk);accept=0;
 if(dut.state!=5)fail("valid DATA lost at deadline");
 while(tx)@(negedge clk);
 for(n=0;n<20;n=n+1)begin repeat(2)@(negedge clk);rx=1;@(negedge clk);rx=0;end
 if(dut.state!=0)fail("duplicate final DATA renewed control dally");
 $display("CONTROL_BUDGET_CASES=%0d",cases);
 if(errors==0)$display("TB_REVIEW_CONTROL_BUDGET_PASS");$finish;
end
initial begin #100000;fail("watchdog");$finish;end
endmodule
