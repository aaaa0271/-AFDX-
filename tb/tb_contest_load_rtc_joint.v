`timescale 1ns/1ps
module tb_contest_load_rtc_joint;
reg clk=0;always #5 clk=~clk;reg rst=1,init=0,lur=0,poll=0,ready=1,rx=0;
reg [1023:0] request=0;reg [4127:0] packet=0;reg [15:0] sp=0,dp=0,ra=0;reg [10:0] plen=0;reg [31:0] rip=0,expect_crc;
wire iv,la,lr,sv,loading,complete,failed,image_ok,locked,tv;wire [79:0] ib;wire [7:0] sl,rd;wire [1023:0] sb;
wire [15:0] image_len,ts,td;wire [31:0] image_crc,tip;wire [63:0] utc,mono;wire [10:0] tl;wire [4127:0] tb;
integer errors=0,i,k,packets=0;reg [63:0] origin;reg [31:0] c;
afdx_load_rtc_services #(.CLK_HZ(1024),.TFTP_TIMEOUT(1500),.NTP_TIMEOUT(2000)) dut(
 .clk(clk),.rst(rst),.loader_initialize(init),.lui_valid(iv),.lui_ready(1'b1),.lui_bytes(ib),.lur_valid(lur),.lur_length(16'd23),.lur_bytes(request),.lur_accept(la),.lur_reject(lr),
 .lus_valid(sv),.lus_ready(1'b1),.lus_length(sl),.lus_bytes(sb),.loader_ip(32'h0a000001),.expected_image_length(16'd700),.expected_image_crc(expect_crc),
 .image_valid(image_ok),.image_length(image_len),.image_crc(image_crc),.image_read_address(ra),.image_read_data(rd),.loading(loading),.load_complete(complete),.load_failed(failed),
 .rtc_poll(poll),.time_server_ip(32'h0a000064),.utc_ntp(utc),.monotonic_ticks(mono),.rtc_locked(locked),
 .tx_valid(tv),.tx_ready(ready),.tx_length(tl),.tx_bytes(tb),.tx_destination_ip(tip),.tx_source_port(ts),.tx_destination_port(td),
 .rx_valid(rx),.rx_source_ip(rip),.rx_source_port(sp),.rx_destination_port(dp),.rx_length(plen),.rx_bytes(packet));
function [31:0] crcbyte;input [31:0] a;input [7:0] b;reg [31:0] x;integer t;begin x=a^b;for(t=0;t<8;t=t+1)x=x[0]?(x>>1)^32'hedb88320:x>>1;crcbyte=x;end endfunction
task fail;input [511:0] s;begin errors=errors+1;$display("FAIL JOINT %0s",s);end endtask
task take;input integer destport;integer t;begin
 t=0;while((!tv||td!=destport)&&t<3000)begin @(negedge clk);t=t+1;end
 if(t==3000)fail("outbound UDP missing");
 if(destport==123)begin origin=0;for(k=0;k<8;k=k+1)origin={origin[55:0],tb[(40+k)*8+:8]};end
 packets=packets+1;@(negedge clk);
end endtask
task data_packet;input integer block,n,offset;integer j;begin
 packet=0;packet[15:8]=3;packet[23:16]=block>>8;packet[31:24]=block;
 for(j=0;j<n;j=j+1)packet[(4+j)*8+:8]=((offset+j)*7+3)&255;
 rip=32'h0a000001;sp=30000;dp=40000;plen=n+4;rx=1;@(negedge clk);rx=0;
end endtask
initial begin
 c=32'hffffffff;for(i=0;i<700;i=i+1)c=crcbyte(c,(i*7+3)&255);expect_crc=~c;
 repeat(4)@(negedge clk);rst=0;init=1;@(negedge clk);init=0;repeat(2)@(negedge clk);
 request[3*8+:8]=23;request[4*8+:8]="A";request[5*8+:8]="4";request[7*8+:8]=1;request[8*8+:8]=8;request[9*8+:64]=64'h0048554c2e505041;request[17*8+:8]=5;request[18*8+:40]=40'h00312d4e50;
 lur=1;poll=1;ready=0;@(negedge clk);lur=0;poll=0;
 repeat(8)@(negedge clk);ready=1;
 take(123);take(69);data_packet(1,512,0);
 // Time synchronization reply while file bytes are being copied to staging RAM.
 repeat(10)@(negedge clk);packet=0;packet[7:0]=8'h24;packet[15:8]=1;
 for(k=0;k<8;k=k+1)begin packet[(24+k)*8+:8]=origin[63-k*8-:8];packet[(32+k)*8+:8]=(origin+64'h100000000)>>((7-k)*8);packet[(40+k)*8+:8]=(origin+64'h100000000)>>((7-k)*8);end
 rip=32'h0a000064;sp=123;dp=40001;plen=48;rx=1;@(negedge clk);rx=0;
 take(30000);data_packet(2,188,512);take(30000);repeat(8)@(negedge clk);
 if(!image_ok||!complete||failed||image_len!=700||image_crc!=expect_crc||!locked)fail("load/RTC joint result");
 for(i=0;i<700;i=i+1)begin ra=i;#1;if(rd!==((i*7+3)&255))fail("committed load image");end
 $display("JOINT_IMAGE_BYTES=%0d RTC_LOCKED=%b PACKETS=%0d ERRORS=%0d",image_len,locked,packets,errors);
 if(errors==0)$display("TB_CONTEST_LOAD_RTC_JOINT_PASS");else $display("TB_CONTEST_LOAD_RTC_JOINT_FAIL");$finish;
end
initial begin #100000;$display("LOAD_RTC_TIMEOUT");$finish;end
endmodule
