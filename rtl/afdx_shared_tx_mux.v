`timescale 1ns/1ps
// Store-and-forward, frame-atomic A/B egress sharing for business, management
// and service MAC producers. Admission gates launches, never truncates a frame.
module afdx_shared_tx_mux #(parameter integer MANAGEMENT_BAG_CYCLES=1,SERVICE_BAG_CYCLES=1,REWRITE_SOURCE=0,EXTERNAL_ADMISSION=0,parameter [15:0] SOURCE_USER_ID=16'h0010)(
 input wire clk,rst,network_a_enable,network_b_enable,input wire tx_admit,
 input wire [127:0] business_bags,input wire [191:0] business_macs,
 input wire [7:0] business_a,business_b,input wire business_a_en,business_b_en,business_a_er,business_b_er,
 input wire [7:0] management_data,service_data,input wire management_en,service_en,management_er,service_er,
 output wire business_admit,management_admit,service_admit,
 output reg [7:0] a_data,b_data,output reg a_en,b_en,a_er,b_er,a_done,b_done,
 output reg [31:0] overflow_count,a_frames,b_frames
);
reg [7:0] memory[0:4607],business_b_memory[0:1535];
reg [10:0] c0a,c0b,c1,c2,len_a[0:2],len_b[0:2];
reg [2:0] pending,bad_a,bad_b;reg [1:0] mask[0:2];reg a_end,b_end,prev_a,prev_b,prev_m,prev_s;
reg sending;reg [1:0] owner,last;reg [10:0] index;reg [3:0] ifg;
reg [31:0] bag_left[0:5];reg [47:0] business_destination;reg [1:0] business_vl;
integer i,k;reg choose;reg [1:0] selected,probe;
always @*begin business_vl=0;for(k=0;k<4;k=k+1)if(business_destination==business_macs[k*48+:48])business_vl=k;end
wire any_enabled=network_a_enable||network_b_enable;
assign business_admit=!rst&&any_enabled&&c0a==0&&c0b==0&&!pending[0]&&!(sending&&owner==0);
assign management_admit=!rst&&any_enabled&&c1==0&&!pending[1]&&!(sending&&owner==1);
assign service_admit=!rst&&any_enabled&&c2==0&&!pending[2]&&!(sending&&owner==2);
wire [10:0] last_index=len_a[owner]>len_b[owner]?len_a[owner]-1'b1:len_b[owner]-1'b1;
always @*begin
 choose=0;selected=0;probe=0;
 for(i=1;i<=3;i=i+1)begin probe=(last+i)%3;if(!choose&&pending[probe]&&bag_left[probe==0?{1'b0,business_vl}:probe+3]==0)begin choose=1;selected=probe;end end
end
// Source Interface_ID occupies the upper3 bits of the last MAC octet.
// Recalculate FCS for the tagged copies, but preserve a corrupt producer FCS
// as corrupt: rewriting must never conceal the existing fault-injection path.
function [31:0] crcbyte;input [31:0] c;input [7:0] x;reg [31:0] v;integer n;begin v=c^x;for(n=0;n<8;n=n+1)v=v[0]?(v>>1)^32'hedb88320:v>>1;crcbyte=v;end endfunction
reg [31:0] input_crc_a,input_crc_b,input_crc_m,input_crc_s,output_crc_a,output_crc_b;
reg [2:0] input_bad_a,input_bad_b;
wire [7:0] raw_a=memory[owner*1536+index],raw_b=owner==0?business_b_memory[index]:raw_a;
reg [7:0] tagged_a,tagged_b,emit_a,emit_b;
always @*begin
 tagged_a=raw_a;tagged_b=raw_b;
 if(index>=14&&index<=19)case(index)
  14:begin tagged_a=2;tagged_b=2;end
  15,16:begin tagged_a=0;tagged_b=0;end
  17:begin tagged_a=SOURCE_USER_ID[15:8];tagged_b=SOURCE_USER_ID[15:8];end
  18:begin tagged_a=SOURCE_USER_ID[7:0];tagged_b=SOURCE_USER_ID[7:0];end
  19:begin tagged_a=8'h20;tagged_b=8'h40;end
 endcase
 emit_a=tagged_a;emit_b=tagged_b;
 if(index>=len_a[owner]-4)emit_a=(~output_crc_a)>>((index-(len_a[owner]-4))*8);
 if(index>=len_b[owner]-4)emit_b=(~output_crc_b)>>((index-(len_b[owner]-4))*8);
 if(index==len_a[owner]-4&&input_bad_a[owner])emit_a=emit_a^8'h01;
 if(index==len_b[owner]-4&&input_bad_b[owner])emit_b=emit_b^8'h01;
end
always @(posedge clk)begin
 if(rst)begin input_crc_a<=32'hffffffff;input_crc_b<=32'hffffffff;input_crc_m<=32'hffffffff;input_crc_s<=32'hffffffff;output_crc_a<=32'hffffffff;output_crc_b<=32'hffffffff;input_bad_a<=0;input_bad_b<=0;end
 else begin
  if(business_a_en)begin if(c0a==0)input_crc_a<=32'hffffffff;else if(c0a>=8)input_crc_a<=crcbyte(input_crc_a,business_a);end
  else if(prev_a)input_bad_a[0]<=input_crc_a!=32'hdebb20e3;
  if(business_b_en)begin if(c0b==0)input_crc_b<=32'hffffffff;else if(c0b>=8)input_crc_b<=crcbyte(input_crc_b,business_b);end
  else if(prev_b)input_bad_b[0]<=input_crc_b!=32'hdebb20e3;
  if(management_en)begin if(c1==0)input_crc_m<=32'hffffffff;else if(c1>=8)input_crc_m<=crcbyte(input_crc_m,management_data);end
  else if(prev_m)begin input_bad_a[1]<=input_crc_m!=32'hdebb20e3;input_bad_b[1]<=input_crc_m!=32'hdebb20e3;end
  if(service_en)begin if(c2==0)input_crc_s<=32'hffffffff;else if(c2>=8)input_crc_s<=crcbyte(input_crc_s,service_data);end
  else if(prev_s)begin input_bad_a[2]<=input_crc_s!=32'hdebb20e3;input_bad_b[2]<=input_crc_s!=32'hdebb20e3;end
  if(!sending&&ifg==0&&choose&&(!EXTERNAL_ADMISSION||tx_admit))begin output_crc_a<=32'hffffffff;output_crc_b<=32'hffffffff;end
  if(sending&&index>=8)begin
   if(index<len_a[owner]-4)output_crc_a<=crcbyte(output_crc_a,tagged_a);
   if(index<len_b[owner]-4)output_crc_b<=crcbyte(output_crc_b,tagged_b);
  end
 end
end
always @(posedge clk)begin
 if(rst)begin
  for(i=0;i<6;i=i+1)bag_left[i]<=0;business_destination<=0;
  c0a<=0;c0b<=0;c1<=0;c2<=0;pending<=0;bad_a<=0;bad_b<=0;a_end<=0;b_end<=0;prev_a<=0;prev_b<=0;prev_m<=0;prev_s<=0;
  sending<=0;owner<=0;last<=2;index<=0;ifg<=0;a_data<=0;b_data<=0;a_en<=0;b_en<=0;a_er<=0;b_er<=0;a_done<=0;b_done<=0;overflow_count<=0;a_frames<=0;b_frames<=0;
  for(i=0;i<3;i=i+1)begin len_a[i]<=0;len_b[i]<=0;mask[i]<=0;end
 end else begin
  a_en<=0;b_en<=0;a_er<=0;b_er<=0;a_done<=0;b_done<=0;
  for(i=0;i<6;i=i+1)if(bag_left[i]!=0)bag_left[i]<=bag_left[i]-1'b1;
  prev_a<=business_a_en;prev_b<=business_b_en;prev_m<=management_en;prev_s<=service_en;
  if((business_a_en||business_b_en)&&c0a==0&&c0b==0)begin mask[0]<={business_b_en,business_a_en};bad_a[0]<=0;bad_b[0]<=0;end
  if((business_a_en&&c0a>=8&&c0a<=13)||(!mask[0][0]&&business_b_en&&c0b>=8&&c0b<=13))
   business_destination<={business_destination[39:0],business_a_en?business_a:business_b};
  if(business_a_en)begin
   if(c0a<1536&&!pending[0]&&!(sending&&owner==0))begin memory[c0a]<=business_a;c0a<=c0a+1'b1;if(business_a_er)bad_a[0]<=1;end
   else overflow_count<=overflow_count+1'b1;
  end else if(prev_a)begin a_end<=1;len_a[0]<=c0a;end
  if(business_b_en)begin
   if(c0b<1536&&!pending[0]&&!(sending&&owner==0))begin business_b_memory[c0b]<=business_b;c0b<=c0b+1'b1;if(business_b_er)bad_b[0]<=1;end
   else overflow_count<=overflow_count+1'b1;
  end else if(prev_b)begin b_end<=1;len_b[0]<=c0b;end
  if((a_end||!mask[0][0])&&(b_end||!mask[0][1])&&mask[0]!=0&&!sending&&(c0a!=0||c0b!=0))pending[0]<=1;
  if(management_en)begin
   if(c1<1536&&!pending[1]&&!(sending&&owner==1))begin
    memory[1536+c1]<=management_data;c1<=c1+1'b1;
    if(c1==0)begin mask[1]<={network_b_enable,network_a_enable};bad_a[1]<=management_er;bad_b[1]<=management_er;end else if(management_er)begin bad_a[1]<=1;bad_b[1]<=1;end
   end else overflow_count<=overflow_count+1'b1;
  end else if(prev_m)begin pending[1]<=1;len_a[1]<=c1;len_b[1]<=c1;end
  if(service_en)begin
   if(c2<1536&&!pending[2]&&!(sending&&owner==2))begin
    memory[3072+c2]<=service_data;c2<=c2+1'b1;
    if(c2==0)begin mask[2]<={network_b_enable,network_a_enable};bad_a[2]<=service_er;bad_b[2]<=service_er;end else if(service_er)begin bad_a[2]<=1;bad_b[2]<=1;end
   end else overflow_count<=overflow_count+1'b1;
  end else if(prev_s)begin pending[2]<=1;len_a[2]<=c2;len_b[2]<=c2;end
  if(ifg!=0)ifg<=ifg-1'b1;
  if(!sending&&ifg==0&&choose&&(!EXTERNAL_ADMISSION||tx_admit))begin sending<=1;owner<=selected;last<=selected;index<=0;end
  if(sending)begin
   if(index==0)begin
    if(owner==0)bag_left[{1'b0,business_vl}]<=business_bags[business_vl*32+:32]>0?business_bags[business_vl*32+:32]-1'b1:0;
    else if(owner==1)bag_left[4]<=MANAGEMENT_BAG_CYCLES>0?MANAGEMENT_BAG_CYCLES-1:0;
    else bag_left[5]<=SERVICE_BAG_CYCLES>0?SERVICE_BAG_CYCLES-1:0;
   end
   if(mask[owner][0]&&index<len_a[owner])begin a_data<=REWRITE_SOURCE?emit_a:raw_a;a_en<=1;a_er<=bad_a[owner];if(index==len_a[owner]-1)begin a_done<=1;a_frames<=a_frames+1'b1;end end
   if(mask[owner][1]&&index<len_b[owner])begin b_data<=REWRITE_SOURCE?emit_b:raw_b;b_en<=1;b_er<=bad_b[owner];if(index==len_b[owner]-1)begin b_done<=1;b_frames<=b_frames+1'b1;end end
   if(index==last_index)begin
    sending<=0;pending[owner]<=0;ifg<=12;
    case(owner)0:begin c0a<=0;c0b<=0;a_end<=0;b_end<=0;mask[0]<=0;len_a[0]<=0;len_b[0]<=0;end 1:c1<=0;2:c2<=0;endcase
   end else index<=index+1'b1;
  end
 end
end
endmodule
