`timescale 1ns/1ps
module tb_completion_package_network;
reg clk=0;always #5 clk=~clk;reg rst=1,poll=0,rv=0;reg [31:0] rip=0,expected_crc;reg [15:0] rsp=0,rdp=0,read_addr=0;reg [10:0] rlen=0;reg [4127:0] rb=0;
wire tv,locked,image_valid,loading,complete,failed,service_idle;wire [31:0] tip,icrc;wire [15:0] tsp,tdp,ilen;wire [10:0] tlen;wire [4127:0] tb;wire [7:0] idata;wire [63:0] utc,mono;
wire [31:0] generation;wire [2:0] file_count;reg [1:0] app_file=0;
reg [7:0] header[0:125],file_a[0:699],file_b[0:1023];integer current_file=0,current_length=0,current_offset=0,current_block=0;
integer mode=0,drop_final=1,dropped=0,aborted_status=0,sent_zero=0;
integer errors=0,lui_done=0,lur_done=0,reports=0,final_reports=0,blocks=0,k,j,t;reg pending=0;reg [31:0] pi;reg [15:0] ps,pd;reg [10:0] pl;reg [4127:0] pb;
reg [1023:0] lurfile=0;reg [63:0] origin,remote_stamp;reg [31:0] c;
afdx_package_network_services #(.CLK_HZ(1024),.TIMEOUT_CYCLES(3000)) dut(
.clk(clk),.rst(rst),.loader_ip(32'h0a000001),.time_server_ip(32'h0a000064),.hardware_length(6'd3),.hardware_id({232'd0,24'h4d4953}),
.rtc_poll(poll),.rtc_locked(locked),.utc_ntp(utc),.monotonic_ticks(mono),.package_valid(image_valid),.generation(generation),.package_crc(icrc),.file_count(file_count),.app_file(app_file),.app_address(read_addr),.app_data(idata),.app_length(ilen),.app_name(),
.loading(loading),.load_complete(complete),.load_failed(failed),.service_idle(service_idle),.tx_valid(tv),.tx_ready(1'b1),.tx_ip(tip),.tx_sport(tsp),.tx_dport(tdp),.tx_length(tlen),.tx_bytes(tb),
.rx_valid(rv),.rx_ip(rip),.rx_sport(rsp),.rx_dport(rdp),.rx_length(rlen),.rx_bytes(rb));
task fail;input [511:0] why;begin errors=errors+1;$display("FAIL NETWORK %0s",why);end endtask
function [31:0] crcbyte;input [31:0] a;input [7:0] b;reg [31:0] x;integer n;begin x=a^b;for(n=0;n<8;n=n+1)x=x[0]?(x>>1)^32'hedb88320:x>>1;crcbyte=x;end endfunction
task data_reply;input integer block,n,offset;integer z;reg [7:0] value;begin
 pb=0;pb[15:8]=3;pb[23:16]=block>>8;pb[31:24]=block;pl=n+4;ps=30000;
 for(z=0;z<n;z=z+1)begin
  case(current_file)0:value=header[offset+z];1:value=file_a[offset+z];default:value=file_b[offset+z];endcase
  if(mode==1&&current_file==2&&offset+z==5)value=value^1;
  pb[(4+z)*8+:8]=value;
 end
end endtask
always @(posedge clk)if(!rst&&tv)begin
 if(pending)fail("peer response queue collision");
 pb=0;pi=tip;pd=tsp;ps=tdp;pl=4;
 if(tdp==123)begin
  origin=0;for(j=0;j<8;j=j+1)origin={origin[55:0],tb[(40+j)*8+:8]};remote_stamp=origin+64'h100000000;
  pb[7:0]=8'h24;pb[15:8]=1;pl=48;
  for(j=0;j<8;j=j+1)begin pb[(24+j)*8+:8]=origin[63-j*8-:8];pb[(32+j)*8+:8]=remote_stamp[63-j*8-:8];pb[(40+j)*8+:8]=remote_stamp[63-j*8-:8];end
  pending=1;
 end else if(tsp==41000)begin
  if(tb[15:8]==3)begin
   if(tlen!=14||tb[4*8+:80]!=80'h0001010034410a000000)fail("wire LUI file");
   pb[15:8]=4;pb[31:24]=1;pending=1;lui_done=1;
  end else if(tb[15:8]==4&&tb[31:24]==0)begin
   pb[15:8]=3;pb[31:24]=1;pb[4*8+:184]=lurfile[183:0];pl=27;pending=1;
  end else if(tb[15:8]==4&&tb[31:24]==1)lur_done=1;
  else fail("control server packet");
 end else if(tsp==40002)begin
  ps=30002;pb[15:8]=4;
  if(tb[15:8]==2)begin
   if(tb[2*8+:80]!=80'h53554c2e544547524154)fail("LUS WRQ filename");pb[31:24]=0;
  end else if(tb[15:8]==3)begin
   pb[31:24]=1;reports=reports+1;
   if({tb[10*8+:8],tb[11*8+:8]}==3)begin
    final_reports=final_reports+1;
    if(mode==0&&generation!=0)fail("published before final status ACK");
   end
   if({tb[10*8+:8],tb[11*8+:8]}==16'h1003)aborted_status=aborted_status+1;
  end else fail("status client opcode");pending=1;
  if(tb[15:8]==3&&{tb[10*8+:8],tb[11*8+:8]}==3&&drop_final&&!dropped)begin pending=0;dropped=1;end
 end else if(tsp>=42000)begin
  if(tb[15:8]==1)begin
   if(tb[2*8+:56]==56'h48554c2e505041)begin current_file=0;current_length=126;end
   else if(tb[2*8+:40]==40'h50554c2e41)begin current_file=1;current_length=700;end
   else if(tb[2*8+:40]==40'h50554c2e42)begin current_file=2;current_length=1024;end
   else fail("LUH requested file name");
   current_offset=0;current_block=1;sent_zero=0;data_reply(1,current_length>512?512:current_length,0);pending=1;blocks=blocks+1;
  end else if(tb[15:8]==4)begin
   if(current_length-current_offset>=512)begin current_offset=current_offset+512;current_block=current_block+1;
    data_reply(current_block,current_length-current_offset>512?512:current_length-current_offset,current_offset);pending=1;blocks=blocks+1;
   end else if(!sent_zero)begin
    current_block=current_block+1;sent_zero=1;data_reply(current_block,0,current_offset);pending=1;blocks=blocks+1;
   end
  end else fail("fetch ACK");
 end else fail("unknown transfer ID");
end
always @(negedge clk)if(!rst)begin
 rv=0;if(pending)begin rv=1;rip=pi;rsp=ps;rdp=pd;rlen=pl;rb=pb;pending=0;end
end
task request_control;input integer op;input [79:0] file_name;begin
 // Queue a peer-originated RFC1350 RRQ/WRQ, rather than calling file APIs.
 @(posedge clk);#1;pb=0;pb[15:8]=op;pb[2*8+:80]=file_name;pb[13*8+:48]=48'h00746574636f;
 pi=32'h0a000001;ps=32000;pd=69;pl=19;pending=1;
end endtask
task transaction;input integer newmode;
 begin
 mode=newmode;lui_done=0;lur_done=0;request_control(1,80'h49554c2e544547524154);
 t=0;while(!lui_done&&t<300)begin @(negedge clk);t=t+1;end
 repeat(4)@(negedge clk);request_control(2,80'h52554c2e544547524154);
 @(posedge clk);#1;poll=1;@(posedge clk);#1;poll=0;
 t=0;while((newmode==1?!failed:!complete)&&t<15000)begin @(negedge clk);t=t+1;end
 repeat(10)@(negedge clk);
 if(!image_valid||file_count!=2||generation!=(newmode==2?2:1)||!locked||failed!==(newmode==1))fail("network package commit/recovery");
 for(k=0;k<1724;k=k+1)begin app_file=k<700?0:1;read_addr=k<700?k:k-700;#1;if(idata!==(k<700?file_a[k]:file_b[k-700]))fail("package atomic application bytes");end
 repeat(50)@(negedge clk);
 end
endtask
integer input_fd;
initial begin
 $readmemh("APP.LUH.hex",header);$readmemh("A.LUP.hex",file_a);$readmemh("B.LUP.hex",file_b);
 lurfile[3*8+:8]=23;lurfile[4*8+:8]="A";lurfile[5*8+:8]="4";lurfile[7*8+:8]=1;lurfile[8*8+:8]=8;lurfile[9*8+:64]=64'h0048554c2e505041;lurfile[17*8+:8]=5;lurfile[18*8+:40]=40'h00312d4e50;
 repeat(4)@(negedge clk);rst=0;#1;if(service_idle!==1'b1)fail("reset idle contract");transaction(0);drop_final=0;transaction(1);transaction(2);
 t=0;while(!service_idle&&t<4000)begin @(negedge clk);t=t+1;end
 if(service_idle!==1'b1)fail("post-transaction idle contract");
 if(!dropped||aborted_status!=1)fail("lost ACK and aborted LUS coverage");
 $display("PACKAGE_NETWORK_FILES=%0d GENERATIONS=%0d STATUS_REPORTS=%0d FINAL_REPORTS=%0d ERRORS=%0d",file_count,generation,reports,final_reports,errors);
 if(errors==0)$display("TB_COMPLETION_PACKAGE_NETWORK_PASS");else $display("TB_COMPLETION_PACKAGE_NETWORK_FAIL");$finish;
end
initial begin #1000000;$display("NETWORK_SERVICES_TIMEOUT");$finish;end
endmodule
