`timescale 1ns/1ps
// Independent, integral reference clock and real raw Ethernet packets.
module tb_review_rtc_mac;
localparam [63:0] INITIAL=64'h100000000,STEP=64'd65536;
reg clk=0;always #5 clk=~clk;
reg rst=1,enabled=0,rx_valid=0;reg [7:0] rx_data=0;
wire [7:0] tx_data;wire tx_valid,ready;
integer errors=0,cycles=0,count=0,i,j,n,timeout,business;
reg previous=0,request_seen=0;reg [7:0] captured[0:1535],frame[0:102];
reg [63:0] tx_reference,origin,t2,t3,difference,first_reference;
reg [31:0] crc;integer sum;
AFDX_top #(.CLK_HZ(65536),.DEMO_INTERVAL_CYCLES(500),.RTC_POLL_CYCLES(100000),.SERVICE_TIMEOUT_CYCLES(20000)) dut(
 .clk(clk),.reset(rst),.tx_data(tx_data),.rx_data(rx_data),.tx_valid(tx_valid),.rx_valid(rx_valid),.tx_ready(ready),.rx_ready(enabled));
task fail;input [511:0] why;begin errors=errors+1;$display("FAIL RTC_MAC %0s",why);end endtask
function [31:0] crcbyte;input [31:0] c;input [7:0] b;reg [31:0] v;integer z;begin
 v=c^b;for(z=0;z<8;z=z+1)v=v[0]?(v>>1)^32'hedb88320:v>>1;crcbyte=v;
end endfunction
always @(posedge clk)begin
 if(rst)begin cycles<=0;count=0;previous=0;request_seen=0;business=0;end
 else begin
  cycles<=cycles+1;
  if(tx_valid)begin
   if(!previous)begin count=0;first_reference=INITIAL+cycles*STEP;end
   captured[count]=tx_data;count=count+1;
  end else if(previous)begin
   if(count==103&&captured[44]==0&&captured[45]==123&&captured[50]==8'h23)begin
    request_seen=1;tx_reference=first_reference;origin=0;
    for(j=0;j<8;j=j+1)origin={origin[55:0],captured[90+j]};
   end else business=business+1;
  end
  previous=tx_valid;
 end
end
task response;input integer sequence_number;input integer stratum;begin
 t2=tx_reference+4*STEP;t3=INITIAL+cycles*STEP-4*STEP;
 for(i=0;i<103;i=i+1)frame[i]=0;
 for(i=0;i<7;i=i+1)frame[i]=8'h55;frame[7]=8'hd5;
 frame[8]=3;frame[13]=8'h10;frame[14]=2;frame[19]=2;
 frame[20]=8'h08;frame[22]=8'h45;frame[25]=76;frame[30]=64;frame[31]=17;
 frame[34]=10;frame[36]=1;frame[37]=1;frame[38]=10;frame[41]=16;
 sum=0;for(i=22;i<42;i=i+2)sum=sum+{frame[i],frame[i+1]};
 sum=(sum&65535)+(sum>>16);sum=(sum&65535)+(sum>>16);sum=(~sum)&65535;
 frame[32]=sum>>8;frame[33]=sum;
 frame[43]=123;frame[44]=8'h9c;frame[45]=8'h41;frame[47]=56;frame[50]=8'h24;frame[51]=stratum;
 for(i=0;i<8;i=i+1)begin frame[74+i]=origin[63-i*8-:8];frame[82+i]=t2[63-i*8-:8];frame[90+i]=t3[63-i*8-:8];end
 frame[98]=sequence_number;crc=32'hffffffff;
 for(i=8;i<99;i=i+1)crc=crcbyte(crc,frame[i]);crc=~crc;
 for(i=0;i<4;i=i+1)frame[99+i]=crc>>(i*8);
 for(i=0;i<103;i=i+1)begin rx_data=frame[i];rx_valid=1;@(negedge clk);end
 rx_valid=0;repeat(12)@(negedge clk);
end endtask
initial begin
 for(n=0;n<3;n=n+1)begin
  rst=1;enabled=0;rx_valid=0;repeat(4)@(negedge clk);rst=0;
  repeat(20+n*200)@(negedge clk);enabled=1;
  timeout=0;while(!request_seen&&timeout<20000)begin @(negedge clk);timeout=timeout+1;end
  if(!request_seen)begin fail("no automatic NTP request");$finish;end
  response(1,0);response(2,0);response(3,1);
  timeout=0;while(!dut.rtc_locked&&timeout<5000)begin @(negedge clk);timeout=timeout+1;end
  difference=dut.u_end_system.utc_ntp>(INITIAL+cycles*STEP)?dut.u_end_system.utc_ntp-(INITIAL+cycles*STEP):(INITIAL+cycles*STEP)-dut.u_end_system.utc_ntp;
  $display("RTC_MAC queue=%0d error_ticks=%0d business_frames=%0d",n*200,difference/STEP,business);
  if(!dut.rtc_locked||difference>STEP)fail("queued MAC exchange produced biased lock");
  if(dut.u_end_system.MULTI_SERVICES.plane.LANES[0].ACTIVE.client.ntp.t1!==tx_reference)fail("T1 is not final MAC departure");
  if(!ready||dut.cfg_rx_error)fail("demo configuration failed");
 end
 if(errors==0)$display("TB_REVIEW_RTC_MAC_PASS");$finish;
end
initial begin #2000000;fail("watchdog");$finish;end
endmodule
