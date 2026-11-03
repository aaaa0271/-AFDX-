`timescale 1ns/1ps
// ERROR payload syntax from the published 615A implementation literature:
// RFC1350 opcode=5, error=0, "WAIT:<decimal seconds>\0" or
// "ABORT:<four hexadecimal status digits>\0". No private opcodes.
module afdx_615a_tftp_error(
 input wire [10:0] length,input wire [4127:0] bytes,
 output reg wait_message,abort_message,output reg [15:0] wait_seconds,abort_status
);
 integer i,v,d; reg good; reg [7:0] c;
 always @* begin
  wait_message=0;abort_message=0;wait_seconds=0;abort_status=0;v=0;d=0;c=0;good=1;
  if(length>=5&&length<=516&&bytes[31:0]==32'h00000500) begin
   if(length>=11&&length<=15&&bytes[32+:40]==40'h3a54494157) begin
    for(i=9;i<14;i=i+1)if(i<length-1)begin
     c=bytes[i*8+:8];if(c<"0"||c>"9")good=0;
     v=v*10+(c-"0");
    end
    if(good&&v<=65535&&bytes[(length-1)*8+:8]==0)begin wait_message=1;wait_seconds=v;end
   end
   if(length==15&&bytes[32+:48]==48'h3a54524f4241&&bytes[112+:8]==0)begin
    good=1;v=0;
    for(i=10;i<14;i=i+1)begin
     c=bytes[i*8+:8];d=0;
     if(c>="0"&&c<="9")d=c-"0";
     else if(c>="A"&&c<="F")d=c-"A"+10;
     else if(c>="a"&&c<="f")d=c-"a"+10;
     else good=0;
     v=v*16+d;
    end
    if(good)begin abort_message=1;abort_status=v;end
   end
  end
 end
endmodule
