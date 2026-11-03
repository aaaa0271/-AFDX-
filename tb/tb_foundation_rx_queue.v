`timescale 1ns/1ps
module tb_foundation_rx_queue;
reg clk=0;always #40 clk=~clk;reg rst=1;
reg [7:0] a=0,b=0;reg av=0,bv=0;
wire [7:0] md,sd;wire mv,sv;wire [31:0] accepted,duplicates,dropped;
integer errors=0,frames=0,idx=0,j,k,prev_accept,prev_drop;reg previous=0;reg [31:0] rxcrc=32'hffffffff;
reg [7:0] frame[0:71],observed[0:71];reg [31:0] crc,total;reg [15:0] sum;
afdx_shared_rx_demux #(.SKEW_MAX_CYCLES(100000)) dut(.clk(clk),.rst(rst),.loader_ip(32'h0a000001),.time_server_ip(32'h0a000001),
.a_data(a),.b_data(b),.a_valid(av),.b_valid(bv),.a_error(1'b0),.b_error(1'b0),.management_data(md),.service_data(sd),.management_valid(mv),.service_valid(sv),.accepted(accepted),.duplicates(duplicates),.dropped(dropped));
function [31:0] crcbyte;input [31:0] c;input [7:0] x;reg [31:0] v;integer n;begin v=c^x;for(n=0;n<8;n=n+1)v=v[0]?(v>>1)^32'hedb88320:v>>1;crcbyte=v;end endfunction
task fail;input [511:0] why;begin errors=errors+1;$display("FAIL RX_QUEUE %0s",why);end endtask
task build;input integer sequence_number,wrong_ip;integer n;begin
 for(n=0;n<72;n=n+1)frame[n]=0;
 for(n=0;n<7;n=n+1)frame[n]=8'h55;frame[7]=8'hd5;
 frame[8]=3;frame[13]=1;frame[14]=wrong_ip==2?3:2;frame[19]=2;frame[20]=8'h08;
 frame[22]=8'h45;frame[25]=32;frame[30]=64;frame[31]=17;
 frame[34]=192;frame[35]=168;frame[36]=1;frame[37]=wrong_ip==1?114:115;
 frame[38]=192;frame[39]=168;frame[40]=1;frame[41]=1;
 frame[42]=8'h9c;frame[43]=8'h49;frame[45]=161;frame[47]=12;
 frame[50]=sequence_number;frame[51]=~sequence_number;frame[52]=8'h6a;frame[53]=8'hb5;frame[67]=sequence_number;
 total=0;for(n=22;n<42;n=n+2)total=total+{frame[n],frame[n+1]};total=(total&65535)+(total>>16);total=(total&65535)+(total>>16);sum=~total;
 frame[32]=sum[15:8];frame[33]=sum[7:0];crc=32'hffffffff;for(n=8;n<68;n=n+1)crc=crcbyte(crc,frame[n]);crc=~crc;
 for(n=0;n<4;n=n+1)frame[68+n]=crc>>(n*8);
end endtask
task send;input integer seq,mask,corrupt,wrong_ip;integer n;begin
 build(seq,wrong_ip);
 for(n=0;n<72;n=n+1)begin @(negedge clk);a=frame[n]^((corrupt&&n==55)?8'h1:8'h0);b=frame[n];av=mask&1;bv=(mask>>1)&1;end
 @(negedge clk);av=0;bv=0;repeat(12)@(negedge clk);
end endtask
always @(posedge clk)if(!rst)begin
 if(sv)fail("management incorrectly routed to service");
 if(mv)begin
  if(!previous)begin idx=0;rxcrc=32'hffffffff;end
  if(idx>=72)fail("oversized replay");else observed[idx]=md;
  if(idx>=8)rxcrc=crcbyte(rxcrc,md);idx=idx+1;
 end else if(previous)begin
  if(idx!=72||rxcrc!==32'hdebb20e3)fail("overwritten/partial replay");
  if(observed[50]!==observed[67]||observed[51]!==~observed[50]||observed[52]!==8'h6a||observed[53]!==8'hb5)fail("queued payload/sequence corrupt");
  frames=frames+1;
 end
 previous=mv;
end
initial begin
 repeat(4)@(negedge clk);rst=0;
 send(0,3,1,0);repeat(800)@(negedge clk);
 if(accepted!=1||frames!=1||dropped!=1)fail("bad-A good-B selection");
 send(1,1,0,1);repeat(500)@(negedge clk);if(accepted!=1||dropped!=2)fail("source filter before integrity");
 send(1,3,0,0);repeat(800)@(negedge clk);if(accepted!=2||frames!=2)fail("valid recovery after filtered source");
 send(2,1,0,2);repeat(500)@(negedge clk);if(accepted!=2||dropped!=3)fail("multicast source filter before integrity");
 send(2,3,0,0);repeat(800)@(negedge clk);if(accepted!=3||frames!=3)fail("unicast source recovery");
 prev_drop=dropped;
 for(k=3;k<51;k=k+1)send(k,3,0,0);
 repeat(10000)@(negedge clk);
 if(dropped<=prev_drop||dut.used[0]!=0||dut.used[1]!=0||dut.state!=0)fail("burst overflow accounting/drain");
 prev_accept=accepted;send(0,3,0,0);repeat(800)@(negedge clk);if(accepted!=prev_accept+1)fail("queue recovery after overflow");
 @(negedge clk);rst=1;repeat(4)@(negedge clk);rst=0;frames=0;previous=0;
 send(0,3,0,0);repeat(800)@(negedge clk);if(accepted!=1||frames!=1||duplicates!=1||dropped!=0)fail("reset clears queue/history");
 $display("RX_QUEUE_FINAL accepted=%0d duplicate=%0d dropped=%0d frames=%0d errors=%0d",accepted,duplicates,dropped,frames,errors);
 if(errors==0)$display("TB_FOUNDATION_RX_QUEUE_PASS");else $display("TB_FOUNDATION_RX_QUEUE_FAIL");$finish;
end
initial begin #5000000;$display("RX_QUEUE_TIMEOUT");$finish;end
endmodule