`timescale 1ns / 1ps

module afdx_m6a_integration #(
    parameter integer CLK_HZ = 100_000_000
)(
    input wire clk,
    input wire rst_n,
    input wire snapshot_req,
    output wire snapshot_ack,
    output wire snapshot_valid,
    output wire [31:0] snapshot_id,
    input wire event_clear,
    input wire [7:0] rd_addr,
    output wire [31:0] rd_data,
    output wire rd_valid,

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

    reg m5_redundancy_ok_d;
    wire redundancy_fault_event;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            m5_redundancy_ok_d <= 1'b0;
        else
            m5_redundancy_ok_d <= m5_redundancy_ok;
    end

    assign redundancy_fault_event =
        m5_redundancy_ok_d && !m5_redundancy_ok;

    afdx_management_telemetry #(
        .CLK_HZ(CLK_HZ)
    ) u_telemetry (
        .clk(clk),
        .rst_n(rst_n),
        .snapshot_req(snapshot_req),
        .snapshot_ack(snapshot_ack),
        .snapshot_valid(snapshot_valid),
        .snapshot_id(snapshot_id),
        .event_clear(event_clear),
        .rd_addr(rd_addr),
        .rd_data(rd_data),
        .rd_valid(rd_valid),
        .network_a_enable(m5_network_a_enable),
        .network_b_enable(m5_network_b_enable),
        .degraded_mode(m5_degraded_mode),
        .redundancy_ok(m5_redundancy_ok),
        .frame_count_match(m5_frame_count_match),
        .active_byte_count_match(m5_active_byte_count_match),
        .redundancy_fault_event(redundancy_fault_event),
        .fault_applied_event(m5_fault_applied_event),
        .rx_accepted_count(m5_rx_accepted_count),
        .rx_accepted_a_count(m5_rx_accepted_a_count),
        .rx_accepted_b_count(m5_rx_accepted_b_count),
        .rx_duplicate_count(m5_rx_duplicate_count),
        .rx_cross_network_duplicate_count(m5_rx_cross_network_duplicate_count),
        .rx_same_network_repeat_count(m5_rx_same_network_repeat_count),
        .rx_stale_count(m5_rx_stale_count),
        .rx_sequence_gap_count(m5_rx_sequence_gap_count),
        .tx_a_frame_count(m5_tx_a_frame_count),
        .tx_b_frame_count(m5_tx_b_frame_count),
        .tx_a_active_byte_count(m5_tx_a_active_byte_count),
        .tx_b_active_byte_count(m5_tx_b_active_byte_count),
        .tx_byte_mismatch_count(m5_tx_byte_mismatch_count),
        .tx_frame_skew_cycle_count(m5_tx_frame_skew_cycle_count),
        .tx_frame_done_skew_count(m5_tx_frame_done_skew_count),
        .tx_er_mismatch_count(m5_tx_er_mismatch_count),
        .tx_a_error_cycle_count(m5_tx_a_error_cycle_count),
        .tx_b_error_cycle_count(m5_tx_b_error_cycle_count),
        .tx_a_underrun_count(m5_tx_a_underrun_count),
        .tx_b_underrun_count(m5_tx_b_underrun_count)
    );
endmodule
