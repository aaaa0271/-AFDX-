`timescale 1ns/1ps
// Transactional software-part loader. Parses a real LUH, fetches every data
// and support file (in that order), verifies file CRC16 and cumulative load CRC32, then atomically swaps bank.
module afdx_665_package_loader #(
 parameter integer TIMEOUT_CYCLES=100000000,MAX_FILES=4,DEFER_COMMIT=0,CLK_HZ=TIMEOUT_CYCLES,
 parameter integer HEADER_EDITION=0,MAX_HEADER=2048,MAX_UDD_BYTES=2048,MAX_FILE_BYTES=4096,
 parameter integer ALLOW_RELATIVE_PATHS=0,LEGACY_8002=0,
 parameter [15:0] PART_FLAGS_ALLOWED=16'h0000
)(
 input wire commit_authorize,output reg prepared,
 input wire clk,rst,start,abort,input wire [31:0] server_ip,
 input wire [5:0] header_name_length,input wire [255:0] header_name,
 input wire [5:0] hardware_length,input wire [255:0] hardware_id,
 output wire tx_valid,input wire tx_ready,output wire [10:0] tx_length,output wire [4127:0] tx_bytes,
 output wire [31:0] tx_ip,output wire [15:0] tx_sport,tx_dport,
 input wire rx_valid,input wire [31:0] rx_ip,input wire [15:0] rx_sport,rx_dport,input wire [10:0] rx_length,input wire [4127:0] rx_bytes,
 output wire busy,output wire idle,output reg done,error,output reg [7:0] error_code,
 output reg package_valid,output reg [31:0] generation,package_crc,output reg [2:0] loaded_file_count,
 input wire [1:0] app_file,input wire [15:0] app_address,
 output wire [7:0] app_data,output wire [15:0] app_length,output wire [255:0] app_name,
 // Independent read-only port for a serialized download of the committed bank.
 input wire [1:0] download_file,input wire [15:0] download_address,
 output wire [7:0] download_data,output wire [15:0] download_length,output wire [255:0] download_name,
 output reg [2:0] active_file,
 output reg [MAX_FILES-1:0] loaded_support_mask,
 output wire waiting,output wire remote_abort,output wire [15:0] abort_status,
 output reg [31:0] measured_bytes,measured_retries,output reg [31:0] expected_bytes
);
localparam IDLE=0,GET_HEADER=1,WAIT_HEADER=2,PARSE=3,WAIT_PARSE=4,GET_DATA=5,WAIT_DATA=6,COPY=7,VERIFY=8,COMMIT=9,PREPARED=10;
reg [5:0] hardware_length_q;reg [255:0] hardware_id_q;
wire [15:0] h_format;wire [MAX_FILES-1:0] h_support_mask;
reg [MAX_FILES-1:0] support_mask_q;
reg [15:0] tid_counter;reg [31:0] peer_ip_q;
reg [3:0] state;reg tf_start,h_start,tf_reset;
reg [5:0] filename_length;reg [255:0] filename;
wire tf_busy,tf_idle,tf_done,tf_error,tf_valid;wire [15:0] tf_len;wire [31:0] tf_crc;reg [15:0] tf_address;wire [7:0] tf_data;
wire h_done,h_error;wire [7:0] h_code;wire [15:0] h_address;wire [2:0] h_files;wire [MAX_FILES*256-1:0] h_names;wire [MAX_FILES*6-1:0] h_name_lens;wire [MAX_FILES*16-1:0] h_lengths,h_crcs;wire [31:0] h_crc_state,h_expected;
reg [7:0] storage[0:32767];reg bank;reg [15:0] lengths[0:7];reg [255:0] names[0:7];reg [2:0] count_q;reg [31:0] load_crc,expected_crc;reg [15:0] file_crc,index;
// Storage geometry is 2 banks x MAX_FILES(4) x 4096 bytes; MAX_FILE_BYTES
// must not exceed 4096 without widening index/write_slot and this array.
wire [14:0] write_slot={!bank,active_file[1:0],index[11:0]};
wire [14:0] read_slot={bank,app_file,app_address[11:0]};
wire [2:0] app_slot={bank,app_file};
assign app_length=package_valid&&app_file<loaded_file_count?lengths[app_slot]:16'd0;
assign app_name=package_valid&&app_file<loaded_file_count?names[app_slot]:256'd0;
assign app_data=package_valid&&app_file<loaded_file_count&&app_address<app_length?storage[read_slot]:8'd0;
wire [2:0] download_slot={bank,download_file};
assign download_length=package_valid&&download_file<loaded_file_count?lengths[download_slot]:16'd0;
assign download_name=package_valid&&download_file<loaded_file_count?names[download_slot]:256'd0;
assign download_data=package_valid&&download_file<loaded_file_count&&download_address<download_length?
 storage[{bank,download_file,download_address[11:0]}]:8'd0;
assign busy=state!=IDLE;
assign idle=state==IDLE&&tf_idle&&!tx_valid;
function [15:0] c16;input [15:0] c;input [7:0] x;reg [15:0] t;integer k;begin t=c^{x,8'd0};for(k=0;k<8;k=k+1)t=t[15]?(t<<1)^16'h1021:t<<1;c16=t;end endfunction
function [31:0] c32;input [31:0] c;input [7:0] x;reg [31:0] t;integer k;begin t=c^{x,24'd0};for(k=0;k<8;k=k+1)t=t[31]?(t<<1)^32'h04c11db7:t<<1;c32=t;end endfunction
// Transport names are local policy: printable relative names, optional paths.
// Reject aliases (dot/dot-dot/empty segments) before issuing any RRQ.
function safe_name;input [255:0] value;input [5:0] size;
 integer n,seg,dots;reg [7:0] ch;begin
 safe_name=(size>0&&size<=31);seg=0;dots=0;
 for(n=0;n<32;n=n+1)if(n<size)begin
  ch=value[n*8+:8];
  if(ch<33||ch>126||ch==92||ch==58||ch==42||ch==63||ch==34||ch==60||ch==62||ch==124)safe_name=0;
  if(ch==47)begin
   if(!ALLOW_RELATIVE_PATHS||seg==0||(seg==dots&&seg<=2))safe_name=0;
   seg=0;dots=0;
  end else begin seg=seg+1;if(ch==46)dots=dots+1;end
 end
 if(seg==0||(seg==dots&&seg<=2))safe_name=0;
end endfunction
wire [15:0] read_mux=(state==PARSE||state==WAIT_PARSE)?h_address:tf_address;
wire [31:0] tf_retries;reg [31:0] retry_previous;integer telemetry_i;reg [31:0] expected_sum;
always @*begin
 expected_sum=0;for(telemetry_i=0;telemetry_i<MAX_FILES;telemetry_i=telemetry_i+1)if(telemetry_i<h_files)expected_sum=expected_sum+h_lengths[telemetry_i*16+:16];
end
always @(posedge clk)begin
 if(rst)begin measured_bytes<=0;measured_retries<=0;expected_bytes<=0;retry_previous<=0;end
 else begin
  if(tf_reset)retry_previous<=0;
  else begin if(tf_retries>=retry_previous)measured_retries<=measured_retries+tf_retries-retry_previous;retry_previous<=tf_retries;end
  if(start&&!busy)begin measured_bytes<=0;expected_bytes<=0;end
  if(state==WAIT_PARSE&&h_done&&!h_error)expected_bytes<=expected_sum;
  if(state==WAIT_DATA&&tf_done&&!tf_error)measured_bytes<=measured_bytes+tf_len;
 end
end
afdx_tftp_client #(.TIMEOUT_CYCLES(TIMEOUT_CYCLES),.CLK_HZ(CLK_HZ)) tftp(.clk(clk),.rst(rst||tf_reset),.start(tf_start),.read_not_write(1'b1),.server_ip(peer_ip_q),.local_tid(tid_counter),
.filename_length(filename_length),.filename(filename),.put_length(16'd0),.put_address(),.put_data(8'd0),
.tx_valid(tx_valid),.tx_ready(tx_ready),.tx_length(tx_length),.tx_bytes(tx_bytes),.tx_destination_ip(tx_ip),.tx_source_port(tx_sport),.tx_destination_port(tx_dport),
.rx_valid(rx_valid),.rx_source_ip(rx_ip),.rx_source_port(rx_sport),.rx_destination_port(rx_dport),.rx_length(rx_length),.rx_bytes(rx_bytes),
.wait_active(waiting),.remote_abort(remote_abort),.abort_status(abort_status),.error_code(),
.busy(tf_busy),.done(tf_done),.error(tf_error),.idle(tf_idle),.file_valid(tf_valid),.file_length(tf_len),.file_crc(tf_crc),.read_address(read_mux),.read_data(tf_data),.retries(tf_retries),.duplicates(),.rejected());
afdx_665_header #(.MAX_FILES(MAX_FILES),.MAX_HEADER(MAX_HEADER),.EDITION(HEADER_EDITION),
.MAX_FILE_BYTES(MAX_FILE_BYTES),
.MAX_UDD_BYTES(MAX_UDD_BYTES),.ALLOW_RELATIVE_PATHS(ALLOW_RELATIVE_PATHS),
.LEGACY_8002(LEGACY_8002),.PART_FLAGS_ALLOWED(PART_FLAGS_ALLOWED)) header(.clk(clk),.rst(rst||tf_reset),.start(h_start),.header_length(tf_len),.read_address(h_address),.read_data(tf_data),
.hardware_length(hardware_length_q),.hardware_id(hardware_id_q),.done(h_done),.error(h_error),.error_code(h_code),.file_count(h_files),.names(h_names),.name_lengths(h_name_lens),.file_lengths(h_lengths),.file_crcs(h_crcs),.load_crc_state(h_crc_state),.expected_load_crc(h_expected),.support_mask(h_support_mask),.format_version(h_format),
.udd_read_address(16'd0),.udd_read_data(),.data_file_count(),.support_file_count(),
.udd_address(),.udd_length(),.part_flags(),.load_type_id());
integer i;
task fail;input [7:0] code;begin error<=1;error_code<=code;done<=1;state<=IDLE;tf_reset<=1;prepared<=0;end endtask
always @(posedge clk)begin
 if(rst)begin hardware_length_q<=0;hardware_id_q<=0;loaded_support_mask<=0;support_mask_q<=0;prepared<=0;tid_counter<=16'd42000;peer_ip_q<=0;state<=IDLE;tf_start<=0;h_start<=0;tf_reset<=0;filename<=0;filename_length<=0;tf_address<=0;bank<=0;package_valid<=0;generation<=0;package_crc<=0;loaded_file_count<=0;done<=0;error<=0;error_code<=0;active_file<=0;load_crc<=0;expected_crc<=0;file_crc<=0;index<=0;count_q<=0;for(i=0;i<8;i=i+1)begin lengths[i]<=0;names[i]<=0;end end
 else begin
  tf_start<=0;h_start<=0;done<=0;tf_reset<=0;
  if(abort&&busy)fail(8'hf0);
  else case(state)
   IDLE:if(start)begin prepared<=0;peer_ip_q<=server_ip;error<=0;error_code<=0;filename<=header_name;filename_length<=header_name_length;hardware_length_q<=hardware_length;hardware_id_q<=hardware_id;
    if(MAX_FILES<1||MAX_FILES>4||MAX_HEADER>4096||!safe_name(header_name,header_name_length))fail(8'h85);
    else state<=GET_HEADER;end
   GET_HEADER:if(!tf_busy&&!tx_valid)begin tid_counter<=tid_counter==16'hffff ? 16'd42000:tid_counter+1'b1;tf_start<=1;state<=WAIT_HEADER;end
   WAIT_HEADER:if(tf_done)begin if(tf_error)fail(8'h80);else state<=PARSE;end
   PARSE:begin h_start<=1;state<=WAIT_PARSE;end
   WAIT_PARSE:if(h_done)begin
    if(h_error)fail(h_code);
    else if(h_files==0||h_files>MAX_FILES)fail(8'h86);
     else begin support_mask_q<=h_support_mask;count_q<=h_files;load_crc<=h_crc_state;expected_crc<=h_expected;active_file<=0;state<=GET_DATA;end
   end
   GET_DATA:if(!tf_busy&&!tx_valid)begin tid_counter<=tid_counter==16'hffff ? 16'd42000:tid_counter+1'b1;filename<=h_names[active_file*256+:256];filename_length<=h_name_lens[active_file*6+:6];tf_start<=1;state<=WAIT_DATA;end
   WAIT_DATA:if(tf_done)begin
    if(tf_error)fail(8'h81);
    else if(tf_len>MAX_FILE_BYTES || (tf_len!=h_lengths[active_file*16+:16] &&
       !(h_format!=16'h8004&&!support_mask_q[active_file]&&
         {1'b0,tf_len}+17'd1=={1'b0,h_lengths[active_file*16+:16]})))fail(8'h82);
    else begin index<=0;tf_address<=0;file_crc<=16'hffff;state<=tf_len==0?VERIFY:COPY;end
   end
   COPY:begin
    storage[write_slot]<=tf_data;file_crc<=c16(file_crc,tf_data);load_crc<=c32(load_crc,tf_data);
    if(index==tf_len-1)state<=VERIFY;else begin index<=index+1'b1;tf_address<=tf_address+1'b1;end
   end
   VERIFY:begin
    if(file_crc!=h_crcs[active_file*16+:16])fail(8'h83);
    else begin
     lengths[{!bank,active_file[1:0]}]<=tf_len;names[{!bank,active_file[1:0]}]<=filename;
     if(active_file+1==count_q)state<=COMMIT;else begin active_file<=active_file+1'b1;state<=GET_DATA;end
    end
   end
   COMMIT:begin
    if((~load_crc)!=expected_crc)fail(8'h84);
    else if(DEFER_COMMIT)begin prepared<=1;done<=1;state<=PREPARED;end
    else begin bank<=!bank;loaded_file_count<=count_q;loaded_support_mask<=support_mask_q;package_valid<=1;generation<=generation+1'b1;package_crc<=expected_crc;done<=1;state<=IDLE;end
   end
   PREPARED:if(commit_authorize)begin
    bank<=!bank;loaded_file_count<=count_q;loaded_support_mask<=support_mask_q;package_valid<=1;generation<=generation+1'b1;package_crc<=expected_crc;prepared<=0;state<=IDLE;
   end
  endcase
 end
end
endmodule

