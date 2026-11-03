`timescale 1ns/1ps
// Bounded LUH byte grammar: 8003 (665-2), 8004 (665-3/4/5).
// Source: SDK LoadHeaderFile/StringUtils/CheckValueUtils, pinned in results.
// Default rejects historical 8002 fixtures: those used a V2 prefix for a V1 ID.
// LEGACY_8002 is ONLY an opt-in migration profile, not edition-1 conformance.
// Existing outputs describe data files followed by support files, total <=7.
// Names/THW IDs <=31 bytes. UDD is opaque and retained in the header cache.
// Non-empty ARINC649 check values and THW-position constraints are explicitly
// unsupported (18); accepting them without verification would be unsafe.
module afdx_665_header #(
 parameter integer MAX_HEADER=2048,MAX_FILES=8,
 parameter integer EDITION=0,MAX_TARGETS=8,MAX_FILE_BYTES=4096,
 parameter integer MAX_UDD_BYTES=2048,MAX_TEXT_BYTES=255,
 parameter integer ALLOW_RELATIVE_PATHS=0,LEGACY_8002=0,
 parameter [15:0] PART_FLAGS_ALLOWED=16'h0000
)(
 input wire clk,rst,start,input wire [15:0] header_length,
 output reg [15:0] read_address,input wire [7:0] read_data,
 input wire [5:0] hardware_length,input wire [255:0] hardware_id,
 output reg done,error,output reg [7:0] error_code,output reg [2:0] file_count,
 output reg [MAX_FILES*256-1:0] names,output reg [MAX_FILES*6-1:0] name_lengths,
 output reg [MAX_FILES*16-1:0] file_lengths,file_crcs,
 output reg [31:0] load_crc_state,expected_load_crc,
 output reg [2:0] data_file_count,support_file_count,
 output reg [MAX_FILES-1:0] support_mask,
 output reg [15:0] udd_address,udd_length,format_version,part_flags,load_type_id,
 input wire [15:0] udd_read_address,output wire [7:0] udd_read_data
);
localparam IDLE=0,CACHE=1,HEADER=2,POINTERS=3,SECTION=4,STR_LEN=5,
 STR_BYTES=6,STR_DONE=7,HW_COUNT=8,FILE_COUNT=9,FILE_ENTRY=10,
 FILE_META=11,NEXT_SECTION=12,FINISH=13,TYPE_ID=14;
localparam R_PART=0,R_HW=1,R_NAME=2,R_FILEPN=3,R_TYPE=4;
reg [3:0] state,role;
reg [7:0] mem[0:MAX_HEADER-1];
reg [15:0] len,crc16,hw_len_q;
reg [255:0] hw_id_q,current_string,hw_names[0:MAX_TARGETS-1];
reg [31:0] crc32;
// Full-width arithmetic until pointers have passed bounds checks.
reg [31:0] pointers[0:7];
integer section_index,scan_index,ptr,section_end,str_len,str_index,str_end;
integer hw_count,hw_index,entry_count,entry_index,file_index,next_entry,entry_start;
integer segment_length,segment_dots;
reg hw_match,is_v3;
reg [15:0] version;
integer i,j,n;reg bad_pointers,duplicate_string;integer section_limit;
function [15:0] word16;input integer p;begin
 if(p>=0&&p+1<len&&p+1<MAX_HEADER)word16={mem[p],mem[p+1]};else word16=0;
end endfunction
function [31:0] word32;input integer p;begin word32={word16(p),word16(p+2)};end endfunction
function [15:0] c16;input [15:0] c;input [7:0] x;reg [15:0] t;integer k;begin t=c^{x,8'd0};for(k=0;k<8;k=k+1)t=t[15]?(t<<1)^16'h1021:t<<1;c16=t;end endfunction
function [31:0] c32;input [31:0] c;input [7:0] x;reg [31:0] t;integer k;begin t=c^{x,24'd0};for(k=0;k<8;k=k+1)t=t[31]?(t<<1)^32'h04c11db7:t<<1;c32=t;end endfunction
assign udd_read_data=(!error&&udd_read_address<udd_length&&udd_address+{1'b0,udd_read_address}<MAX_HEADER)?mem[udd_address+udd_read_address]:8'd0;
task clear_result;begin
 file_count<=0;data_file_count<=0;support_file_count<=0;support_mask<=0;
 names<=0;name_lengths<=0;file_lengths<=0;file_crcs<=0;
 udd_address<=0;udd_length<=0;load_crc_state<=0;expected_load_crc<=0;
 format_version<=0;part_flags<=0;load_type_id<=0;
end endtask
task fail;input [7:0] code;begin error<=1;error_code<=code;clear_result;state<=FINISH;end endtask
always @* begin
 bad_pointers=0;
 for(i=0;i<8;i=i+1)begin
  if(pointers[i]!=0)begin
   if(pointers[i]<(is_v3?20:14)||pointers[i]>=(len-6)/2)bad_pointers=1;
   for(j=0;j<8;j=j+1)if(j<i&&pointers[i]==pointers[j])bad_pointers=1;
  end
 end
 section_limit=len-6;
 for(i=0;i<8;i=i+1)
  if(pointers[i]>pointers[section_index]&&pointers[i]*2<section_limit) section_limit=pointers[i]*2;
 duplicate_string=0;
 for(i=0;i<MAX_FILES;i=i+1)
  if(role==R_NAME&&i<file_index&&names[i*256+:256]==current_string)duplicate_string=1;
 for(i=0;i<MAX_TARGETS;i=i+1)
  if(role==R_HW&&i<hw_index&&hw_names[i]==current_string)duplicate_string=1;
end
always @(posedge clk)begin
 if(rst)begin
  state<=IDLE;done<=0;error<=0;error_code<=0;read_address<=0;len<=0;
  crc16<=16'hffff;crc32<=32'hffffffff;ptr<=0;section_end<=0;
  section_index<=0;scan_index<=0;role<=0;str_len<=0;str_index<=0;str_end<=0;
  hw_count<=0;hw_index<=0;file_index<=0;entry_count<=0;entry_index<=0;
  next_entry<=0;entry_start<=0;hw_match<=0;hw_len_q<=0;hw_id_q<=0;
  segment_length<=0;segment_dots<=0;is_v3<=0;version<=0;current_string<=0;
  clear_result;
  for(n=0;n<8;n=n+1)pointers[n]<=0;
  for(n=0;n<MAX_TARGETS;n=n+1)hw_names[n]<=0;
 end else begin
  done<=0;
  case(state)
   IDLE:if(start)begin
    clear_result;len<=header_length;read_address<=0;error<=0;error_code<=0;
    crc16<=16'hffff;crc32<=32'hffffffff;hw_match<=0;hw_index<=0;file_index<=0;
    hw_len_q<=hardware_length;section_index<=0;
    for(n=0;n<32;n=n+1)hw_id_q[n*8+:8]<=n<hardware_length?hardware_id[n*8+:8]:0;
    if(MAX_FILES<1||MAX_FILES>8||MAX_HEADER>65535||MAX_FILE_BYTES>65535||
       MAX_TARGETS<1||header_length<40||header_length>MAX_HEADER||header_length[0])fail(1);
    else if(hardware_length==0||hardware_length>31)fail(6);
    else state<=CACHE;
   end
   CACHE:begin
    mem[read_address]<=read_data;
    if(read_address<len-6)crc16<=c16(crc16,read_data);
    if(read_address<len-4)crc32<=c32(crc32,read_data);
    if(read_address==len-1)state<=HEADER;else read_address<=read_address+1'b1;
   end
   HEADER:begin
    version<=word16(4);is_v3<=word16(4)==16'h8004;
    if(word32(0)!=(len>>1)||
       !(word16(4)==16'h8003||word16(4)==16'h8004||(LEGACY_8002&&word16(4)==16'h8002)))fail(2);
    else if(EDITION!=0&&!((EDITION==2&&word16(4)==16'h8003)||
       (EDITION>=3&&EDITION<=5&&word16(4)==16'h8004)))fail(2);
    else if(word16(4)==16'h8004&&len<48)fail(1);
    else if((word16(4)!=16'h8004&&word16(6)!=0)||
       (word16(4)==16'h8004&&(word16(6)&~PART_FLAGS_ALLOWED)!=0))fail(2);
    else if(word16(len-6)!=crc16)fail(3);
    else begin
     for(n=0;n<5;n=n+1)pointers[n]<=word32(8+4*n);
     for(n=5;n<8;n=n+1)pointers[n]<=word16(4)==16'h8004 ? word32(8+4*n):0;
     state<=POINTERS;
    end
   end
   POINTERS:begin
    if(bad_pointers||pointers[0]==0||pointers[1]==0||pointers[2]==0)fail(4);
    else if(pointers[6]!=0)fail(8'h18); // position constraints need a matching interface
    else if(pointers[4]!=0&&((pointers[7]!=0&&pointers[7]<=pointers[4])||
       pointers[4]<pointers[0]||pointers[4]<pointers[1]||pointers[4]<pointers[2]||
       pointers[4]<pointers[3]||pointers[4]<pointers[5]))fail(4);
    else begin section_index<=0;state<=SECTION;end
   end
   SECTION:begin
    ptr<=pointers[section_index]*2;section_end<=section_limit;
    case(section_index)
     0:begin role<=R_PART;state<=STR_LEN;end
     1:state<=HW_COUNT;
     2,3:if(pointers[section_index]==0)state<=NEXT_SECTION;else state<=FILE_COUNT;
     4:begin
      if(pointers[4]!=0)begin
       if(section_limit-pointers[4]*2>MAX_UDD_BYTES)fail(8'h19);
       else begin udd_address<=pointers[4]*2;udd_length<=section_limit-pointers[4]*2;state<=NEXT_SECTION;end
      end else state<=NEXT_SECTION;
     end
     5:if(pointers[5]!=0)begin role<=R_TYPE;state<=STR_LEN;end else state<=NEXT_SECTION;
     6:state<=NEXT_SECTION;
     7:begin
      if(pointers[7]!=0&&(word16(pointers[7]*2)!=0||pointers[7]*2+2!=len-6))fail(8'h18);
      else begin
       format_version<=version;part_flags<=is_v3?word16(6):0;
       load_crc_state<=crc32;expected_load_crc<=word32(len-4);state<=FINISH;
      end
     end
    endcase
   end
   STR_LEN:begin
    str_len<=word16(ptr);str_index<=0;current_string<=0;segment_length<=0;segment_dots<=0;
    str_end<=ptr+2+((word16(ptr)+1)&32'hfffffffe);
    if(ptr+2>section_end||ptr+2+((word16(ptr)+1)&32'hfffffffe)>section_end||
       ((role==R_NAME||role==R_HW)?(word16(ptr)==0||word16(ptr)>31):
        (word16(ptr)>MAX_TEXT_BYTES||(role==R_PART&&word16(ptr)==0))))fail(role==R_HW?7:10);
    else if((word16(ptr)&1)!=0&&mem[ptr+2+word16(ptr)]!=0)fail(8'h17);
    else begin ptr<=ptr+2;state<=word16(ptr)==0?STR_DONE:STR_BYTES;end
   end
   STR_BYTES:begin
    if(str_index<32)current_string[str_index*8+:8]<=mem[ptr+str_index];
    if(mem[ptr+str_index]<32||mem[ptr+str_index]>126)fail(11);
    else if(role==R_NAME&&(mem[ptr+str_index]==32||mem[ptr+str_index]==92||
       mem[ptr+str_index]==58||mem[ptr+str_index]==42||mem[ptr+str_index]==63||
       mem[ptr+str_index]==34||mem[ptr+str_index]==60||mem[ptr+str_index]==62||mem[ptr+str_index]==124))fail(11);
    else if(role==R_NAME&&mem[ptr+str_index]==47)begin
     if(!ALLOW_RELATIVE_PATHS||segment_length==0||
        (segment_length==segment_dots&&segment_length<=2)||str_index==str_len-1)fail(11);
     else begin segment_length<=0;segment_dots<=0;str_index<=str_index+1;end
    end else begin
     segment_length<=segment_length+1;
     if(mem[ptr+str_index]==46)segment_dots<=segment_dots+1;
     if(str_index==str_len-1)state<=STR_DONE;else str_index<=str_index+1;
    end
   end
   STR_DONE:begin
    ptr<=str_end;
    if(duplicate_string)fail(12);
    else case(role)
     R_PART:if(str_end!=section_end)fail(16);else state<=NEXT_SECTION;
     R_TYPE:state<=TYPE_ID;
     R_HW:begin
      hw_names[hw_index]<=current_string;
      if(str_len==hw_len_q&&current_string==hw_id_q)hw_match<=1;
      if(hw_index+1==hw_count)begin
       if(str_end!=section_end)fail(7);
       else if(!hw_match&&!(str_len==hw_len_q&&current_string==hw_id_q))fail(8);
       else state<=NEXT_SECTION;
      end else begin hw_index<=hw_index+1;state<=STR_LEN;end
     end
     R_NAME:begin
      if(segment_length==segment_dots&&segment_length<=2)fail(11);
      else begin names[file_index*256+:256]<=current_string;
       name_lengths[file_index*6+:6]<=str_len;role<=R_FILEPN;state<=STR_LEN;end
     end
     R_FILEPN:state<=FILE_META;
    endcase
   end
   TYPE_ID:begin
    if(ptr+2!=section_end)fail(16);
    else begin load_type_id<=word16(ptr);state<=NEXT_SECTION;end
   end
   HW_COUNT:begin
    if(ptr+2>section_end||word16(ptr)==0||word16(ptr)>MAX_TARGETS)fail(6);
    else begin hw_count<=word16(ptr);hw_index<=0;ptr<=ptr+2;role<=R_HW;state<=STR_LEN;end
   end
   FILE_COUNT:begin
    if(ptr+2>section_end||(section_index==2&&word16(ptr)==0)||word16(ptr)+file_index>MAX_FILES)fail(9);
    else begin
     entry_count<=word16(ptr);entry_index<=0;ptr<=ptr+2;
     if(section_index==2)data_file_count<=word16(ptr);else support_file_count<=word16(ptr);
     if(word16(ptr)==0)begin if(ptr+2!=section_end)fail(16);else state<=NEXT_SECTION;end
     else state<=FILE_ENTRY;
    end
   end
   FILE_ENTRY:begin
    if(ptr+4>section_end)fail(10);
    else if((entry_index+1==entry_count&&word16(ptr)!=0)||
       (entry_index+1<entry_count&&(word16(ptr)==0||ptr+word16(ptr)*2>=section_end)))fail(15);
    else begin entry_start<=ptr;next_entry<=ptr+word16(ptr)*2;ptr<=ptr+2;role<=R_NAME;state<=STR_LEN;end
   end
   FILE_META:begin
    // V3 data: word count + CRC16 + uint64 byte count + check value length.
    // Support: uint32 BYTE count + CRC16 (+ check value length in V3).
    if(ptr+(is_v3?(section_index==2?16:8):6)>section_end)fail(14);
    else if(word32(ptr)>MAX_FILE_BYTES||
       (section_index==2&&!is_v3&&word32(ptr)>MAX_FILE_BYTES/2))fail(13);
    else if(is_v3&&section_index==2&&(word32(ptr+6)!=0||word32(ptr+10)>MAX_FILE_BYTES||
       word32(ptr)!=(word32(ptr+10)+1)/2))fail(14);
    else if(is_v3&&word16(ptr+(section_index==2?14:6))!=0)fail(8'h18);
    else if(entry_index+1<entry_count&&next_entry!=ptr+(is_v3?(section_index==2?16:8):6))fail(15);
    else if(entry_index+1==entry_count&&ptr+(is_v3?(section_index==2?16:8):6)!=section_end)fail(16);
    else begin
     file_lengths[file_index*16+:16]<=section_index==3?word32(ptr):(is_v3?word32(ptr+10):word32(ptr)*2);
     file_crcs[file_index*16+:16]<=word16(ptr+4);support_mask[file_index]<=section_index==3;
     file_index<=file_index+1;file_count<=file_index+1;
     if(entry_index+1==entry_count)state<=NEXT_SECTION;
     else begin entry_index<=entry_index+1;ptr<=next_entry;state<=FILE_ENTRY;end
    end
   end
   NEXT_SECTION:begin section_index<=section_index+1;state<=SECTION;end
   FINISH:begin done<=1;state<=IDLE;end
   default:fail(8'hff);
  endcase
 end
end
endmodule
