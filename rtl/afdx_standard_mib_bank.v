`timescale 1ns/1ps
// UNINTEGRATED EXPERIMENT: indexed placeholder values, NOT a standard MIB.
// These constants are not live telemetry, table instances, or implemented OIDs.
// This module's test must not count toward standard-object/wire conformance.
module afdx_standard_mib_bank #(
 parameter integer OBJECTS=64
)(
 input wire clk,input wire rst,input wire request_valid,input wire request_next,
 input wire [7:0] request_index,input wire set_request,input wire [31:0] set_value,
 output reg response_valid,output reg response_error,output reg [7:0] error_code,
 output reg [7:0] response_index,output reg [3:0] mib_group,output reg [7:0] object_subid,
 output reg [7:0] asn1_type,output reg [1:0] access_mode,output reg table_object,
 output reg index_required,output reg [31:0] value32
);
 localparam ERR_NONE=8'h00,ERR_NO_SUCH=8'h01,ERR_END=8'h02,ERR_NOT_WRITABLE=8'h03;
 integer idx; integer k;
 reg valid_c,table_c,index_c;reg [3:0] group_c;reg [7:0] subid_c,type_c;reg [1:0] access_c;reg [31:0] value_c;reg [7:0] selected;
 always @* begin
  selected=request_next?(request_index+1'b1):(request_index==0?8'd1:request_index);
  valid_c=(selected>=1&&selected<=OBJECTS);table_c=0;index_c=0;group_c=0;subid_c=0;type_c=8'h41;access_c=0;value_c=0;
  if(valid_c) begin
   // 1..7: RFC1213 system scalars
   if(selected<=7) begin group_c=1;subid_c=selected;access_c=(selected==4||selected==5||selected==6)?2:1;type_c=(selected==3)?8'h43:(selected==1||selected==4||selected==5||selected==6)?8'h04:(selected==2)?8'h06:8'h02;value_c={24'd0,selected};end
   // 8..28: ifTable (row index 1 is part of the standard instance)
   else if(selected<=28) begin group_c=2;subid_c=selected-7;table_c=1;index_c=1;access_c=(selected==14)?2:1;type_c=(selected==9)?8'h04:(selected==10)?8'h42:(selected==11||selected==12||selected==13||selected==14||selected==15||selected==16||selected==17||selected==18||selected==19||selected==20||selected==21)?8'h41:8'h02;value_c={24'd0,selected};end
   // 29..45: IP-MIB system/counter scalars
   else if(selected<=45) begin group_c=4;subid_c=selected-28;access_c=(selected==29)?2:1;type_c=(selected==29||selected==30)?8'h02:8'h41;value_c={24'd0,selected};end
   // 46..50: UDP-MIB
   else if(selected<=50) begin group_c=7;subid_c=selected-45;table_c=(selected==50);index_c=(selected==50);access_c=1;type_c=8'h41;value_c={24'd0,selected};end
   // 51..64: SNMPv2-MIB counters plus framework/USM summary
   else begin group_c=(selected<=60)?11:6;subid_c=selected-50;access_c=1;type_c=(selected==64)?8'h02:8'h41;value_c={24'd0,selected};end
  end
 end
 always @(posedge clk) begin
  if(rst) begin response_valid<=0;response_error<=0;error_code<=0;response_index<=0;mib_group<=0;object_subid<=0;asn1_type<=0;access_mode<=0;table_object<=0;index_required<=0;value32<=0;end
  else begin
   response_valid<=0;response_error<=0;error_code<=ERR_NONE;
   if(request_valid) begin
    response_valid<=1;response_index<=selected;mib_group<=group_c;object_subid<=subid_c;asn1_type<=type_c;access_mode<=access_c;table_object<=table_c;index_required<=index_c;value32<=value_c;
    if(!valid_c) begin response_error<=1;error_code<=request_next?ERR_END:ERR_NO_SUCH;end
    else if(set_request&&access_c!=2) begin response_error<=1;error_code<=ERR_NOT_WRITABLE;end
    else if(set_request) value32<=set_value;
   end
  end
 end
endmodule
