`timescale 1ns/1ps
// Startup configuration. Sealing prevents live traffic from changing its policy
// halfway through a frame. Reconfiguration requires reset/quiescence by system.
module afdx_rx_config_bank(
 input wire clk,rst,write,seal,input wire [1:0] index,
 input wire present,enabled,input wire [47:0] dst_mac,
 input wire [31:0] src_ip,dst_ip,input wire [15:0] src_port,dst_port,lmax,
 output reg [671:0] config_table,output reg sealed,output reg error
);
integer i;reg conflict;
always @* begin
 conflict=0;
 for(i=0;i<4;i=i+1) if(i!=index && config_table[i*168] && present && config_table[i*168+8+:48]==dst_mac)conflict=1;
end
always @(posedge clk)begin
 if(rst)begin config_table<=0;sealed<=0;error<=0;end
 else begin
  error<=0;
  if(write)begin
   if(sealed || seal || conflict || (present && (lmax<64 || lmax>1518)))error<=1;
   else config_table[index*168+:168]<={lmax,dst_port,src_port,dst_ip,src_ip,dst_mac,6'd0,enabled,present};
  end
  if(seal && !write)sealed<=1;
 end
end
endmodule
