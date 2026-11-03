`timescale 1ns/1ps
module tb_m6d_ber_boundaries;
reg clk=0;always #5 clk=~clk;reg rst_n=0,req=0;
reg [31:0] rid=0;reg [959:0] vb=0;reg [7:0] vl=9;
wire done,valid,small_done,small_valid;wire [7:0] err,len,small_err,small_len;
wire [1031:0] msg;wire [319:0] small_msg;
integer errors=0,cases=0,i,j,n,want,expected_err;reg [31:0] v;reg [7:0] first,next;
afdx_snmp_response_builder #(.MAX_VARBIND_BYTES(120),.MAX_MSG_BYTES(129)) dut(
.clk(clk),.rst_n(rst_n),.req(req),.request_id(rid),.varbind_data(vb),.varbind_length(vl),
.done(done),.valid(valid),.error_code(err),.msg_length(len),.msg_data(msg));
afdx_snmp_response_builder #(.MAX_VARBIND_BYTES(120),.MAX_MSG_BYTES(40)) small_dut(
.clk(clk),.rst_n(rst_n),.req(req),.request_id(rid),.varbind_data(vb),.varbind_length(vl),
.done(small_done),.valid(small_valid),.error_code(small_err),.msg_length(small_len),.msg_data(small_msg));

function [7:0] b;input integer k;begin b=msg[1031-k*8-:8];end endfunction
function integer minimum;input [31:0] x;reg [31:0] w;integer k;begin
 w=x;k=4;while(k>1 && ((w[31:24]==0 && w[23]==0)||(w[31:24]==255 && w[23]==1))) begin w=w<<8;k=k-1;end minimum=k;end endfunction
task fail;input [511:0] why;begin errors=errors+1;$display("FAIL rid=%h vl=%0d %0s",rid,vl,why);if(errors>8)$finish;end endtask
task test;input [31:0] value;input integer bytes;begin
 @(negedge clk);req=1;rid=value;vl=bytes;n=minimum(value);want=25+n+bytes;
 expected_err=(bytes==0||bytes>120)?1:((want-2>=128)?3:0);
 @(posedge clk);#1;cases=cases+1;
 if(!done || valid!==(expected_err==0) || err!==expected_err) fail("builder result");
 if(expected_err!=0) begin if(msg!==0||len!==0)fail("error response retained bytes");end
 else begin
  if(len!=want||b(1)!=want-2||b(14)!=want-15||b(16)!=n)fail("envelope/request-id lengths");
  if(b(15)!=2)fail("integer tag");
  for(j=0;j<n;j=j+1)if(b(17+j)!==((value>>((n-j-1)*8))&255))fail("signed INTEGER content");
  first=b(17);next=b(18);
  if(n>1 && ((first==0&&!next[7])||(first==255&&next[7])))fail("nonminimal signed INTEGER");
  if(b(23+n)!=48||b(24+n)!=bytes)fail("VarBindList offset");
  for(j=0;j<bytes;j=j+1)if(b(25+n+j)!==vb[959-j*8-:8])fail("VarBind preservation");
 end
 if(small_err!==((expected_err!=0)?expected_err:((want>40)?2:0)))fail("capacity error precedence");
 if((expected_err!=0||want>40) && (small_valid||small_len!=0||small_msg!=0))fail("small capacity fail closed");
 @(negedge clk);req=0;@(posedge clk);#1;if(done||small_done)fail("done pulse");
end endtask
initial begin
 for(i=0;i<120;i=i+1)vb[959-i*8-:8]=(i*7)^8'h5a;
 repeat(3)@(negedge clk);rst_n=1;
 for(i=-32768;i<=32767;i=i+1)test(i,9);
 test(32768,9);test(-32769,9);test(8388607,9);test(8388608,9);test(-8388608,9);test(-8388609,9);
 test(32'h7fffffff,9);test(32'h80000000,9);test(32'hffffffff,9);
 test(1,0);test(1,121);test(1,103);test(1,104);test(32'h12345678,100);test(32'h12345678,101);test(1,15);test(1,14);
 $display("BER_CASES=%0d ERRORS=%0d",cases,errors);
 if(errors==0)$display("M6D_BER_REPAIR_PASS");else $display("M6D_BER_REPAIR_FAIL");$finish;
end
initial begin #3000000;$display("M6D_BER_TIMEOUT");$finish;end
endmodule
