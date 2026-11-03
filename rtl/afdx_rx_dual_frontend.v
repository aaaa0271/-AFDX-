`timescale 1ns / 1ps

// ============================================================
// M5-D2c3
// Final Dual-Network AFDX RX Front End
//
// Network A GMII -> D2a-A --\
//                           D2c1 -> D1 redundancy decision
// Network B GMII -> D2a-B --/
//
// D1 decision is routed back only to the owning parser.
//
// Accepted payload:
//     D2a-A --\
//              D2c2 frame-atomic arbiter -> application
//     D2a-B --/
//
// Redundancy policy is implemented ONLY by D1.
// ============================================================

module afdx_rx_dual_frontend #(
    parameter integer MAX_RAW_BYTES     = 1518,
    parameter integer MAX_PAYLOAD_BYTES = 1471,
    parameter integer SKEW_MAX_CYCLES=16_000_000,
    parameter integer RX_CONFIGURABLE=0
)(
    input wire [671:0] rx_cfg_table,
    input  wire       clk,
    input  wire       rst,
    input  wire       clear,

    // ========================================================
    // GMII Network A
    // ========================================================

    input  wire [7:0] gmii_a_rxd,
    input  wire       gmii_a_rx_dv,
    input  wire       gmii_a_rx_er,

    // ========================================================
    // GMII Network B
    // ========================================================

    input  wire [7:0] gmii_b_rxd,
    input  wire       gmii_b_rx_dv,
    input  wire       gmii_b_rx_er,

    // ========================================================
    // Final accepted payload
    // ========================================================

    output wire [7:0] payload_data,
    output wire       payload_valid,
    input  wire       payload_ready,

    output wire       payload_sof,
    output wire       payload_eof,

    // 0 = payload came from network A
    // 1 = payload came from network B
    output wire       payload_network,

    // ========================================================
    // D1 events
    // ========================================================

    output wire       accept_event,
    output wire       duplicate_event,
    output wire       stale_event,
    output wire       gap_event,

    // ========================================================
    // Statistics
    // ========================================================

    output wire [31:0] accepted_count,
    output wire [31:0] accepted_a_count,
    output wire [31:0] accepted_b_count,

    output wire [31:0] duplicate_count,

    output wire [31:0] cross_network_duplicate_count,
    output wire [31:0] same_network_repeat_count,

    output wire [31:0] stale_count,
    output wire [31:0] sequence_gap_count,

    // ========================================================
    // D2a debug/status
    // ========================================================

    output wire       a_candidate_valid,
    output wire       a_candidate_outstanding,

    output wire       b_candidate_valid,
    output wire       b_candidate_outstanding,

    output wire       a_l2_crc_error,
    output wire       b_l2_crc_error,

    output wire       a_unknown_vl_error,
    output wire       b_unknown_vl_error,

    output wire       a_commit_overflow_error,
    output wire       b_commit_overflow_error,

    // ========================================================
    // D2c debug
    // ========================================================

    output wire       decision_arb_valid,
    output wire       decision_arb_network,

    output wire       payload_frame_active
);


// ============================================================
// Parser A candidate
// ============================================================

wire       a_candidate_ready;

wire [1:0]  a_candidate_vl_index;
wire [15:0] a_candidate_vl_id;
wire [10:0] a_candidate_payload_length;
wire [7:0]  a_candidate_sequence;


// ============================================================
// Parser B candidate
// ============================================================

wire       b_candidate_ready;

wire [1:0]  b_candidate_vl_index;
wire [15:0] b_candidate_vl_id;
wire [10:0] b_candidate_payload_length;
wire [7:0]  b_candidate_sequence;


// ============================================================
// Decisions
// ============================================================

wire a_decision_valid;
wire a_decision_accept;

wire b_decision_valid;
wire b_decision_accept;


// ============================================================
// Payload A
// ============================================================

wire [7:0] a_payload_data;
wire       a_payload_valid;
wire       a_payload_ready;
wire       a_payload_sof;
wire       a_payload_eof;


// ============================================================
// Payload B
// ============================================================

wire [7:0] b_payload_data;
wire       b_payload_valid;
wire       b_payload_ready;
wire       b_payload_sof;
wire       b_payload_eof;


// ============================================================
// Unused parser-A metadata/status
// ============================================================

wire [47:0] a_dst_mac;
wire [47:0] a_src_mac;
wire [15:0] a_ether_type;

wire [15:0] a_ip_total_length;
wire [7:0]  a_ip_ttl;
wire [7:0]  a_ip_protocol;
wire [15:0] a_ip_header_checksum;

wire [31:0] a_src_ip;
wire [31:0] a_dst_ip;

wire [15:0] a_udp_src_port;
wire [15:0] a_udp_dst_port;
wire [15:0] a_udp_length;
wire [15:0] a_udp_checksum;

wire [10:0] a_payload_length_meta;
wire [4:0]  a_padding_length;
wire [7:0]  a_afdx_sequence;
wire        a_meta_valid;

wire        a_frame_done;
wire        a_frame_valid;

wire        a_l2_good_frame;
wire        a_l2_output_frame_done;
wire        a_l2_format_error;
wire        a_l2_length_error;
wire        a_l2_rx_error;
wire        a_l2_overflow_error;

wire        a_ether_type_error;
wire        a_ip_version_error;
wire        a_ip_ihl_error;
wire        a_ip_checksum_error;
wire        a_ip_protocol_error;
wire        a_ip_length_error;
wire        a_udp_length_error;
wire        a_structure_error;

wire        a_vl_result_valid;
wire        a_vl_accept;
wire        a_vl_reject;
wire [1:0]  a_vl_index;
wire [15:0] a_vl_id;
wire [10:0] a_vl_lmax;

wire        a_disabled_vl_error;
wire        a_ip_whitelist_error;
wire        a_udp_whitelist_error;
wire        a_length_whitelist_error;


// ============================================================
// Unused parser-B metadata/status
// ============================================================

wire [47:0] b_dst_mac;
wire [47:0] b_src_mac;
wire [15:0] b_ether_type;

wire [15:0] b_ip_total_length;
wire [7:0]  b_ip_ttl;
wire [7:0]  b_ip_protocol;
wire [15:0] b_ip_header_checksum;

wire [31:0] b_src_ip;
wire [31:0] b_dst_ip;

wire [15:0] b_udp_src_port;
wire [15:0] b_udp_dst_port;
wire [15:0] b_udp_length;
wire [15:0] b_udp_checksum;

wire [10:0] b_payload_length_meta;
wire [4:0]  b_padding_length;
wire [7:0]  b_afdx_sequence;
wire        b_meta_valid;

wire        b_frame_done;
wire        b_frame_valid;

wire        b_l2_good_frame;
wire        b_l2_output_frame_done;
wire        b_l2_format_error;
wire        b_l2_length_error;
wire        b_l2_rx_error;
wire        b_l2_overflow_error;

wire        b_ether_type_error;
wire        b_ip_version_error;
wire        b_ip_ihl_error;
wire        b_ip_checksum_error;
wire        b_ip_protocol_error;
wire        b_ip_length_error;
wire        b_udp_length_error;
wire        b_structure_error;

wire        b_vl_result_valid;
wire        b_vl_accept;
wire        b_vl_reject;
wire [1:0]  b_vl_index;
wire [15:0] b_vl_id;
wire [10:0] b_vl_lmax;

wire        b_disabled_vl_error;
wire        b_ip_whitelist_error;
wire        b_udp_whitelist_error;
wire        b_length_whitelist_error;


// ============================================================
// D2a-A
// ============================================================

afdx_rx_frame_parser #(
    .MAX_RAW_BYTES     (MAX_RAW_BYTES),
    .MAX_PAYLOAD_BYTES (MAX_PAYLOAD_BYTES),.RX_CONFIGURABLE(RX_CONFIGURABLE)
)
u_parser_a (
    .rx_cfg_table(rx_cfg_table),
    .clk                       (clk),
    .rst                       (rst),

    .gmii_rxd                  (gmii_a_rxd),
    .gmii_rx_dv                (gmii_a_rx_dv),
    .gmii_rx_er                (gmii_a_rx_er),

    .dst_mac                   (a_dst_mac),
    .src_mac                   (a_src_mac),
    .ether_type                (a_ether_type),

    .ip_total_length           (a_ip_total_length),
    .ip_ttl                    (a_ip_ttl),
    .ip_protocol               (a_ip_protocol),
    .ip_header_checksum        (a_ip_header_checksum),
    .src_ip                    (a_src_ip),
    .dst_ip                    (a_dst_ip),

    .udp_src_port              (a_udp_src_port),
    .udp_dst_port              (a_udp_dst_port),
    .udp_length                (a_udp_length),
    .udp_checksum              (a_udp_checksum),

    .payload_length            (a_payload_length_meta),
    .padding_length            (a_padding_length),
    .afdx_sequence             (a_afdx_sequence),
    .meta_valid                (a_meta_valid),

    .candidate_valid           (a_candidate_valid),
    .candidate_ready           (a_candidate_ready),
    .candidate_vl_index        (a_candidate_vl_index),
    .candidate_vl_id           (a_candidate_vl_id),
    .candidate_payload_length  (a_candidate_payload_length),
    .candidate_sequence        (a_candidate_sequence),
    .candidate_outstanding     (a_candidate_outstanding),

    .decision_valid            (a_decision_valid),
    .decision_accept           (a_decision_accept),

    .payload_data              (a_payload_data),
    .payload_valid             (a_payload_valid),
    .payload_ready             (a_payload_ready),
    .payload_sof               (a_payload_sof),
    .payload_eof               (a_payload_eof),

    .frame_done                (a_frame_done),
    .frame_valid               (a_frame_valid),

    .l2_good_frame             (a_l2_good_frame),
    .l2_output_frame_done      (a_l2_output_frame_done),
    .l2_crc_error              (a_l2_crc_error),
    .l2_format_error           (a_l2_format_error),
    .l2_length_error           (a_l2_length_error),
    .l2_rx_error               (a_l2_rx_error),
    .l2_overflow_error         (a_l2_overflow_error),

    .ether_type_error          (a_ether_type_error),
    .ip_version_error          (a_ip_version_error),
    .ip_ihl_error              (a_ip_ihl_error),
    .ip_checksum_error         (a_ip_checksum_error),
    .ip_protocol_error         (a_ip_protocol_error),
    .ip_length_error           (a_ip_length_error),
    .udp_length_error          (a_udp_length_error),
    .structure_error           (a_structure_error),

    .vl_result_valid           (a_vl_result_valid),
    .vl_accept                 (a_vl_accept),
    .vl_reject                 (a_vl_reject),
    .vl_index                  (a_vl_index),
    .vl_id                     (a_vl_id),
    .vl_lmax                   (a_vl_lmax),

    .unknown_vl_error          (a_unknown_vl_error),
    .disabled_vl_error         (a_disabled_vl_error),
    .ip_whitelist_error        (a_ip_whitelist_error),
    .udp_whitelist_error       (a_udp_whitelist_error),
    .length_whitelist_error    (a_length_whitelist_error),

    .commit_overflow_error     (a_commit_overflow_error)
);


// ============================================================
// D2a-B
// ============================================================

afdx_rx_frame_parser #(
    .MAX_RAW_BYTES     (MAX_RAW_BYTES),
    .MAX_PAYLOAD_BYTES (MAX_PAYLOAD_BYTES),.RX_CONFIGURABLE(RX_CONFIGURABLE)
)
u_parser_b (
    .rx_cfg_table(rx_cfg_table),
    .clk                       (clk),
    .rst                       (rst),

    .gmii_rxd                  (gmii_b_rxd),
    .gmii_rx_dv                (gmii_b_rx_dv),
    .gmii_rx_er                (gmii_b_rx_er),

    .dst_mac                   (b_dst_mac),
    .src_mac                   (b_src_mac),
    .ether_type                (b_ether_type),

    .ip_total_length           (b_ip_total_length),
    .ip_ttl                    (b_ip_ttl),
    .ip_protocol               (b_ip_protocol),
    .ip_header_checksum        (b_ip_header_checksum),
    .src_ip                    (b_src_ip),
    .dst_ip                    (b_dst_ip),

    .udp_src_port              (b_udp_src_port),
    .udp_dst_port              (b_udp_dst_port),
    .udp_length                (b_udp_length),
    .udp_checksum              (b_udp_checksum),

    .payload_length            (b_payload_length_meta),
    .padding_length            (b_padding_length),
    .afdx_sequence             (b_afdx_sequence),
    .meta_valid                (b_meta_valid),

    .candidate_valid           (b_candidate_valid),
    .candidate_ready           (b_candidate_ready),
    .candidate_vl_index        (b_candidate_vl_index),
    .candidate_vl_id           (b_candidate_vl_id),
    .candidate_payload_length  (b_candidate_payload_length),
    .candidate_sequence        (b_candidate_sequence),
    .candidate_outstanding     (b_candidate_outstanding),

    .decision_valid            (b_decision_valid),
    .decision_accept           (b_decision_accept),

    .payload_data              (b_payload_data),
    .payload_valid             (b_payload_valid),
    .payload_ready             (b_payload_ready),
    .payload_sof               (b_payload_sof),
    .payload_eof               (b_payload_eof),

    .frame_done                (b_frame_done),
    .frame_valid               (b_frame_valid),

    .l2_good_frame             (b_l2_good_frame),
    .l2_output_frame_done      (b_l2_output_frame_done),
    .l2_crc_error              (b_l2_crc_error),
    .l2_format_error           (b_l2_format_error),
    .l2_length_error           (b_l2_length_error),
    .l2_rx_error               (b_l2_rx_error),
    .l2_overflow_error         (b_l2_overflow_error),

    .ether_type_error          (b_ether_type_error),
    .ip_version_error          (b_ip_version_error),
    .ip_ihl_error              (b_ip_ihl_error),
    .ip_checksum_error         (b_ip_checksum_error),
    .ip_protocol_error         (b_ip_protocol_error),
    .ip_length_error           (b_ip_length_error),
    .udp_length_error          (b_udp_length_error),
    .structure_error           (b_structure_error),

    .vl_result_valid           (b_vl_result_valid),
    .vl_accept                 (b_vl_accept),
    .vl_reject                 (b_vl_reject),
    .vl_index                  (b_vl_index),
    .vl_id                     (b_vl_id),
    .vl_lmax                   (b_vl_lmax),

    .unknown_vl_error          (b_unknown_vl_error),
    .disabled_vl_error         (b_disabled_vl_error),
    .ip_whitelist_error        (b_ip_whitelist_error),
    .udp_whitelist_error       (b_udp_whitelist_error),
    .length_whitelist_error    (b_length_whitelist_error),

    .commit_overflow_error     (b_commit_overflow_error)
);


// ============================================================
// D2c1
// Candidate arbitration + D1 + decision ownership
// ============================================================

wire decision_arb_ready;
wire [1:0] decision_arb_vl_index;
wire [7:0] decision_arb_sequence;
wire decision_pending_network;


afdx_rx_redundancy_decision_core
u_decision_core (
    .clk                           (clk),
    .rst                           (rst),
    .clear                         (clear),

    .a_candidate_valid             (a_candidate_valid),
    .a_candidate_ready             (a_candidate_ready),
    .a_candidate_vl_index          (a_candidate_vl_index),
    .a_candidate_vl_id             (a_candidate_vl_id),
    .a_candidate_payload_length    (a_candidate_payload_length),
    .a_candidate_sequence          (a_candidate_sequence),

    .b_candidate_valid             (b_candidate_valid),
    .b_candidate_ready             (b_candidate_ready),
    .b_candidate_vl_index          (b_candidate_vl_index),
    .b_candidate_vl_id             (b_candidate_vl_id),
    .b_candidate_payload_length    (b_candidate_payload_length),
    .b_candidate_sequence          (b_candidate_sequence),

    .a_decision_valid              (a_decision_valid),
    .a_decision_accept             (a_decision_accept),

    .b_decision_valid              (b_decision_valid),
    .b_decision_accept             (b_decision_accept),

    .accept_event                  (accept_event),
    .duplicate_event               (duplicate_event),
    .stale_event                   (stale_event),
    .gap_event                     (gap_event),

    .accepted_count                (accepted_count),
    .accepted_a_count              (accepted_a_count),
    .accepted_b_count              (accepted_b_count),

    .duplicate_count               (duplicate_count),
    .cross_network_duplicate_count (cross_network_duplicate_count),
    .same_network_repeat_count     (same_network_repeat_count),

    .stale_count                   (stale_count),
    .sequence_gap_count            (sequence_gap_count),

    .arb_valid                     (decision_arb_valid),
    .arb_ready                     (decision_arb_ready),
    .arb_network                   (decision_arb_network),
    .arb_vl_index                  (decision_arb_vl_index),
    .arb_sequence                  (decision_arb_sequence),

    .decision_pending_network      (decision_pending_network)
);


// ============================================================
// D2c2
// Frame-atomic payload arbitration
// ============================================================

afdx_rx_payload_frame_arbiter
u_payload_arbiter (
    .clk         (clk),
    .rst         (rst),

    .a_data      (a_payload_data),
    .a_valid     (a_payload_valid),
    .a_ready     (a_payload_ready),
    .a_sof       (a_payload_sof),
    .a_eof       (a_payload_eof),

    .b_data      (b_payload_data),
    .b_valid     (b_payload_valid),
    .b_ready     (b_payload_ready),
    .b_sof       (b_payload_sof),
    .b_eof       (b_payload_eof),

    .out_data    (payload_data),
    .out_valid   (payload_valid),
    .out_ready   (payload_ready),
    .out_sof     (payload_sof),
    .out_eof     (payload_eof),

    .out_network (payload_network),

    .frame_active(payload_frame_active)
);


endmodule
