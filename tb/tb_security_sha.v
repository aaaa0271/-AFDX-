`timescale 1ns/1ps
module tb_security_sha;
reg clk=0;always #5 clk=~clk;reg rst=1,start=0;reg [15:0] length=0;wire [15:0] address;wire busy,done;wire [255:0] digest;reg [7:0] bytes[0:4095];
reg [255:0] expected[0:13];reg [15:0] lengths[0:13];integer errors=0,i,j,cycles;
afdx_sec_sha256 dut(.clk(clk),.rst(rst),.start(start),.length(length),.address(address),.data(address<4096?bytes[address]:8'd0),.busy(busy),.done(done),.digest(digest));
initial begin
 $readmemh("sha_bytes.hex",bytes);$readmemh("sha_lengths.hex",lengths);$readmemh("sha_expected.hex",expected);
 repeat(4)@(negedge clk);rst=0;
 for(i=0;i<14;i=i+1)begin
  length=lengths[i];start=1;@(negedge clk);start=0;cycles=0;
  while(!done&&cycles<20000)begin @(negedge clk);cycles=cycles+1;end
  if(!done||digest!==expected[i])begin errors=errors+1;$display("SHA_FAIL case=%0d len=%0d got=%064x want=%064x",i,length,digest,expected[i]);end
  else $display("SHA_VECTOR_PASS case=%0d length=%0d digest=%064x",i,length,digest);
  @(negedge clk);
 end
 if(errors==0)$display("SEC_SHA_PASS");else $display("SEC_SHA_FAIL errors=%0d",errors);$finish;
end
endmodule
