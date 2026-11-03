`timescale 1ns/1ps
module tb_contest_service_mac;
reg clk=0;always #5 clk=~clk;reg rst=1,valid=0,corrupt=0;
reg [10:0] length=0;reg [4127:0] data=0;
wire ready,txen,txer,done,rv;wire [7:0] td;wire [31:0] rip,received,rejected;wire [15:0] sp,dp;wire [10:0] rlen;wire [4127:0] rd;
integer errors=0,frame_index=0,packets=0,rx_packets=0,i,j,t;reg prev=0;reg [31:0] wire_crc;reg corrupt_q;
afdx_service_gmii #(.BAG_CYCLES(100)) a(
 .tx_admit(1'b1),.clk(clk),.rst(rst),.gmii_rxd(8'd0),.gmii_rx_dv(1'b0),.gmii_rx_er(1'b0),.gmii_txd(td),.gmii_tx_en(txen),.gmii_tx_er(txer),.tx_done(done),
.rx_valid(),.rx_ip(),.rx_sport(),.rx_dport(),.rx_length(),.rx_bytes(),.tx_valid(valid),.tx_ready(ready),.tx_ip(32'h0a000001),.tx_sport(16'd40000),.tx_dport(16'd69),.tx_length(length),.tx_bytes(data),.received(),.rejected());
afdx_service_gmii #(.LOCAL_MAC(48'h020000000002),.PEER_MAC(48'h030000000010),.LOCAL_IP(32'h0a000001)) b(
 .tx_admit(1'b1),.clk(clk),.rst(rst),
.gmii_rxd((corrupt&&frame_index==50)?td^8'h01:td),.gmii_rx_dv(txen),.gmii_rx_er(txer),.gmii_txd(),.gmii_tx_en(),.gmii_tx_er(),.tx_done(),
.rx_valid(rv),.rx_ip(rip),.rx_sport(sp),.rx_dport(dp),.rx_length(rlen),.rx_bytes(rd),.tx_valid(1'b0),.tx_ready(),.tx_ip(32'd0),.tx_sport(16'd0),.tx_dport(16'd0),.tx_length(11'd0),.tx_bytes(4128'd0),.received(received),.rejected(rejected));
task fail;input [511:0] why;begin errors=errors+1;$display("FAIL SERVICE_MAC %0s",why);end endtask
function [31:0] crcbyte;input [31:0] c;input [7:0] x;reg [31:0] v;integer k;begin v=c^x;for(k=0;k<8;k=k+1)v=v[0]?(v>>1)^32'hedb88320:v>>1;crcbyte=v;end endfunction
always @(posedge clk)begin
 if(!rst)begin
  if(txen)begin
   if(!prev)begin frame_index=0;wire_crc=32'hffffffff;end
   if(frame_index>=8)wire_crc=crcbyte(wire_crc,td);
   frame_index=frame_index+1;
  end else if(prev)begin
   packets=packets+1;if(wire_crc!=32'hdebb20e3||frame_index!=(length<=17?72:55+length))fail("independent wire FCS/length");
  end
  prev=txen;
  if(rv)begin rx_packets=rx_packets+1;if(corrupt||rip!=32'h0a000010||sp!=40000||dp!=69||rlen!=length)fail("UDP metadata");
   for(j=0;j<length;j=j+1)if(rd[j*8+:8]!==((j*17+length)&255))fail("UDP payload");
  end
 end
end
task send;input integer n;input bad;begin
 length=n;corrupt=bad;data=0;for(i=0;i<n;i=i+1)data[i*8+:8]=(i*17+n)&255;
 @(negedge clk);valid=1;begin:waitready for(t=0;t<200;t=t+1)begin @(posedge clk);if(ready)disable waitready;end fail("request not accepted");end
 @(negedge clk);valid=0;repeat(2*n+250)@(negedge clk);
end endtask
initial begin repeat(5)@(negedge clk);rst=0;send(1,0);send(4,0);send(48,0);send(516,0);send(516,1);
if(rx_packets!=4||packets!=5||rejected!=1)fail("packet totals");
$display("SERVICE_MAC_TX=%0d RX=%0d REJECT=%0d ERRORS=%0d",packets,rx_packets,rejected,errors);
if(errors==0)$display("TB_CONTEST_SERVICE_MAC_PASS");else $display("TB_CONTEST_SERVICE_MAC_FAIL");$finish;end
initial begin #100000;$display("SERVICE_MAC_TIMEOUT");$finish;end
endmodule
