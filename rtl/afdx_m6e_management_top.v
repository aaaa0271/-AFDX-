`timescale 1ns/1ps
module afdx_m6e_management_top #(
    parameter integer CLK_HZ = 1000,
    parameter integer BAG_CYCLES = 400000,
    parameter [47:0] MANAGEMENT_MAC = 48'h030000000001,
    parameter [31:0] MANAGEMENT_IP = 32'hc0a80101
)(
    input wire clk, rst,
    input wire [7:0] gmii_rxd,
    input wire gmii_rx_dv, gmii_rx_er,
    input wire [47:0] cfg_src_mac, cfg_dst_mac,
    input wire [31:0] cfg_src_ip,
    output wire busy, rx_commit,
    output wire rx_result_valid, rx_accept, rx_reject, crc_error, boundary_busy,
    output wire response_done, response_valid, response_error,
    output wire [7:0] response_error_code,
    output wire builder_start, builder_done,
    output wire [7:0] gmii_txd,
    output wire gmii_tx_en, gmii_tx_er, tx_frame_done, underrun,
    output wire [7:0] sequence_num,
    input wire m5_network_a_enable, m5_network_b_enable,
    input wire m5_degraded_mode, m5_redundancy_ok,
    input wire m5_frame_count_match, m5_active_byte_count_match,
    input wire m5_fault_applied_event,
    input wire [31:0] m5_rx_accepted_count,
    input wire [31:0] m5_rx_accepted_a_count, m5_rx_accepted_b_count,
    input wire [31:0] m5_rx_duplicate_count,
    input wire [31:0] m5_rx_cross_network_duplicate_count,
    input wire [31:0] m5_rx_same_network_repeat_count,
    input wire [31:0] m5_rx_stale_count, m5_rx_sequence_gap_count,
    input wire [31:0] m5_tx_a_frame_count, m5_tx_b_frame_count,
    input wire [31:0] m5_tx_a_active_byte_count, m5_tx_b_active_byte_count,
    input wire [31:0] m5_tx_byte_mismatch_count,
    input wire [31:0] m5_tx_frame_skew_cycle_count,
    input wire [31:0] m5_tx_frame_done_skew_count,
    input wire [31:0] m5_tx_er_mismatch_count,
    input wire [31:0] m5_tx_a_error_cycle_count, m5_tx_b_error_cycle_count,
    input wire [31:0] m5_tx_a_underrun_count, m5_tx_b_underrun_count
);
wire meta_valid, payload_valid, payload_sof, payload_eof, payload_ready, frame_done, frame_valid;
wire [31:0] src_ip;
wire [15:0] udp_src_port, udp_dst_port;
wire [10:0] payload_length;
wire [7:0] payload_data;
afdx_m6e_management_rx #(.MANAGEMENT_MAC(MANAGEMENT_MAC),.MANAGEMENT_IP(MANAGEMENT_IP)) u_rx (
    .clk(clk),.rst(rst),.gmii_rxd(gmii_rxd),.gmii_rx_dv(gmii_rx_dv),.gmii_rx_er(gmii_rx_er),
    .management_busy(busy),.meta_valid(meta_valid),.src_ip(src_ip),.udp_src_port(udp_src_port),
    .udp_dst_port(udp_dst_port),.payload_length(payload_length),.payload_data(payload_data),
    .payload_valid(payload_valid),.payload_sof(payload_sof),.payload_eof(payload_eof),.payload_ready(payload_ready),
    .frame_done(frame_done),.frame_valid(frame_valid),.rx_result_valid(rx_result_valid),
    .rx_accept(rx_accept),.rx_reject(rx_reject),.crc_error(crc_error),.boundary_busy(boundary_busy));
afdx_m6e_integration #(.CLK_HZ(CLK_HZ),.BAG_CYCLES(BAG_CYCLES)) u_integration (
    .clk(clk),.rst(rst),.meta_valid(meta_valid),.src_ip(src_ip),.udp_src_port(udp_src_port),
    .udp_dst_port(udp_dst_port),.payload_length(payload_length),.payload_data(payload_data),
    .payload_valid(payload_valid),.payload_sof(payload_sof),.payload_eof(payload_eof),.payload_ready(payload_ready),
    .frame_done(frame_done),.frame_valid(frame_valid),.cfg_src_mac(cfg_src_mac),.cfg_dst_mac(cfg_dst_mac),
    .cfg_src_ip(cfg_src_ip),.busy(busy),.rx_commit(rx_commit),.response_done(response_done),
    .response_valid(response_valid),.response_error(response_error),.response_error_code(response_error_code),
    .builder_start(builder_start),.builder_done(builder_done),.gmii_txd(gmii_txd),.gmii_tx_en(gmii_tx_en),
    .gmii_tx_er(gmii_tx_er),.tx_frame_done(tx_frame_done),.underrun(underrun),.sequence_num(sequence_num),
    .m5_network_a_enable(m5_network_a_enable),.m5_network_b_enable(m5_network_b_enable),
    .m5_degraded_mode(m5_degraded_mode),.m5_redundancy_ok(m5_redundancy_ok),
    .m5_frame_count_match(m5_frame_count_match),.m5_active_byte_count_match(m5_active_byte_count_match),
    .m5_fault_applied_event(m5_fault_applied_event),.m5_rx_accepted_count(m5_rx_accepted_count),
    .m5_rx_accepted_a_count(m5_rx_accepted_a_count),.m5_rx_accepted_b_count(m5_rx_accepted_b_count),
    .m5_rx_duplicate_count(m5_rx_duplicate_count),.m5_rx_cross_network_duplicate_count(m5_rx_cross_network_duplicate_count),
    .m5_rx_same_network_repeat_count(m5_rx_same_network_repeat_count),.m5_rx_stale_count(m5_rx_stale_count),
    .m5_rx_sequence_gap_count(m5_rx_sequence_gap_count),.m5_tx_a_frame_count(m5_tx_a_frame_count),
    .m5_tx_b_frame_count(m5_tx_b_frame_count),.m5_tx_a_active_byte_count(m5_tx_a_active_byte_count),
    .m5_tx_b_active_byte_count(m5_tx_b_active_byte_count),.m5_tx_byte_mismatch_count(m5_tx_byte_mismatch_count),
    .m5_tx_frame_skew_cycle_count(m5_tx_frame_skew_cycle_count),.m5_tx_frame_done_skew_count(m5_tx_frame_done_skew_count),
    .m5_tx_er_mismatch_count(m5_tx_er_mismatch_count),.m5_tx_a_error_cycle_count(m5_tx_a_error_cycle_count),
    .m5_tx_b_error_cycle_count(m5_tx_b_error_cycle_count),.m5_tx_a_underrun_count(m5_tx_a_underrun_count),
    .m5_tx_b_underrun_count(m5_tx_b_underrun_count));
endmodule
