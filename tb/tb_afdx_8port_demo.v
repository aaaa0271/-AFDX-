`timescale 1ns/1ps
// Test the actual eight-pin shell, not a substituted configurable top.
module tb_afdx_8port_demo;
reg clk=0;always #40 clk=~clk;
reg reset=1,rx_ready=0;
wire [7:0] tx_data;wire tx_valid,tx_ready;
AFDX_top #(.DEMO_INTERVAL_CYCLES(1000),.RTC_POLL_CYCLES(12500)) dut(.clk(clk),.reset(reset),.rx_ready(rx_ready),.rx_data(8'd0),.rx_valid(1'b0),
 .tx_data(tx_data),.tx_valid(tx_valid),.tx_ready(tx_ready));
integer errors=0,cycles=0,polls=0,last_poll=-1,seals=0,accepted=0,stalls=0;
integer business=0,ntp=0,n=0,k,j,phase;
reg previous=0,held=0;
reg [25:0] held_fields;
reg [7:0] frame[0:1535];
reg [31:0] crc;
function [31:0] crcbyte;input [31:0] c;input [7:0] x;integer b;reg [31:0] v;begin
 v=c^x;for(b=0;b<8;b=b+1)v=v[0]?(v>>1)^32'hedb88320:v>>1;crcbyte=v;
end endfunction
task fail;input [511:0] why;begin errors=errors+1;$display("FAIL eight-port %0s t=%0t",why,$time);end endtask
task check_frame;begin
 if(n<72||crc!==32'hdebb20e3)fail("wire length/FCS");
 for(k=0;k<7;k=k+1)if(frame[k]!==8'h55)fail("preamble");
 if(frame[7]!==8'hd5||{frame[20],frame[21]}!==16'h0800||frame[31]!==17)fail("Ethernet/IP/UDP");
 if({frame[8],frame[9],frame[10],frame[11],frame[12],frame[13]}>=48'h030000000040&&
    {frame[8],frame[9],frame[10],frame[11],frame[12],frame[13]}<=48'h030000000043)begin
  business=business+1;
  if(n!=72||{frame[46],frame[47]}!==16'd24)fail("business configuration/length on wire");
  if({frame[53],frame[52],frame[51],frame[50]}!==32'h58444641)fail("business payload signature");
 end else if({frame[44],frame[45]}==16'd123)begin
  ntp=ntp+1;
  if(n!=103||{frame[38],frame[39],frame[40],frame[41]}!==32'h0a000101||
     {frame[46],frame[47]}!==16'd56||frame[50][2:0]!==3'd3)fail("NTP request on wire");
 end else fail("unexpected demo traffic");
end endtask
always @(posedge clk)begin
 if(reset)begin
  cycles=0;polls=0;last_poll=-1;seals=0;accepted=0;stalls=0;business=0;ntp=0;
  previous=0;held=0;n=0;
 end else begin
  cycles=cycles+1;
  if(dut.cfg_rx_error||dut.app_len_error||dut.app_access_error)fail("configuration/application error");
  if(dut.cfg_rx_seal)begin
   seals=seals+1;
   if(dut.cfg_rx_write||dut.cfg_we||dut.cfg_port_write)fail("seal overlaps a write");
  end
  if(held&&(!dut.app_wr_en||{dut.app_wr_data,dut.app_wr_len,dut.app_wr_sof,dut.app_wr_eof}!==held_fields))fail("source changed under backpressure");
  held=dut.app_wr_en&&!dut.app_wr_ready;
  held_fields={dut.app_wr_data,dut.app_wr_len,dut.app_wr_sof,dut.app_wr_eof};
  if(held)stalls=stalls+1;
  if(dut.app_wr_accept)accepted=accepted+1;
  if(dut.rtc_poll)begin
   if(last_poll>=0&&cycles-last_poll!=12500)fail("RTC poll period");
   last_poll=cycles;polls=polls+1;
  end
  #1;
  if(dut.a_tx_er||dut.shared_tx_overflows!=0)fail("wire error/overflow");
  if(tx_valid)begin
   if(!previous)begin n=0;crc=32'hffffffff;end
   frame[n]=tx_data;if(n>=8)crc=crcbyte(crc,tx_data);n=n+1;
  end else if(previous)check_frame;
  previous=tx_valid;
 end
end
task configuration_check;begin
 if(!dut.cfg_rx_ready||!dut.u_end_system.port_sealed||seals!=1)fail("configuration not sealed once");
 if(dut.u_end_system.business_bags[31:0]!==32'd12500)fail("TX BAG not installed before seal");
 for(j=0;j<4;j=j+1)begin
  if(dut.u_end_system.rx_cfg_table[j*168+:8]!==8'h03||dut.u_end_system.port_table[j*64+:64]!==64'h0100000000000001)fail("RX/port configuration not installed");
 end
 if(dut.u_end_system.hardware_length!==6'd3||dut.u_end_system.hardware_id!=={232'd0,24'h4d4953})fail("hardware identifier");
end endtask
initial begin
 repeat(5)@(negedge clk);
 if(tx_ready!==0)fail("reset ready");reset=0;
 repeat(40)@(negedge clk);configuration_check;
 // Block both physical lanes until the finite ingress queue backpressures.
 repeat(40000)@(negedge clk);
 if(tx_valid||business!=0||ntp!=0||stalls==0)fail("network disable/backpressure not exercised");
 rx_ready=1;
 repeat(40000)@(negedge clk);
 if(business<2||ntp<1||polls<2||accepted<32||tx_ready!==1)fail("missing live business/RTC traffic");
 $display("EIGHT_PORT phase=0 business=%0d ntp=%0d polls=%0d accepted=%0d stalls=%0d",business,ntp,polls,accepted,stalls);
 // A second reset must repeat initialization and resume real traffic.
 reset=1;repeat(5)@(negedge clk);reset=0;
 repeat(40)@(negedge clk);configuration_check;
 repeat(26000)@(negedge clk);
 if(business<2||ntp<1||polls<2)fail("reset restart");
 $display("EIGHT_PORT phase=1 business=%0d ntp=%0d polls=%0d errors=%0d",business,ntp,polls,errors);
 if(errors==0)$display("TB_AFDX_8PORT_DEMO_PASS");else $display("TB_AFDX_8PORT_DEMO_FAIL");
 $finish;
end
initial begin #12000000;fail("timeout");$finish;end
endmodule
