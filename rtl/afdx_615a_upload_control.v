`timescale 1ns/1ps
// ARINC615A A4 bounded multiple-header upload-control profile. File transport is explicit:
// RRQ .LUI -> WRQ .LUR -> target RRQ load-header -> application validation -> .LUS.
// It does NOT interpret ARINC665 packages or replace application validation.
module afdx_615a_upload_control #(
 parameter integer STATUS_PERIOD=1000000, parameter integer VALIDATION_TIMEOUT=100000000,
 parameter integer MAX_HEADERS=4,TRANSFER_TIMEOUT=400000000
)(
 input wire clk,rst,initialize,
 output reg init_valid,input wire init_ready,output reg [79:0] init_bytes,
 input wire lur_valid,input wire [15:0] lur_length,input wire [1023:0] lur_bytes,
 output reg lur_accept,lur_reject,
 output reg fetch_start,output reg [5:0] filename_length,output reg [255:0] filename,
 input wire transfer_done,transfer_error,input wire [15:0] transferred_length,input wire [31:0] transferred_crc,
 output reg validate_request,output reg [15:0] validate_length,output reg [31:0] validate_crc,
 input wire validation_done,validation_ok,
 output reg status_valid,input wire status_ready,output reg [7:0] status_length,output reg [1023:0] status_bytes,
 output reg active,complete,failed,output reg [15:0] status_code,
 input wire abort_request,input wire [15:0] abort_reason,
 output reg [2:0] selected_header,output reg [2:0] header_count,
 output wire idle
);
localparam WAIT_INIT=0,READY=1,FETCH=2,VALIDATE=3,FINISHED=4;
reg [2:0] state;reg [31:0] age,status_timer;reg [15:0] report_counter;
reg [5:0] part_length;reg [255:0] part_number;
reg [5:0] name_lengths[0:MAX_HEADERS-1],part_lengths[0:MAX_HEADERS-1];
reg [255:0] names[0:MAX_HEADERS-1],parts[0:MAX_HEADERS-1];
reg [15:0] header_status[0:MAX_HEADERS-1];
reg [5:0] parsed_n[0:MAX_HEADERS-1],parsed_pn[0:MAX_HEADERS-1];
reg [255:0] parsed_name[0:MAX_HEADERS-1],parsed_part[0:MAX_HEADERS-1];
reg valid_file;integer count,pos,n,pn,i,k,total_report;
function [7:0] b;input [1023:0] packet;input integer index;begin
 b=(index>=0&&index<128)?packet[index*8+:8]:8'd0;
end endfunction
assign idle=state==WAIT_INIT&&!active&&!init_valid&&!status_valid;
always @*begin
 count={b(lur_bytes,6),b(lur_bytes,7)};pos=8;total_report=21;n=0;pn=0;
 valid_file=lur_length>=12&&lur_length<=128&&
  {b(lur_bytes,0),b(lur_bytes,1),b(lur_bytes,2),b(lur_bytes,3)}==lur_length&&
  b(lur_bytes,4)=="A"&&b(lur_bytes,5)=="4"&&count>0&&count<=MAX_HEADERS;
 for(i=0;i<MAX_HEADERS;i=i+1)begin
  parsed_n[i]=0;parsed_pn[i]=0;parsed_name[i]=0;parsed_part[i]=0;
  if(i<count)begin
   n=b(lur_bytes,pos);pos=pos+1;
   if(n<2||n>32||pos+n>lur_length||b(lur_bytes,pos+n-1)!=0)valid_file=0;
   for(k=0;k<31;k=k+1)if(k<n-1)begin
    parsed_name[i][k*8+:8]=b(lur_bytes,pos+k);
    if(b(lur_bytes,pos+k)==0||b(lur_bytes,pos+k)>127)valid_file=0;
   end
   parsed_n[i]=n-1;pos=pos+n;pn=b(lur_bytes,pos);pos=pos+1;
   if(pn<2||pn>32||pos+pn>lur_length||b(lur_bytes,pos+pn-1)!=0)valid_file=0;
   for(k=0;k<31;k=k+1)if(k<pn-1)begin
    parsed_part[i][k*8+:8]=b(lur_bytes,pos+k);
    if(b(lur_bytes,pos+k)==0||b(lur_bytes,pos+k)>127)valid_file=0;
   end
   parsed_pn[i]=pn-1;pos=pos+pn;total_report=total_report+9+n+pn;
  end
 end
 if(pos!=lur_length||total_report>128)valid_file=0;
 for(i=0;i<MAX_HEADERS;i=i+1)for(k=0;k<i;k=k+1)
  if(i<count&&parsed_name[i]==parsed_name[k])valid_file=0;
end
reg [1023:0] report;reg [7:0] report_length;integer j,r,q,progress;
always @*begin
 report=0;r=21;progress=0;
 report[32+:8]="A";report[40+:8]="4";
 report[48+:8]=status_code[15:8];report[56+:8]=status_code[7:0];report[64+:8]=1;
 report[80+:8]=report_counter[15:8];report[88+:8]=report_counter[7:0];
 if(complete)progress=100;else if(header_count!=0)progress=(selected_header*100)/header_count;
 report[128+:8]="0"+progress/100;report[136+:8]="0"+(progress/10)%10;report[144+:8]="0"+progress%10;
 report[160+:8]=header_count;
 for(j=0;j<MAX_HEADERS;j=j+1)if(j<header_count)begin
  report[r*8+:8]=name_lengths[j]+1;r=r+1;
  for(q=0;q<31;q=q+1)if(q<name_lengths[j])report[(r+q)*8+:8]=names[j][q*8+:8];
  r=r+name_lengths[j]+1;report[r*8+:8]=part_lengths[j]+1;r=r+1;
  for(q=0;q<31;q=q+1)if(q<part_lengths[j])report[(r+q)*8+:8]=parts[j][q*8+:8];
  r=r+part_lengths[j]+1;
  report[r*8+:8]=(header_status[j]==3)?"1":"0";
  report[(r+1)*8+:8]="0";report[(r+2)*8+:8]="0";
  report[(r+3)*8+:8]=header_status[j][15:8];report[(r+4)*8+:8]=header_status[j][7:0];
  report[(r+5)*8+:8]=1;r=r+7;
 end
 report_length=r;report[24+:8]=r;
end
integer j_copy;
task publish_status;
 begin status_bytes<=report;status_length<=report_length;status_valid<=1;
  report_counter<=report_counter+1'b1;status_timer<=0;
 end
endtask
always @(posedge clk)begin
 if(rst)begin
  selected_header<=0;header_count<=0;
  for(j_copy=0;j_copy<MAX_HEADERS;j_copy=j_copy+1)begin names[j_copy]<=0;parts[j_copy]<=0;name_lengths[j_copy]<=0;part_lengths[j_copy]<=0;header_status[j_copy]<=0;end
  state<=WAIT_INIT;age<=0;status_timer<=0;report_counter<=0;part_length<=0;part_number<=0;
  init_valid<=0;init_bytes<=0;lur_accept<=0;lur_reject<=0;fetch_start<=0;filename_length<=0;filename<=0;
  validate_request<=0;validate_length<=0;validate_crc<=0;status_valid<=0;status_length<=0;status_bytes<=0;
  active<=0;complete<=0;failed<=0;status_code<=0;
 end else begin
  lur_accept<=0;lur_reject<=0;fetch_start<=0;validate_request<=0;
  if(init_valid&&init_ready)init_valid<=0;
  if(status_valid&&status_ready)status_valid<=0;
  if(initialize&&!active&&!status_valid)begin
   init_bytes<=80'h0001010034410a000000; // len10,A4,status0001,description length1,NUL
   init_valid<=1;state<=READY;complete<=0;failed<=0;status_code<=1;
  end
  if(lur_valid)begin
   if(state==READY&&valid_file&&!status_valid&&!init_valid)begin
    lur_accept<=1;selected_header<=0;header_count<=count;
    filename<=parsed_name[0];part_number<=parsed_part[0];filename_length<=parsed_n[0];part_length<=parsed_pn[0];
    for(j_copy=0;j_copy<MAX_HEADERS;j_copy=j_copy+1)begin
     names[j_copy]<=parsed_name[j_copy];parts[j_copy]<=parsed_part[j_copy];
     name_lengths[j_copy]<=parsed_n[j_copy];part_lengths[j_copy]<=parsed_pn[j_copy];
     header_status[j_copy]<=j_copy==0?16'd2:16'd1;
    end
    active<=1;complete<=0;failed<=0;status_code<=2;age<=0;status_timer<=STATUS_PERIOD;state<=FETCH;
    fetch_start<=1;
   end else lur_reject<=1;
  end
  if(active&&!(abort_request===1'b1))begin
   status_timer<=status_timer+1'b1;age<=age+1'b1;
   if(status_timer>=STATUS_PERIOD&&!status_valid)publish_status;
   if((state==FETCH&&transfer_done)||(state==FETCH&&transfer_error))begin
    if(transfer_error)begin header_status[selected_header]<=16'h1003;active<=0;failed<=1;status_code<=16'h1003;state<=FINISHED;end
    else begin validate_request<=1;validate_length<=transferred_length;validate_crc<=transferred_crc;age<=0;state<=VALIDATE;end
   end
   if(state==VALIDATE)begin
    if(validation_done)begin
     header_status[selected_header]<=validation_ok?16'h0003:16'h1003;
     if(validation_ok&&selected_header+1<header_count)begin
      selected_header<=selected_header+1'b1;filename<=names[selected_header+1'b1];
      filename_length<=name_lengths[selected_header+1'b1];part_number<=parts[selected_header+1'b1];
      part_length<=part_lengths[selected_header+1'b1];header_status[selected_header+1'b1]<=2;
      fetch_start<=1;age<=0;state<=FETCH;
     end else begin
      active<=0;complete<=validation_ok;failed<=!validation_ok;status_code<=validation_ok?16'h0003:16'h1003;state<=FINISHED;
     end
    end else if(age>=VALIDATION_TIMEOUT)begin header_status[selected_header]<=16'h1003;active<=0;failed<=1;status_code<=16'h1003;state<=FINISHED;end
   end
  end
  if(active&&state==FETCH&&age>=TRANSFER_TIMEOUT)begin
   active<=0;failed<=1;complete<=0;status_code<=16'h1003;header_status[selected_header]<=16'h1003;state<=FINISHED;
  end
  if(abort_request===1'b1&&active)begin
   active<=0;complete<=0;failed<=1;state<=FINISHED;
   // Abort reason is the wire status, not an invented project opcode.
   status_code<=abort_reason;header_status[selected_header]<=abort_reason;
  end
  if(state==FINISHED&&!status_valid)begin publish_status;state<=WAIT_INIT;end
 end
end
endmodule
