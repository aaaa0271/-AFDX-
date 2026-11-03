`timescale 1ns/1ps
module afdx_sec_events #(parameter integer DEPTH=32)(
 input wire clk,rst,push,input wire [159:0] record,
 output wire valid,input wire ready,output wire [159:0] data,output reg [31:0] lost
);
reg [159:0] mem[0:DEPTH-1];integer wp,rp,count;wire pop=valid&&ready;wire put=push&&(count<DEPTH||pop);
assign valid=count!=0;assign data=mem[rp];
always @(posedge clk)begin
 if(rst)begin wp<=0;rp<=0;count<=0;lost<=0;end else begin
  if(push&&!put)lost<=lost+1'b1;
  if(put)begin mem[wp]<=record;wp<=wp==DEPTH-1?0:wp+1;end
  if(pop)rp<=rp==DEPTH-1?0:rp+1;
  case({put,pop})2'b10:count<=count+1;2'b01:count<=count-1;default:count<=count;endcase
 end
end
endmodule
