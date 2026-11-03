`timescale 1ns/1ps
module afdx_sec_replay #(parameter integer MAX_WIRE=1536)(
 input wire clk,rst,input wire start,input wire [MAX_WIRE*8-1:0] packet,input wire [10:0] length,
 output wire ready,output reg [7:0] data,output reg valid,error,output wire idle
);
reg [MAX_WIRE*8-1:0] buffer_q;reg [10:0] len,index;reg active;reg [3:0] gap;
assign ready=!active&&gap==0;assign idle=ready&&!valid;
always @(posedge clk)begin
 if(rst)begin buffer_q<=0;len<=0;index<=0;active<=0;gap<=0;data<=0;valid<=0;error<=0;end
 else begin
  valid<=0;error<=0;if(gap!=0)gap<=gap-1'b1;
  if(start&&ready)begin buffer_q<=packet;len<=length;index<=0;active<=length!=0;end
  if(active)begin data<=buffer_q[index*8+:8];valid<=1;
   if(index==len-1)begin active<=0;gap<=12;end else index<=index+1'b1;
  end
 end
end
endmodule
