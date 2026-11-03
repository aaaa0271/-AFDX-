`timescale 1ns/1ps
// Simulation peer, not RTL in the delivered FPGA. Provides a loader and NTP
// server over actual Ethernet/IPv4/UDP/AFDX frames on a MAC byte interface.
module model_loader_ntp_peer(
 input wire clk,rst,start,input wire [7:0] rxd,input wire dv,er,
 output wire [7:0] txd,output wire txen,txer,
 output reg [31:0] errors,output reg [31:0] reports,final_reports,
 output reg lui_seen,lur_seen,ntp_seen
);
wire pv,pr;wire [31:0] pip;wire [15:0] psp,pdp;wire [10:0] plen;wire [4127:0] packet;
reg [4127:0] queue[0:7];reg [10:0] lengths[0:7];reg [15:0] sports[0:7],dports[0:7];
reg [7:0] header[0:125],file_a[0:699],file_b[0:1023];integer current_file,current_length,current_offset,current_block;
integer head=0,tail=0,count=0,phase=0,j;reg push;reg [4127:0] pb;reg [10:0] pl;reg [15:0] ps,pd;reg [1023:0] lurfile;reg [63:0] origin,remote_time;
afdx_service_gmii #(.LOCAL_MAC(48'h020000000002),.PEER_MAC(48'h030000000010),.LOCAL_IP(32'h0a000001),.BAG_CYCLES(1)) mac(
 .tx_admit(1'b1),
.clk(clk),.rst(rst),.gmii_rxd(rxd),.gmii_rx_dv(dv),.gmii_rx_er(er),.gmii_txd(txd),.gmii_tx_en(txen),.gmii_tx_er(txer),.tx_done(),
.rx_valid(pv),.rx_ip(pip),.rx_sport(psp),.rx_dport(pdp),.rx_length(plen),.rx_bytes(packet),
.tx_valid(count!=0),.tx_ready(pr),.tx_ip(32'h0a000010),.tx_sport(sports[head]),.tx_dport(dports[head]),.tx_length(count!=0?lengths[head]:11'd1),.tx_bytes(queue[head]),.received(),.rejected());
task fail;input [511:0] why;begin errors=errors+1;$display("FAIL PEER %0s",why);end endtask
task enqueue;begin
 if(count>=8)fail("response queue overflow");
 else begin queue[tail]=pb;lengths[tail]=pl;sports[tail]=ps;dports[tail]=pd;tail=(tail+1)%8;count=count+1;end
end endtask
task control_request;input integer op;input [79:0] name;begin
 pb=0;pb[15:8]=op;pb[2*8+:80]=name;pb[13*8+:48]=48'h00746574636f;pl=19;ps=32000;pd=69;enqueue;
end endtask
task data_reply;input integer block,n,offset;integer z;reg [7:0] value;begin
 pb=0;pb[15:8]=3;pb[23:16]=block>>8;pb[31:24]=block;pl=n+4;ps=30000;
 for(z=0;z<n;z=z+1)begin
  case(current_file)0:value=header[offset+z];1:value=file_a[offset+z];default:value=file_b[offset+z];endcase
  pb[(4+z)*8+:8]=value;
 end
end endtask
always @(posedge clk)begin
 // Sample outgoing queue before changes, as the MAC's handshake does.
 if(rst)begin head=0;tail=0;count=0;phase=0;errors=0;reports=0;final_reports=0;lui_seen=0;lur_seen=0;ntp_seen=0;end
 else begin
  if(count!=0&&pr)begin #1;head=(head+1)%8;count=count-1;end
  else #1;
  if(start&&phase==0)begin control_request(1,80'h49554c2e544547524154);phase=1;end
  else if(phase==2&&count==0&&pr)begin control_request(2,80'h52554c2e544547524154);phase=3;end
 end
end
// Commit notification is sampled before NBA. Queue writes occur on the falling
// edge, so no testbench race can change a packet on its acceptance edge.
reg incoming=0;reg [4127:0] incoming_bytes;reg [15:0] incoming_sp,incoming_dp;reg [10:0] incoming_len;
always @(posedge clk)begin incoming=pv;if(pv)begin incoming_bytes=packet;incoming_sp=psp;incoming_dp=pdp;incoming_len=plen;end end
always @(negedge clk)if(!rst&&incoming)begin
 push=0;pb=0;pl=4;ps=incoming_dp;pd=incoming_sp;
 if(incoming_dp==123)begin
  origin=0;for(j=0;j<8;j=j+1)origin={origin[55:0],incoming_bytes[(40+j)*8+:8]};remote_time=origin+64'h100000000;
  pb[7:0]=8'h24;pb[15:8]=1;pl=48;
  for(j=0;j<8;j=j+1)begin pb[(24+j)*8+:8]=origin[63-j*8-:8];pb[(32+j)*8+:8]=remote_time[63-j*8-:8];pb[(40+j)*8+:8]=remote_time[63-j*8-:8];end
  push=1;ntp_seen=1;
 end else begin $display("PEER_RX sp=%0d dp=%0d op=%0d block=%0d len=%0d",incoming_sp,incoming_dp,{incoming_bytes[7:0],incoming_bytes[15:8]},{incoming_bytes[23:16],incoming_bytes[31:24]},incoming_len); end
 if(incoming_sp>=42000&&incoming_sp<43000)begin
  if(incoming_bytes[15:8]==1)begin
   if(incoming_bytes[2*8+:56]==56'h48554c2e505041)begin current_file=0;current_length=126;end
   else if(incoming_bytes[2*8+:40]==40'h50554c2e41)begin current_file=1;current_length=700;end
   else if(incoming_bytes[2*8+:40]==40'h50554c2e42)begin current_file=2;current_length=1024;end
   else fail("package requested unknown file");
   current_offset=0;current_block=1;data_reply(1,current_length>512?512:current_length,0);$display("PEER_TX_DATA file=%0d len=%0d dest=%0d",current_file,current_length,incoming_sp);push=1;
  end else if(incoming_bytes[15:8]==4)begin
   if(incoming_bytes[31:24]==current_block)begin
    if(current_length-current_offset>=512)begin
      current_offset=current_offset+512;current_block=current_block+1;
      data_reply(current_block,current_length-current_offset>512?512:current_length-current_offset,current_offset);push=1;
     end
   end
  end else fail("package TID opcode");
 end else if(incoming_sp==41000)begin
  if(incoming_bytes[15:8]==3)begin
   if(incoming_len!=14||incoming_bytes[4*8+:80]!=80'h0001010034410a000000)fail("LUI response");
   pb[15:8]=4;pb[31:24]=1;push=1;lui_seen=1;phase=2;
  end else if(incoming_bytes[15:8]==4&&incoming_bytes[31:24]==0)begin
   lurfile=0;lurfile[3*8+:8]=23;lurfile[4*8+:8]="A";lurfile[5*8+:8]="4";lurfile[7*8+:8]=1;
   lurfile[8*8+:8]=8;lurfile[9*8+:64]=64'h0048554c2e505041;lurfile[17*8+:8]=5;lurfile[18*8+:40]=40'h00312d4e50;
   pb[15:8]=3;pb[31:24]=1;pb[4*8+:184]=lurfile[183:0];pl=27;push=1;
  end else if(incoming_bytes[15:8]==4&&incoming_bytes[31:24]==1)lur_seen=1;
  else fail("control opcode");
 end else if(incoming_sp==40002)begin
  ps=30002;pb[15:8]=4;
  if(incoming_bytes[15:8]==2)begin if(incoming_bytes[2*8+:80]!=80'h53554c2e544547524154)fail("LUS WRQ");pb[31:24]=0;end
  else if(incoming_bytes[15:8]==3)begin
   pb[31:24]=1;reports=reports+1;if({incoming_bytes[10*8+:8],incoming_bytes[11*8+:8]}==3)final_reports=final_reports+1;
  end else fail("LUS opcode");push=1;
 end else if(incoming_sp==40000)begin
  if(incoming_bytes[15:8]==1)begin if(incoming_bytes[2*8+:56]!=56'h48554c2e505041)fail("fetch name");data_reply(1,512,0);push=1;end
  else if(incoming_bytes[15:8]==4&&incoming_bytes[31:24]==1)begin data_reply(2,188,512);push=1;end
  else if(incoming_bytes[15:8]!=4||incoming_bytes[31:24]!=2)fail("fetch ACK");
 end else if(incoming_dp==123)begin /* NTP reply is already prepared; keep push asserted. */ end else begin $display("PEER_UNKNOWN sp=%0d dp=%0d opcode=%0d block=%0d len=%0d",incoming_sp,incoming_dp,{incoming_bytes[7:0],incoming_bytes[15:8]},{incoming_bytes[23:16],incoming_bytes[31:24]},incoming_len);fail("unknown client TID");end
 if(push)enqueue;
end
initial begin
 $readmemh("APP.LUH.hex",header);
 $readmemh("A.LUP.hex",file_a);
 $readmemh("B.LUP.hex",file_b);
end
endmodule