`timescale 1ns / 1ps
// M6E-01D：parser流到GMII发送；不包含GMII接收或ARP。
module afdx_m6e_integration #(
    parameter integer CLK_HZ = 1000,
    parameter integer BAG_CYCLES = 400000
)(
    input wire clk, rst,
    input wire meta_valid,
    input wire [31:0] src_ip,
    input wire [15:0] udp_src_port, udp_dst_port,
    input wire [10:0] payload_length,
    input wire [7:0] payload_data,
    input wire payload_valid, payload_sof, payload_eof,
    output wire payload_ready,
    input wire frame_done, frame_valid,
    input wire [47:0] cfg_src_mac, cfg_dst_mac,
    input wire [31:0] cfg_src_ip,
    output wire busy, rx_commit,
    output wire response_done, response_valid, response_error,
    output wire [7:0] response_error_code,
    output wire builder_start,
    output wire builder_done,
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
    localparam IDLE=0, M6D_REQ=1, M6D_WAIT=2, TX_PENDING=3, TX_WAIT=4;
    reg [2:0] state;
    wire m6d_req = (state == M6D_REQ);
    // 复用既有BAG，只有待发送事务可以申请；sequence在最后FCS后推进。
    bag_regulator #(.BAG_CYCLES(BAG_CYCLES)) u_bag (
        .clk(clk), .rst(rst), .send_request(state == TX_PENDING),
        .send_grant(builder_start)
    );
    // 首帧为0，FF之后回到1，保留原sequence发生器契约。
    seq_generator u_sequence (
        .clk(clk), .rst(rst), .advance(tx_frame_done), .seq_num(sequence_num)
    );
    wire [767:0] active_msg_bytes, response_bytes;
    wire [10:0] active_msg_length;
    wire [31:0] active_requester_ip;
    wire [15:0] active_requester_port;
    wire [7:0] response_length;
    reg [767:0] response_q;
    reg [7:0] length_q;
    reg [47:0] src_mac_q, dst_mac_q;
    reg [31:0] src_ip_q, requester_ip_q;
    reg [15:0] src_port_q, requester_port_q;
    wire [7:0] body_data;
    wire body_valid, body_eof, body_ready;
    integer i;
    // 包括commit脉冲本身，封闭下一拍metadata的准入窗口。
    assign busy = (state != IDLE) | rx_commit;
    afdx_m6e_udp_rx_buffer u_rx (
        .clk(clk), .rst(rst), .m6e_busy(busy), .meta_valid(meta_valid),
        .src_ip(src_ip), .udp_src_port(udp_src_port), .udp_dst_port(udp_dst_port),
        .payload_length(payload_length), .payload_data(payload_data),
        .payload_valid(payload_valid), .payload_ready(payload_ready),
        .payload_sof(payload_sof), .payload_eof(payload_eof),
        .frame_done(frame_done), .frame_valid(frame_valid), .rx_commit(rx_commit),
        .active_msg_bytes(active_msg_bytes), .active_msg_length(active_msg_length),
        .active_requester_ip(active_requester_ip), .active_requester_port(active_requester_port)
    );
    // 01A低位优先96字节，M6D低位优先128字节；仅高位补零。
    afdx_m6d_integration #(.CLK_HZ(CLK_HZ)) u_m6d (
        .clk(clk), .rst_n(!rst), .req(m6d_req),
        .msg_length(active_msg_length[7:0]), .msg_bytes({256'b0, active_msg_bytes}),
        .response_done(response_done), .response_valid(response_valid),
        .response_error(response_error), .response_error_code(response_error_code),
        .response_length(response_length), .response_bytes(response_bytes),
        .m5_network_a_enable(m5_network_a_enable), .m5_network_b_enable(m5_network_b_enable),
        .m5_degraded_mode(m5_degraded_mode), .m5_redundancy_ok(m5_redundancy_ok),
        .m5_frame_count_match(m5_frame_count_match), .m5_active_byte_count_match(m5_active_byte_count_match),
        .m5_fault_applied_event(m5_fault_applied_event), .m5_rx_accepted_count(m5_rx_accepted_count),
        .m5_rx_accepted_a_count(m5_rx_accepted_a_count), .m5_rx_accepted_b_count(m5_rx_accepted_b_count),
        .m5_rx_duplicate_count(m5_rx_duplicate_count), .m5_rx_cross_network_duplicate_count(m5_rx_cross_network_duplicate_count),
        .m5_rx_same_network_repeat_count(m5_rx_same_network_repeat_count), .m5_rx_stale_count(m5_rx_stale_count),
        .m5_rx_sequence_gap_count(m5_rx_sequence_gap_count), .m5_tx_a_frame_count(m5_tx_a_frame_count),
        .m5_tx_b_frame_count(m5_tx_b_frame_count), .m5_tx_a_active_byte_count(m5_tx_a_active_byte_count),
        .m5_tx_b_active_byte_count(m5_tx_b_active_byte_count), .m5_tx_byte_mismatch_count(m5_tx_byte_mismatch_count),
        .m5_tx_frame_skew_cycle_count(m5_tx_frame_skew_cycle_count), .m5_tx_frame_done_skew_count(m5_tx_frame_done_skew_count),
        .m5_tx_er_mismatch_count(m5_tx_er_mismatch_count), .m5_tx_a_error_cycle_count(m5_tx_a_error_cycle_count),
        .m5_tx_b_error_cycle_count(m5_tx_b_error_cycle_count), .m5_tx_a_underrun_count(m5_tx_a_underrun_count),
        .m5_tx_b_underrun_count(m5_tx_b_underrun_count)
    );
    afdx_frame_builder_varlen_cfg u_builder (
        .clk(clk), .rst(rst), .start(builder_start), .seq_num(sequence_num),
        .cfg_dst_mac(dst_mac_q), .cfg_src_mac(src_mac_q),
        .cfg_src_ip(src_ip_q), .cfg_dst_ip(requester_ip_q),
        .cfg_src_port(src_port_q), .cfg_dst_port(requester_port_q),
        .payload_length(length_q), .payload_bytes(response_q),
        .tx_data(body_data), .tx_valid(body_valid), .tx_eof(body_eof),
        .tx_ready(body_ready), .busy(), .done(builder_done)
    );
    gmii_tx_adapter_varlen u_tx (
        .clk(clk), .rst(rst), .s_data(body_data), .s_valid(body_valid),
        .s_eof(body_eof), .s_ready(body_ready), .gmii_txd(gmii_txd),
        .gmii_tx_en(gmii_tx_en), .gmii_tx_er(gmii_tx_er),
        .frame_done(tx_frame_done), .underrun(underrun)
    );
    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            response_q <= 0; length_q <= 0;
            src_mac_q <= 0; dst_mac_q <= 0; src_ip_q <= 0;
            requester_ip_q <= 0; src_port_q <= 0; requester_port_q <= 0;
        end else begin
            case (state)
                IDLE: if (rx_commit) begin
                    src_mac_q <= cfg_src_mac; dst_mac_q <= cfg_dst_mac;
                    src_ip_q <= cfg_src_ip; src_port_q <= 16'd161;
                    requester_ip_q <= active_requester_ip;
                    requester_port_q <= active_requester_port;
                    state <= M6D_REQ;
                end
                M6D_REQ: state <= M6D_WAIT;
                M6D_WAIT: if (response_done) begin
                    if (response_valid) begin
                        // M6D高位优先输出，完整反转到01B低位优先布局。
                        for (i=0; i<96; i=i+1)
                            response_q[i*8 +: 8] <= response_bytes[767-i*8 -: 8];
                        length_q <= response_length;
                        state <= TX_PENDING;
                    end else state <= IDLE;
                end
                TX_PENDING: if (builder_start) state <= TX_WAIT;
                // builder_done只结束body；ownership必须保持到最后FCS。
                TX_WAIT: if (tx_frame_done) begin
                    state <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
