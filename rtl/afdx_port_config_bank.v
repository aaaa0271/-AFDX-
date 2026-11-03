`timescale 1ns/1ps
// Static communication-port/SAP port_table. Port number = {Sub-VL, VL}; thus
// exactly four independent Sub-VLs share each VL's BAG and sequence context.
// Entry: [0]enabled [1]sampling [2]SAP [3]UDP override [7:4]reserved,
// [23:8]SAP id [39:24]UDP source [55:40]UDP destination [63:56]reader/writer mask.
module afdx_port_config_bank #(parameter [3:0] SAMPLING_MASK=0)(
 input wire clk,rst,write,seal,input wire [3:0] index,input wire [63:0] entry,
 input wire [671:0] network_cfg,output reg [1023:0] port_table,
 output reg sealed,error
);
integer i;reg conflict;reg [15:0] other_src,other_dst,new_src,new_dst;
always @*begin
 conflict=0;other_src=0;other_dst=0;
 new_src=entry[3]?entry[39:24]:network_cfg[index[1:0]*168+120+:16];
 new_dst=entry[3]?entry[55:40]:network_cfg[index[1:0]*168+136+:16];
 for(i=0;i<16;i=i+1)begin
  other_src=port_table[i*64+3]?port_table[i*64+24+:16]:network_cfg[(i%4)*168+120+:16];
  other_dst=port_table[i*64+3]?port_table[i*64+40+:16]:network_cfg[(i%4)*168+136+:16];
  if(i!=index&&port_table[i*64]&&entry[0])begin
   if(i%4==index[1:0]&&other_src==new_src&&other_dst==new_dst)conflict=1;
   if(entry[2]&&port_table[i*64+2]&&entry[23:8]==port_table[i*64+8+:16])conflict=1;
  end
 end
end
always @(posedge clk)begin
 if(rst)begin port_table<=0;sealed<=0;error<=0;
  for(i=0;i<4;i=i+1)begin port_table[i*64]<=1;port_table[i*64+1]<=SAMPLING_MASK[i];port_table[i*64+56+:8]<=1;end
 end else begin
  error<=0;
  if(write)begin
   if(sealed||seal||entry[7:4]!=0||conflict||
     (entry[0]&&(entry[63:56]==0||(index>=4&&!entry[3])||(entry[2]&&(entry[1]||entry[23:8]==0))||
      (entry[3]&&(entry[39:24]==0||entry[55:40]==0)))))error<=1;
   else port_table[index*64+:64]<=entry;
  end
  if(seal&&!write)sealed<=1;
 end
end
endmodule