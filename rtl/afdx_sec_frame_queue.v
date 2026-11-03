`timescale 1ns/1ps
// No input backpressure exists on the baseline GMII-byte interface.
// Each slot is a complete frame; overflow discards a whole input frame.
module afdx_sec_frame_queue #(parameter integer SLOTS=4,MAX_WIRE=1536)(
 input wire clk,rst,input wire [63:0] cycle,input wire [7:0] data,input wire valid,error,
 output wire request,output wire [MAX_WIRE*8-1:0] packet,
 output wire [10:0] length,output wire [63:0] stamp,output wire good,input wire take,
 output wire idle,output reg [31:0] overflows
);
reg [MAX_WIRE*8-1:0] slots[0:SLOTS-1];
reg [63:0] stamps[0:SLOTS-1];
reg [10:0] lens[0:SLOTS-1];reg goods[0:SLOTS-1];
integer wp,rp,used,i;reg previous,capturing,bad;reg [15:0] count;reg [31:0] crc;
wire finish=!valid&&previous;wire pop=take&&request;
wire push=finish&&capturing;
assign stamp=stamps[rp];assign request=used!=0;assign packet=slots[rp];assign length=lens[rp];assign good=goods[rp];
assign idle=used==0&&!valid&&!previous&&!capturing;
function [31:0] crcbyte;input [31:0] c;input [7:0] b;reg [31:0] x;integer k;begin x=c^b;for(k=0;k<8;k=k+1)x=x[0]?(x>>1)^32'hedb88320:x>>1;crcbyte=x;end endfunction
always @(posedge clk)begin
 if(rst)begin wp<=0;rp<=0;used<=0;previous<=0;capturing<=0;bad<=0;count<=0;crc<=32'hffffffff;overflows<=0;for(i=0;i<SLOTS;i=i+1)begin lens[i]<=0;goods[i]<=0;end end
 else begin
  previous<=valid;
  if(valid)begin
   if(!previous)begin
    capturing<=used<SLOTS;count<=1;crc<=32'hffffffff;bad<=error||data!=8'h55;
    if(used<SLOTS)begin stamps[wp]<=cycle;slots[wp]<=0;slots[wp][7:0]<=data;end else overflows<=overflows+1'b1;
   end else begin
    if(count<65535)count<=count+1'b1;
    if(capturing&&count<MAX_WIRE)slots[wp][count*8+:8]<=data;
    if(count>=8)crc<=crcbyte(crc,data);
    if(error||count>=MAX_WIRE||(count<7&&data!=8'h55)||(count==7&&data!=8'hd5))bad<=1;
   end
  end
  if(finish)begin
   capturing<=0;
   if(capturing)begin lens[wp]<=count>MAX_WIRE?MAX_WIRE:count;goods[wp]<=!bad&&count>=72&&count<=1526&&crc==32'hdebb20e3;wp<=wp==SLOTS-1?0:wp+1;end
  end
  if(pop)rp<=rp==SLOTS-1?0:rp+1;
  case({push,pop})2'b10:used<=used+1;2'b01:used<=used-1;default:used<=used;endcase
 end
end
endmodule
