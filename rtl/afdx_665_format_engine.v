`timescale 1ns/1ps
// Metadata admission only, NOT a byte grammar or a normative conformance oracle.
// IDs/edition mapping: Thomas Vogt ARINC665 SDK Arinc665.hpp (snapshot in results).
// FILE_CLASS: 0 LUH, 1 batch, 2 media/list. 8002 is ambiguous across classes
// and its edition-1 body is not supported by this implementation.
// Counts are caller-supplied aggregate resource requirements; their semantic
// derivation must be validated by the corresponding byte parser. udd_count is
// a resource count, not an on-wire UDD record count (UDD is opaque).
module afdx_665_format_engine #(
 parameter integer MAX_HEADERS=8,MAX_TARGETS=8,MAX_PARTS=8,MAX_SUPPORT=8,MAX_UDD=8,
 parameter integer FILE_CLASS=0
)(
 input wire clk,input wire rst,input wire start,input wire [3:0] edition,
 input wire [15:0] format_id,input wire [3:0] header_count,input wire [3:0] target_count,
 input wire [3:0] part_count,input wire [3:0] support_count,input wire [3:0] udd_count,
 input wire header_crc_ok,file_crc_ok,load_crc_ok,reserved_zero,names_ok,duplicate_free,
 output reg done,accepted,output reg [7:0] error_code,output wire busy
);
 wire known_id = FILE_CLASS==0 ? (format_id==16'h8003 || format_id==16'h8004) :
                 FILE_CLASS==1 ? (format_id==16'h9003 || format_id==16'h9004) :
                 FILE_CLASS==2 ? (format_id==16'ha003 || format_id==16'ha004) : 1'b0;
 wire edition_match = (edition==2 && format_id[3:0]==3) ||
                      (edition>=3 && edition<=5 && format_id[3:0]==4);
 assign busy=start&&!done;
 always @(posedge clk) begin
  if(rst) begin done<=0;accepted<=0;error_code<=0;end
  else begin
   done<=0;accepted<=0;error_code<=0;
   if(start) begin
    done<=1;
    if(edition<2||edition>5) error_code<=8'h01;
    else if(!known_id) error_code<=8'h02;
    else if(!edition_match) error_code<=8'h05;
    else if(header_count>MAX_HEADERS||target_count>MAX_TARGETS||part_count>MAX_PARTS||
      (FILE_CLASS==0&&(header_count==0||target_count==0||part_count==0))) error_code<=8'h03;
    else if(support_count>MAX_SUPPORT||udd_count>MAX_UDD) error_code<=8'h04;
    else if(!header_crc_ok) error_code<=8'h10;
    else if(!file_crc_ok) error_code<=8'h11;
    else if(!load_crc_ok) error_code<=8'h12;
    else if(!reserved_zero) error_code<=8'h13;
    else if(!names_ok) error_code<=8'h14;
    else if(!duplicate_free) error_code<=8'h15;
    else accepted<=1;
   end
  end
 end
endmodule
