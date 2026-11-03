`timescale 1ns/1ps
// Simulation-only competition top. All protocol traffic crosses MAC byte
// interfaces; image/clock readouts are the application-side result interfaces.
module AFDX_basic_top #(
 parameter integer CLK_HZ=100000000,MANAGEMENT_BAG_CYCLES=400000,
 parameter integer RX_SKEW_MAX_CYCLES=16000000,SERVICE_BAG_CYCLES=100000,
 parameter integer SERVICE_TIMEOUT_CYCLES=100000000
)(
    input wire cfg_rx_write,cfg_rx_seal,input wire [1:0] cfg_rx_index,input wire [167:0] cfg_rx_entry,
    output wire cfg_rx_ready,cfg_rx_error,
    input wire clk, rst,
    input wire tx_enable, network_a_enable, network_b_enable,
    input wire cfg_we,
    input wire [1:0] cfg_vl_id,
    input wire [31:0] cfg_bag,
    input wire [7:0] cfg_destination,
    input wire app_wr_en,
    input wire [1:0] app_wr_vl_id,
    input wire [7:0] app_wr_data,
    input wire [15:0] app_wr_len,
    input wire app_wr_sof, app_wr_eof,
    input wire [15:0] cfg_lmax,
    output wire app_wr_ready, app_len_error,
    output wire app_wr_accept,
    input wire fault_enable,
    output wire [7:0] data_a_txd, data_b_txd,
    output wire data_a_tx_en, data_b_tx_en, data_a_tx_er, data_b_tx_er,
    output wire data_a_done, data_b_done,
    input wire [7:0] data_a_rxd, data_b_rxd,
    input wire data_a_rx_dv, data_b_rx_dv, data_a_rx_er, data_b_rx_er,
    output wire [7:0] payload_data,
    output wire payload_valid, payload_sof, payload_eof, payload_network,
    input wire payload_ready,
    input wire [7:0] management_rxd,
    input wire management_rx_dv, management_rx_er,
    output wire [7:0] management_txd,
    output wire management_tx_en, management_tx_er, management_done,
    output wire management_busy, management_commit,
    output wire management_response_done, management_response_error,
    output wire [7:0] management_error_code,

 input wire [7:0] service_rxd,input wire service_rx_dv,service_rx_er,
 output wire [7:0] service_txd,output wire service_tx_en,service_tx_er,service_tx_done,
 input wire [31:0] loader_ip,time_server_ip,input wire [5:0] hardware_length,input wire [255:0] hardware_id,
 input wire [1:0] app_file,
 input wire rtc_poll,output wire rtc_locked,output wire [63:0] utc_ntp,monotonic_ticks,
 output wire image_valid,output wire [15:0] image_length,output wire [31:0] image_crc,
 output wire [31:0] package_generation,output wire [2:0] package_file_count,
 input wire [15:0] image_read_address,output wire [7:0] image_read_data,
 output wire loading,load_complete,load_failed
);
wire [671:0] rx_cfg_table;
afdx_rx_config_bank u_rx_configuration(.clk(clk),.rst(rst),.write(cfg_rx_write),.seal(cfg_rx_seal),.index(cfg_rx_index),
.present(cfg_rx_entry[0]),.enabled(cfg_rx_entry[1]),.dst_mac(cfg_rx_entry[55:8]),.src_ip(cfg_rx_entry[87:56]),.dst_ip(cfg_rx_entry[119:88]),
.src_port(cfg_rx_entry[135:120]),.dst_port(cfg_rx_entry[151:136]),.lmax(cfg_rx_entry[167:152]),.config_table(rx_cfg_table),.sealed(cfg_rx_ready),.error(cfg_rx_error));
afdx_m6f_system_top #(.CLK_HZ(CLK_HZ),.MANAGEMENT_BAG_CYCLES(MANAGEMENT_BAG_CYCLES),.RX_SKEW_MAX_CYCLES(RX_SKEW_MAX_CYCLES),.RX_CONFIGURABLE(1)) u_core(
 .mib_live(),
.rx_cfg_table(rx_cfg_table),
.clk(clk),
.rst(rst),
.tx_enable(tx_enable && cfg_rx_ready),
.network_a_enable(network_a_enable),
.network_b_enable(network_b_enable),
.cfg_we(cfg_we),
.cfg_vl_id(cfg_vl_id),
.cfg_bag(cfg_bag),
.cfg_destination(cfg_destination),
.app_wr_en(app_wr_en),
.app_wr_vl_id(app_wr_vl_id),
.app_wr_data(app_wr_data),
.app_wr_len(app_wr_len),
.app_wr_sof(app_wr_sof),
.app_wr_eof(app_wr_eof),
.cfg_lmax(cfg_lmax),
.app_wr_ready(app_wr_ready),
.app_len_error(app_len_error),
.app_wr_accept(app_wr_accept),
.fault_enable(fault_enable),
.data_a_txd(data_a_txd),
.data_b_txd(data_b_txd),
.data_a_tx_en(data_a_tx_en),
.data_b_tx_en(data_b_tx_en),
.data_a_tx_er(data_a_tx_er),
.data_b_tx_er(data_b_tx_er),
.data_a_done(data_a_done),
.data_b_done(data_b_done),
.data_a_rxd(data_a_rxd),
.data_b_rxd(data_b_rxd),
.data_a_rx_dv(data_a_rx_dv),
.data_b_rx_dv(data_b_rx_dv),
.data_a_rx_er(data_a_rx_er),
.data_b_rx_er(data_b_rx_er),
.payload_data(payload_data),
.payload_valid(payload_valid),
.payload_sof(payload_sof),
.payload_eof(payload_eof),
.payload_network(payload_network),
.payload_ready(payload_ready),
.management_rxd(management_rxd),
.management_rx_dv(management_rx_dv),
.management_rx_er(management_rx_er),
.management_txd(management_txd),
.management_tx_en(management_tx_en),
.management_tx_er(management_tx_er),
.management_done(management_done),
.management_busy(management_busy),
.management_commit(management_commit),
.management_response_done(management_response_done),
.management_response_error(management_response_error),
.management_error_code(management_error_code));
wire rxv,txv,txr;wire [31:0] rip,tip;wire [15:0] rsp,rdp,tsp,tdp;wire [10:0] rlen,tlen;wire [4127:0] rb,tb;
wire departure_valid;wire [63:0] departure_time,departure_origin,arrival_time;wire [31:0] departure_ip;
afdx_ntp_tx_timestamp departure(.clk(clk),.rst(rst),.utc(utc_ntp),.data(service_txd),.valid(service_tx_en),.error(service_tx_er),
 .event_valid(departure_valid),.timestamp(departure_time),.origin(departure_origin),.peer_ip(departure_ip));
afdx_service_gmii #(.BAG_CYCLES(SERVICE_BAG_CYCLES)) u_service_mac(
 .tx_admit(1'b1),
.clk(clk),.rst(rst),.gmii_rxd(service_rxd),.gmii_rx_dv(service_rx_dv),.gmii_rx_er(service_rx_er),
.gmii_txd(service_txd),.gmii_tx_en(service_tx_en),.gmii_tx_er(service_tx_er),.tx_done(service_tx_done),
.rx_valid(rxv),.rx_ip(rip),.rx_sport(rsp),.rx_dport(rdp),.rx_length(rlen),.rx_bytes(rb),.gmii_rx_timestamp(utc_ntp),.rx_timestamp(arrival_time),
.tx_valid(txv),.tx_ready(txr),.tx_ip(tip),.tx_sport(tsp),.tx_dport(tdp),.tx_length(tlen),.tx_bytes(tb),.received(),.rejected());
wire [31:0] package_crc;wire [2:0] package_files;wire [15:0] package_selected_length;
wire [7:0] package_app_data;wire package_valid;
afdx_package_network_services #(.CLK_HZ(CLK_HZ),.TIMEOUT_CYCLES(SERVICE_TIMEOUT_CYCLES),.MAC_TIMESTAMPS(1)) u_network_services(
 .clk(clk),.rst(rst),.loader_ip(loader_ip),.time_server_ip(time_server_ip),.hardware_length(hardware_length),.hardware_id(hardware_id),
 .rtc_poll(rtc_poll),.rtc_locked(rtc_locked),.utc_ntp(utc_ntp),.monotonic_ticks(monotonic_ticks),
 .package_valid(package_valid),.generation(package_generation),.package_crc(package_crc),.file_count(package_files),.app_file(app_file),.app_address(image_read_address),.app_data(package_app_data),.app_length(package_selected_length),.app_name(),
 .loading(loading),.load_complete(load_complete),.load_failed(load_failed),
 .tx_valid(txv),.tx_ready(txr),.tx_ip(tip),.tx_sport(tsp),.tx_dport(tdp),.tx_length(tlen),.tx_bytes(tb),
 .rx_valid(rxv),.rx_ip(rip),.rx_sport(rsp),.rx_dport(rdp),.rx_length(rlen),.rx_bytes(rb),
 .tx_timestamp_valid(departure_valid),.tx_timestamp(departure_time),.tx_origin(departure_origin),.tx_peer_ip(departure_ip),.rx_timestamp(arrival_time));
assign image_valid=package_valid;
assign image_length=package_selected_length;
assign image_crc=package_crc;
assign package_file_count=package_files;
assign image_read_data=package_app_data;
endmodule
