`timescale 1ns/1ps
// Eight-port BYPASS comparison demo; protection is configured through
// AFDX_security_plugin_top, not through this fixed eight-port interface.
//
//   clk/reset : 12.5 MHz clock and active-high reset
//   tx_data   : transmit byte stream out of the end system
//   tx_valid  : transmit byte valid (GMII-style)
//   rx_data   : received byte stream into the end system
//   rx_valid  : received byte valid
//   tx_ready  : end system transmit channel ready
//   rx_ready  : external receiver ready (flow control / network enable)
//
// The single external byte stream feeds BOTH redundant A/B MAC inputs
// (identical frame copies), which exercises redundancy management and the
// shared RX demux. SNMP management, 615A loading and RTC traffic are
// separated internally by IP/UDP and leave through the A transmit port.
module AFDX_security_8port_top #(
 parameter integer CLK_HZ=12500000,DEMO_INTERVAL_CYCLES=1250000,
 parameter integer RTC_POLL_CYCLES=12500000,SERVICE_TIMEOUT_CYCLES=12500000,
 parameter [31:0] LOADER_IP=32'h0a000001,TIME_SERVER_IP=32'h0a000101
)(
 input  wire       clk,
 input  wire       reset,
 output wire [7:0] tx_data,
 input  wire [7:0] rx_data,
 output wire       tx_valid,
 input  wire       rx_valid,
 output wire       tx_ready,
 input  wire       rx_ready
);
 // Network enables follow external receiver readiness; the TX channel is
 // reported ready whenever the end system is out of reset.
 wire net_enable = rx_ready && !reset;

 wire [7:0]  a_txd, b_txd;
 wire        a_tx_en, b_tx_en, a_tx_er, b_tx_er, a_done, b_done;
 wire        payload_valid, payload_sof, payload_eof, payload_network;
 wire [7:0]  payload_data;
 wire cfg_write,cfg_seal,cfg_ready,cfg_error,app_en,app_accept,app_sof,app_eof,poll;
 wire [1:0] cfg_index,app_vl;wire [167:0] cfg_entry;wire [7:0] app_data,image_data;
 wire image_valid,rtc_locked,loading,load_failed;wire [15:0] image_length,image_address;
 assign tx_ready = cfg_ready && !cfg_error && !reset;
 afdx_demo_controller #(.CLK_HZ(CLK_HZ),.INTERVAL_CYCLES(DEMO_INTERVAL_CYCLES),.POLL_CYCLES(RTC_POLL_CYCLES)) demo(
  .clk(clk),.rst(reset),.cfg_ready(cfg_ready),.cfg_write(cfg_write),.cfg_seal(cfg_seal),.cfg_index(cfg_index),.cfg_entry(cfg_entry),
  .app_enable(app_en),.app_vl(app_vl),.app_data(app_data),.app_sof(app_sof),.app_eof(app_eof),.app_accept(app_accept),
  .payload_valid(payload_valid),.payload_data(payload_data),.rtc_poll(poll),.rtc_locked(rtc_locked),
  .image_valid(image_valid),.image_length(image_length),.image_data(image_data),.image_address(image_address),.loading(loading),.load_failed(load_failed));

 assign tx_data  = a_txd;
 assign tx_valid = a_tx_en;

 AFDX_security_plugin_top #(
  .SECURITY_BOOT_MODE(0),.SERVICE_DOMAINS(1),.CLK_HZ(CLK_HZ),.SERVICE_TIMEOUT_CYCLES(SERVICE_TIMEOUT_CYCLES)
 ) u_end_system (
  .cfg_port_write(1'b0), .cfg_port_index(4'd0), .cfg_port_entry(64'd0),
  .app_wr_subvl(2'd0), .app_read_subvl(2'd0), .app_wr_use_sap(1'b0),
  .app_wr_sap(16'd0), .app_wr_partition(3'd0), .app_read_partition(3'd0),
  .payload_port(), .payload_sap(), .app_access_error(),
  .cfg_rx_write(cfg_write), .cfg_rx_seal(cfg_seal), .cfg_rx_index(cfg_index), .cfg_rx_entry(cfg_entry),
  .cfg_rx_ready(cfg_ready), .cfg_rx_error(cfg_error),
  .clk(clk), .rst(reset),
  .tx_enable(net_enable), .network_a_enable(net_enable), .network_b_enable(net_enable),
  .cfg_we(cfg_write), .cfg_vl_id(cfg_index), .cfg_bag(CLK_HZ/1000), .cfg_destination(8'd0),
  .app_wr_en(app_en), .app_wr_vl_id(app_vl), .app_wr_data(app_data),
  .app_wr_len(16'd16), .app_wr_sof(app_sof), .app_wr_eof(app_eof),
  .cfg_lmax(16'd1518), .app_wr_ready(), .app_len_error(), .app_wr_accept(app_accept),
  .fault_enable(1'b0),
  .data_a_txd(a_txd), .data_b_txd(b_txd),
  .data_a_tx_en(a_tx_en), .data_b_tx_en(b_tx_en),
  .data_a_tx_er(a_tx_er), .data_b_tx_er(b_tx_er),
  .data_a_done(a_done), .data_b_done(b_done),
  .data_a_rxd(rx_data), .data_b_rxd(rx_data),
  .data_a_rx_dv(rx_valid), .data_b_rx_dv(rx_valid),
  .data_a_rx_er(1'b0), .data_b_rx_er(1'b0),
  .payload_data(payload_data), .payload_valid(payload_valid),
  .payload_sof(payload_sof), .payload_eof(payload_eof),
  .payload_network(payload_network), .payload_ready(1'b1),
  .app_read_request(1'b0), .app_read_port(2'd0), .app_read_ready(),
  .payload_length(), .payload_vl(), .payload_fresh(),
  .management_busy(), .snmp_snapshots(), .snmp_busy_drops(),
  .shared_rx_accepted(), .shared_rx_duplicates(), .shared_rx_dropped(),
  .shared_tx_overflows(), .physical_a_frames(), .physical_b_frames(),
  .loader_ip(LOADER_IP), .time_server_ip(TIME_SERVER_IP),
  .hardware_length(6'd3), .hardware_id({232'd0,24'h4d4953}),
  .app_file(2'd0),
  .rtc_poll(poll), .rtc_locked(rtc_locked), .utc_ntp(), .monotonic_ticks(),
  .image_valid(image_valid), .image_length(image_length), .image_crc(),
  .package_generation(), .package_file_count(),
  .image_read_address(image_address), .image_read_data(image_data),
  .loading(loading), .load_complete(), .load_failed(load_failed),
  .service_app_domain(1'b0),
  .service_loaded(), .service_clock_locked(),
  .service_cfg_we(1'b0), .service_cfg_domain(1'b0),
  .service_cfg_loader_ip(32'd0), .service_cfg_clock_ip(32'd0),
  .service_cfg_enable(1'b0), .service_cfg_commit(1'b0),
  .service_cfg_ready(), .service_cfg_error(), .service_cfg_pending(),
  .service_cfg_commit_pulse(), .service_enabled()
 );
endmodule

module afdx_demo_controller #(
 parameter integer CLK_HZ=12500000,INTERVAL_CYCLES=1250000,POLL_CYCLES=12500000
)(
 input wire clk,rst,cfg_ready,output wire cfg_write,cfg_seal,
 output wire [1:0] cfg_index,output wire [167:0] cfg_entry,
 output wire app_enable,output reg [1:0] app_vl,output wire [7:0] app_data,
 output wire app_sof,app_eof,input wire app_accept,
 input wire payload_valid,input wire [7:0] payload_data,
 output wire rtc_poll,input wire rtc_locked,image_valid,
 input wire [15:0] image_length,input wire [7:0] image_data,
 output reg [15:0] image_address,input wire loading,load_failed
);
reg [2:0] boot;reg active;reg [3:0] index;
reg [31:0] interval_left,poll_left,frames,received;
reg [7:0] last_rx;reg [127:0] message;
wire [47:0] mac=48'h030000000040+cfg_index;
wire [31:0] source_ip=32'h0a000020+cfg_index;
wire [15:0] source_port=16'd10000+cfg_index,destination_port=16'd20000+cfg_index;
assign cfg_write=!rst&&boot<4;
assign cfg_seal=!rst&&boot==4;
assign cfg_index=boot[1:0];
assign cfg_entry={16'd1518,destination_port,source_port,32'h0a000010,source_ip,mac,8'h03};
assign app_enable=active&&cfg_ready&&!rst;
assign app_data=message[index*8+:8];
assign app_sof=index==0;assign app_eof=index==15;
assign rtc_poll=cfg_ready&&poll_left==0&&!rst;
always @(posedge clk)begin
 if(rst)begin boot<=0;active<=0;index<=0;app_vl<=0;interval_left<=0;poll_left<=0;frames<=0;received<=0;last_rx<=0;message<=0;image_address<=0;end
 else begin
  if(boot<5)boot<=boot+1'b1;
  if(payload_valid)begin received<=received+1'b1;last_rx<=payload_data;end
  if(cfg_ready)begin
   if(poll_left==0)poll_left<=POLL_CYCLES>0?POLL_CYCLES-1:0;else poll_left<=poll_left-1'b1;
   if(interval_left!=0)interval_left<=interval_left-1'b1;
   if(!active&&interval_left==0)begin
    active<=1;index<=0;
    message<={image_length[7:0],image_data,last_rx,4'd0,load_failed,loading,image_valid,rtc_locked,received,frames,32'h58444641};
   end
   if(active&&app_accept)begin
    if(index==15)begin
     active<=0;frames<=frames+1'b1;app_vl<=app_vl+1'b1;interval_left<=INTERVAL_CYCLES>0?INTERVAL_CYCLES-1:0;
     if(image_valid&&image_length!=0&&image_address<image_length-1'b1)image_address<=image_address+1'b1;else image_address<=0;
    end else index<=index+1'b1;
   end
  end
 end
end
endmodule
