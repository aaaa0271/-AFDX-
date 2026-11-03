`timescale 1ns/1ps
module tb_contest_tftp;
reg clk=0;always #5 clk=~clk;reg rst=1,start=0,get=1,ready=1,rx=0;
reg [15:0] putlen=0,rport=30000,raddr=0;reg [10:0] rlen=0;reg [4127:0] rb=0;reg [255:0] name=0;
wire tv,busy,done,err,fvalid;wire [10:0] tlen;wire [4127:0] tb;wire [31:0] dip,crc,retries,dups,rejs;
wire [15:0] sport,dport,flen,putaddr;wire [7:0] filedata;wire [7:0] putdata=(putaddr*7+3)&255;
integer errors=0,cases=0,i,j,n,t,base_retries,base_dups;reg [31:0] refcrc;
afdx_tftp_client #(.MAX_FILE_BYTES(2048),.TIMEOUT_CYCLES(800),.MAX_RETRIES(2)) dut(
.clk(clk),.rst(rst),.start(start),.read_not_write(get),.server_ip(32'h0a000001),.local_tid(16'd40000),.filename_length(6'd8),.filename(name),
.put_length(putlen),.put_address(putaddr),.put_data(putdata),.tx_valid(tv),.tx_ready(ready),.tx_length(tlen),.tx_bytes(tb),.tx_destination_ip(dip),.tx_source_port(sport),.tx_destination_port(dport),
.rx_valid(rx),.rx_source_ip(32'h0a000001),.rx_source_port(rport),.rx_destination_port(16'd40000),.rx_length(rlen),.rx_bytes(rb),
.busy(busy),.done(done),.error(err),.file_valid(fvalid),.file_length(flen),.file_crc(crc),.read_address(raddr),.read_data(filedata),.retries(retries),.duplicates(dups),.rejected(rejs));
task fail;input [511:0] why;begin errors=errors+1;$display("FAIL TFTP case=%0d %0s",cases,why);if(errors>8)$finish;end endtask
function [31:0] crcbyte;input [31:0] c;input [7:0] b;reg [31:0] x;integer k;begin x=c^b;for(k=0;k<8;k=k+1)x=x[0]?(x>>1)^32'hedb88320:x>>1;crcbyte=x;end endfunction
task wait_packet;input integer op,block,len;
 integer k;begin
 k=0;while(!tv&&k<5000)begin @(negedge clk);k=k+1;end
 if(!tv)fail("missing outgoing packet");
 if(tb[15:8]!=op||tlen!=len||sport!=40000||dip!=32'h0a000001)fail("packet header/length");
 if(op>=3 && {tb[23:16],tb[31:24]}!=block)fail("block number");
 @(negedge clk);
 end endtask
task begin_file;input readmode;input integer length;begin
 cases=cases+1;@(negedge clk);get=readmode;putlen=length;start=1;@(negedge clk);start=0;
 wait_packet(readmode?1:2,0,17);
end endtask
task send_data;input integer block,length,base;integer k;begin
 rb=0;rb[15:8]=3;rb[23:16]=block>>8;rb[31:24]=block;
 for(k=0;k<length;k=k+1)rb[(4+k)*8+:8]=(base+k*7)&255;
 rlen=4+length;@(negedge clk);rx=1;@(negedge clk);rx=0;
end endtask
task send_ack;input integer block;begin
 rb=0;rb[15:8]=4;rb[23:16]=block>>8;rb[31:24]=block;rlen=4;
 @(negedge clk);rx=1;@(negedge clk);rx=0;
end endtask
task verify_file;input integer length;integer k;begin
 if(!fvalid||err||flen!=length)fail("file commit/length");refcrc=32'hffffffff;
 for(k=0;k<length;k=k+1)begin raddr=k;#1;if(filedata!==((k*7+3)&255))fail("file bytes/order");refcrc=crcbyte(refcrc,(k*7+3)&255);end
 if(crc!==~refcrc)fail("independent file CRC32");
end endtask
task verify_put;input integer length;integer block,k,base,count;begin
 begin_file(0,length);send_ack(0);base=0;block=1;
 begin:put_loop
  for(t=0;t<8;t=t+1)begin
   count=length-base>=512?512:length-base;
   j=0;while(!tv&&j<1000)begin @(negedge clk);j=j+1;end
   if(!tv||tlen!=count+4||tb[15:8]!=3||{tb[23:16],tb[31:24]}!=block)fail("WRQ DATA block");
   for(k=0;k<count;k=k+1)if(tb[(4+k)*8+:8]!==(((base+k)*7+3)&255))fail("WRQ source bytes");
   @(negedge clk);send_ack(block);
   if(count<512)disable put_loop;
   base=base+count;block=block+1;
  end
 end
 if(busy||err)fail("WRQ completion");
end endtask
initial begin
 name[63:0]=64'h6e69622e6567616d; // "mage.bin", exact8-byte name sufficient for transport
 repeat(4)@(negedge clk);rst=0;
 begin_file(1,0);send_data(1,512,3);wait_packet(4,1,4);if(fvalid)fail("partial file exposed");
 base_dups=dups;send_data(1,512,3);wait_packet(4,1,4);if(dups!=base_dups+1)fail("duplicate DATA handling");
 rport=30001;send_data(2,1,3);wait_packet(5,5,5);rport=30000;
 send_data(2,188,(512*7+3)&255);wait_packet(4,2,4);verify_file(700);
 base_dups=dups;send_data(2,188,(512*7+3)&255);wait_packet(4,2,4);verify_file(700);if(dups!=base_dups+1)fail("final ACK dally");
 begin_file(1,0);send_data(1,512,3);wait_packet(4,1,4);send_data(2,0,0);wait_packet(4,2,4);verify_file(512);
 begin_file(1,0);send_data(1,0,0);wait_packet(4,1,4);verify_file(0);
 verify_put(700);verify_put(512);verify_put(0);
 begin_file(1,0);base_retries=retries;
 repeat(2500)@(negedge clk);if(busy||!err||retries!=base_retries+2)fail("bounded timeout retries");
 // New command after failure succeeds; no partial file leaks from prior session.
 begin_file(1,0);send_data(1,1,3);wait_packet(4,1,4);verify_file(1);
 // Overflow must invalidate the entire file, not return a partial image.
 begin_file(1,0);
 for(i=1;i<=4;i=i+1)begin send_data(i,512,((i-1)*512*7+3)&255);wait_packet(4,i,4);end
 send_data(5,1,3);repeat(3)@(negedge clk);if(!err||fvalid||busy)fail("oversized image fail closed");
 // Target ERROR aborts; a subsequent fresh request still succeeds.
 begin_file(1,0);rb=0;rb[15:8]=5;rb[31:24]=1;rlen=5;@(negedge clk);rx=1;@(negedge clk);rx=0;
 if(!err||busy||fvalid)fail("TFTP ERROR abort");
 begin_file(1,0);send_data(1,1,3);wait_packet(4,1,4);verify_file(1);
 $display("TFTP_CASES=%0d RETRIES=%0d DUPLICATES=%0d ERRORS=%0d",cases,retries,dups,errors);
 if(errors==0)$display("TB_CONTEST_TFTP_PASS");else $display("TB_CONTEST_TFTP_FAIL");$finish;
end
initial begin #200000;$display("TFTP_TEST_TIMEOUT");$finish;end
endmodule
