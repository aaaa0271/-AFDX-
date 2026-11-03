`timescale 1ns/1ps
// Packet-level service integration. UDP/Ethernet adaptation remains a separate
// documented interface; LUI/LUR enter as complete files, LUS leaves as a file.
module afdx_load_rtc_services #(
 parameter integer CLK_HZ=100000000,
 parameter integer TFTP_TIMEOUT=100000000,
 parameter integer NTP_TIMEOUT=100000000
)(
 input wire clk,rst,
 input wire loader_initialize,output wire lui_valid,input wire lui_ready,output wire [79:0] lui_bytes,
 input wire lur_valid,input wire [15:0] lur_length,input wire [1023:0] lur_bytes,
 output wire lur_accept,lur_reject,
 output wire lus_valid,input wire lus_ready,output wire [7:0] lus_length,output wire [1023:0] lus_bytes,
 input wire [31:0] loader_ip,input wire [15:0] expected_image_length,input wire [31:0] expected_image_crc,
 output wire image_valid,output wire [15:0] image_length,output wire [31:0] image_crc,
 input wire [15:0] image_read_address,output wire [7:0] image_read_data,
 output wire loading,load_complete,load_failed,
 input wire rtc_poll,input wire [31:0] time_server_ip,output wire [63:0] utc_ntp,monotonic_ticks,output wire rtc_locked,
 output wire tx_valid,input wire tx_ready,output wire [10:0] tx_length,output wire [4127:0] tx_bytes,
 output wire [31:0] tx_destination_ip,output wire [15:0] tx_source_port,tx_destination_port,
 input wire rx_valid,input wire [31:0] rx_source_ip,input wire [15:0] rx_source_port,rx_destination_port,
 input wire [10:0] rx_length,input wire [4127:0] rx_bytes
);
wire fetch;wire [5:0] name_length;wire [255:0] name;reg fetch_pending;
wire [7:0] staged_read_data;
wire tf_busy,tf_valid,tf_done,tf_error,tf_file_valid;wire [15:0] tf_sport,tf_dport;wire [31:0] tf_ip;
wire [10:0] tf_len;wire [4127:0] tf_bytes;wire tf_ready;
wire validate;wire [15:0] validation_length;wire [31:0] validation_crc;wire [15:0] upload_status;
wire validation_ok=validation_length==expected_image_length&&validation_crc==expected_image_crc;
wire tf_start=fetch_pending&&!tf_busy&&!tf_valid;
wire nt_valid,nt_ready,nt_busy;
reg [31:0] time_peer_q;wire [383:0] nt_bytes;
reg [1:0] owner;reg last_owner;
assign tx_valid=owner==1?tf_valid:(owner==2?nt_valid:1'b0);
assign tx_length=owner==1?tf_len:11'd48;
assign tx_bytes=owner==1?tf_bytes:{3744'd0,nt_bytes};
assign tx_destination_ip=owner==1?tf_ip:time_peer_q;
assign tx_source_port=owner==1?tf_sport:16'd40001;
assign tx_destination_port=owner==1?tf_dport:16'd123;
assign tf_ready=owner==1&&tx_ready;
assign nt_ready=owner==2&&tx_ready;
assign image_valid=tf_file_valid&&load_complete&&!load_failed;
assign image_read_data=image_valid?staged_read_data:8'd0;
always @(posedge clk)begin
 if(rst)begin fetch_pending<=0;owner<=0;last_owner<=0;time_peer_q<=0;end
 else begin
  if(rtc_poll&&!nt_busy)time_peer_q<=time_server_ip;
  if(fetch)fetch_pending<=1;
  if(tf_start)fetch_pending<=0;
  if(owner==0)begin
   if(tf_valid&&nt_valid)owner<=last_owner?1:2;
   else if(tf_valid)owner<=1;else if(nt_valid)owner<=2;
  end else if(tx_valid&&tx_ready)begin last_owner<=owner==2;owner<=0;end
 end
end
afdx_615a_upload_control u_load(
 .clk(clk),.rst(rst),.initialize(loader_initialize),.init_valid(lui_valid),.init_ready(lui_ready),.init_bytes(lui_bytes),
 .lur_valid(lur_valid),.lur_length(lur_length),.lur_bytes(lur_bytes),.lur_accept(lur_accept),.lur_reject(lur_reject),
 .fetch_start(fetch),.filename_length(name_length),.filename(name),.transfer_done(tf_done),.transfer_error(tf_done&&tf_error),
 .transferred_length(image_length),.transferred_crc(image_crc),.validate_request(validate),.validate_length(validation_length),.validate_crc(validation_crc),
 .validation_done(validate),.validation_ok(validation_ok),.status_valid(lus_valid),.status_ready(lus_ready),.status_length(lus_length),.status_bytes(lus_bytes),
 .active(loading),.complete(load_complete),.failed(load_failed),.status_code(upload_status));
afdx_tftp_client #(.TIMEOUT_CYCLES(TFTP_TIMEOUT)) u_tftp(
 .clk(clk),.rst(rst),.start(tf_start),.read_not_write(1'b1),.server_ip(loader_ip),.local_tid(16'd40000),
 .filename_length(name_length),.filename(name),.put_length(16'd0),.put_address(),.put_data(8'd0),
 .tx_valid(tf_valid),.tx_ready(tf_ready),.tx_length(tf_len),.tx_bytes(tf_bytes),.tx_destination_ip(tf_ip),.tx_source_port(tf_sport),.tx_destination_port(tf_dport),
 .rx_valid(rx_valid&&rx_destination_port==40000),.rx_source_ip(rx_source_ip),.rx_source_port(rx_source_port),.rx_destination_port(rx_destination_port),.rx_length(rx_length),.rx_bytes(rx_bytes),
 .busy(tf_busy),.done(tf_done),.error(tf_error),.file_valid(tf_file_valid),.file_length(image_length),.file_crc(image_crc),
 .read_address(image_read_address),.read_data(staged_read_data),.retries(),.duplicates(),.rejected());
afdx_rtc_ntp #(.CLK_HZ(CLK_HZ),.RESPONSE_TIMEOUT(NTP_TIMEOUT)) u_rtc(
 .clk(clk),.rst(rst),.poll(rtc_poll),.server_ip(time_server_ip),.tx_valid(nt_valid),.tx_ready(nt_ready),.tx_bytes(nt_bytes),
 .rx_valid(rx_valid&&rx_destination_port==40001),.rx_source_ip(rx_source_ip),.rx_source_port(rx_source_port),.rx_length(rx_length>255?8'hff:rx_length[7:0]),.rx_bytes(rx_bytes[383:0]),
 .utc_ntp(utc_ntp),.monotonic_ticks(monotonic_ticks),.synchronized(rtc_locked),.sync_event(),.reject_event(),.timeout_event(),.last_offset(),.last_delay(),.sync_count(),.reject_count(),.timeout_count(),.busy(nt_busy));
endmodule
