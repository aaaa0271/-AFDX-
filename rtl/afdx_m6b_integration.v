`timescale 1ns / 1ps

module afdx_m6b_integration #(
    parameter integer CLK_HZ = 1000
)(
    input wire clk,
    input wire rst_n,

    input wire snapshot_req,
    output wire snapshot_ack,
    output wire snapshot_valid,
    output wire [31:0] snapshot_id,
    input wire event_clear,

    input wire req_valid,
    input wire req_op,
    input wire [7:0] req_object_id,
    output wire rsp_valid,
    output wire rsp_error,
    output wire [1:0] rsp_error_code,
    output wire [7:0] rsp_object_id,
    output wire [7:0] rsp_asn1_type,
    output wire [31:0] rsp_value,

    input wire m5_network_a_enable,
    input wire m5_network_b_enable,
    input wire m5_degraded_mode,
    input wire m5_redundancy_ok,
    input wire m5_frame_count_match,
    input wire m5_active_byte_count_match,
    input wire m5_fault_applied_event,

    input wire [31:0] m5_rx_accepted_count,
    input wire [31:0] m5_rx_accepted_a_count,
    input wire [31:0] m5_rx_accepted_b_count,
    input wire [31:0] m5_rx_duplicate_count,
    input wire [31:0] m5_rx_cross_network_duplicate_count,
    input wire [31:0] m5_rx_same_network_repeat_count,
    input wire [31:0] m5_rx_stale_count,
    input wire [31:0] m5_rx_sequence_gap_count,

    input wire [31:0] m5_tx_a_frame_count,
    input wire [31:0] m5_tx_b_frame_count,
    input wire [31:0] m5_tx_a_active_byte_count,
    input wire [31:0] m5_tx_b_active_byte_count,
    input wire [31:0] m5_tx_byte_mismatch_count,
    input wire [31:0] m5_tx_frame_skew_cycle_count,
    input wire [31:0] m5_tx_frame_done_skew_count,
    input wire [31:0] m5_tx_er_mismatch_count,
    input wire [31:0] m5_tx_a_error_cycle_count,
    input wire [31:0] m5_tx_b_error_cycle_count,
    input wire [31:0] m5_tx_a_underrun_count,
    input wire [31:0] m5_tx_b_underrun_count
);
    wire [7:0] m6a_rd_addr;
    wire [31:0] m6a_rd_data;
    wire m6a_rd_valid;

    afdx_m6a_integration #(.CLK_HZ(CLK_HZ)) u_m6a (
        .clk(clk), .rst_n(rst_n),
        .snapshot_req(snapshot_req), .snapshot_ack(snapshot_ack),
        .snapshot_valid(snapshot_valid), .snapshot_id(snapshot_id),
        .event_clear(event_clear), .rd_addr(m6a_rd_addr),
        .rd_data(m6a_rd_data), .rd_valid(m6a_rd_valid),
        .m5_network_a_enable(m5_network_a_enable),
        .m5_network_b_enable(m5_network_b_enable),
        .m5_degraded_mode(m5_degraded_mode),
        .m5_redundancy_ok(m5_redundancy_ok),
        .m5_frame_count_match(m5_frame_count_match),
        .m5_active_byte_count_match(m5_active_byte_count_match),
        .m5_fault_applied_event(m5_fault_applied_event),
        .m5_rx_accepted_count(m5_rx_accepted_count),
        .m5_rx_accepted_a_count(m5_rx_accepted_a_count),
        .m5_rx_accepted_b_count(m5_rx_accepted_b_count),
        .m5_rx_duplicate_count(m5_rx_duplicate_count),
        .m5_rx_cross_network_duplicate_count(m5_rx_cross_network_duplicate_count),
        .m5_rx_same_network_repeat_count(m5_rx_same_network_repeat_count),
        .m5_rx_stale_count(m5_rx_stale_count),
        .m5_rx_sequence_gap_count(m5_rx_sequence_gap_count),
        .m5_tx_a_frame_count(m5_tx_a_frame_count),
        .m5_tx_b_frame_count(m5_tx_b_frame_count),
        .m5_tx_a_active_byte_count(m5_tx_a_active_byte_count),
        .m5_tx_b_active_byte_count(m5_tx_b_active_byte_count),
        .m5_tx_byte_mismatch_count(m5_tx_byte_mismatch_count),
        .m5_tx_frame_skew_cycle_count(m5_tx_frame_skew_cycle_count),
        .m5_tx_frame_done_skew_count(m5_tx_frame_done_skew_count),
        .m5_tx_er_mismatch_count(m5_tx_er_mismatch_count),
        .m5_tx_a_error_cycle_count(m5_tx_a_error_cycle_count),
        .m5_tx_b_error_cycle_count(m5_tx_b_error_cycle_count),
        .m5_tx_a_underrun_count(m5_tx_a_underrun_count),
        .m5_tx_b_underrun_count(m5_tx_b_underrun_count)
    );

    afdx_mib_register_bank u_m6b (
        .clk(clk), .rst_n(rst_n), .req_valid(req_valid), .req_op(req_op),
        .req_object_id(req_object_id), .rsp_valid(rsp_valid),
        .rsp_error(rsp_error), .rsp_error_code(rsp_error_code),
        .rsp_object_id(rsp_object_id), .rsp_asn1_type(rsp_asn1_type),
        .rsp_value(rsp_value), .m6a_rd_addr(m6a_rd_addr),
        .m6a_rd_data(m6a_rd_data), .m6a_rd_valid(m6a_rd_valid)
    );
endmodule
