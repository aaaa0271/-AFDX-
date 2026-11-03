`timescale 1ns / 1ps

module afdx_rx_frame_parser #(
    parameter integer MAX_RAW_BYTES     = 1518,
    parameter integer MAX_PAYLOAD_BYTES = 1471,
    parameter integer RX_CONFIGURABLE=0
)(
    input wire [671:0] rx_cfg_table,
    input  wire        clk,
    input  wire        rst,

    // ========================================================
    // Raw GMII RX
    // ========================================================

    input  wire [7:0]  gmii_rxd,
    input  wire        gmii_rx_dv,
    input  wire        gmii_rx_er,


    // ========================================================
    // Parsed Ethernet metadata
    // ========================================================

    output wire [47:0] dst_mac,
    output wire [47:0] src_mac,
    output wire [15:0] ether_type,


    // ========================================================
    // Parsed IPv4 metadata
    // ========================================================

    output wire [15:0] ip_total_length,
    output wire [7:0]  ip_ttl,
    output wire [7:0]  ip_protocol,
    output wire [15:0] ip_header_checksum,

    output wire [31:0] src_ip,
    output wire [31:0] dst_ip,


    // ========================================================
    // Parsed UDP metadata
    // ========================================================

    output wire [15:0] udp_src_port,
    output wire [15:0] udp_dst_port,
    output wire [15:0] udp_length,
    output wire [15:0] udp_checksum,

    output wire [10:0] payload_length,
    output wire [4:0]  padding_length,


    // ========================================================
    // Raw AFDX sequence
    //
    // Latched by M3-B on the last byte of the Ethernet body.
    //
    // M5-D2a deliberately performs NO sequence classification.
    // The raw byte is forwarded to the D1 eliminator.
    // ========================================================

    output wire [7:0]  afdx_sequence,


    // ========================================================
    // Metadata event
    // ========================================================

    output wire        meta_valid,


    // ========================================================
    // D2b candidate interface
    //
    // A candidate is held stable (not a pulse) until it is
    // accepted by candidate_ready.
    // ========================================================

    output reg         candidate_valid,
    input  wire        candidate_ready,

    output reg  [1:0]  candidate_vl_index,
    output reg  [15:0] candidate_vl_id,
    output reg  [10:0] candidate_payload_length,
    output reg  [7:0]  candidate_sequence,

    output reg         candidate_outstanding,


    // ========================================================
    // D1 decision interface
    // ========================================================

    input  wire        decision_valid,
    input  wire        decision_accept,


    // ========================================================
    // Committed UDP payload stream
    //
    // The parser payload is captured by the commit buffer and
    // is only replayed after D1 accepts the logical frame.
    // ========================================================

    output wire [7:0]  payload_data,
    output wire        payload_valid,
    input  wire        payload_ready,

    output wire        payload_sof,
    output wire        payload_eof,


    // ========================================================
    // Parser-level result
    // ========================================================

    output wire        frame_done,
    output wire        frame_valid,


    // ========================================================
    // M3-A Layer-2 status
    // ========================================================

    output wire        l2_good_frame,
    output wire        l2_output_frame_done,

    output wire        l2_crc_error,
    output wire        l2_format_error,
    output wire        l2_length_error,
    output wire        l2_rx_error,
    output wire        l2_overflow_error,


    // ========================================================
    // M3-B protocol status
    // ========================================================

    output wire        ether_type_error,
    output wire        ip_version_error,
    output wire        ip_ihl_error,
    output wire        ip_checksum_error,
    output wire        ip_protocol_error,
    output wire        ip_length_error,
    output wire        udp_length_error,
    output wire        structure_error,


    // ========================================================
    // M3-C Virtual Link result
    // ========================================================

    output wire        vl_result_valid,
    output wire        vl_accept,
    output wire        vl_reject,

    output wire [1:0]  vl_index,
    output wire [15:0] vl_id,
    output wire [10:0] vl_lmax,

    output wire        unknown_vl_error,
    output wire        disabled_vl_error,
    output wire        ip_whitelist_error,
    output wire        udp_whitelist_error,
    output wire        length_whitelist_error,


    // ========================================================
    // M3-D Payload Commit Buffer status
    // ========================================================

    output wire        commit_overflow_error
);


    // ============================================================
    // Internal validated Ethernet-body stream
    // ============================================================

    wire [7:0]  body_data;
    wire        body_valid;

    wire        adapter_body_ready;
    wire        parser_body_ready;

    wire        body_sof;
    wire        body_eof;

    wire [10:0] body_frame_length;


    // ============================================================
    // D2a single-frame ownership / ingress serialization
    //
    // One D2a instance owns exactly one commit buffer.
    //
    // Once a legal frame has produced a candidate, no following
    // Ethernet body may enter M3-B until:
    //
    //   1. D1 has returned the decision, AND
    //   2. accepted payload replay has completely finished.
    //
    // This prevents a following frame's meta_valid from overwriting
    // frame_vl_* while the previous frame is still outstanding.
    //
    // gmii_rx_adapter itself may continue receiving into its internal
    // frame buffers. We only stall its validated-body output here.
    // ============================================================

    wire commit_capture_active;
    wire commit_frame_buffered;
    wire commit_replay_active;

    wire ingress_enable;

    assign ingress_enable =
           !commit_replay_active
        && !candidate_valid
        && !candidate_outstanding;


    // Adapter may release a body byte only when the parser is ready
    // AND this D2a instance currently owns a free commit slot.

    assign adapter_body_ready =
           parser_body_ready
        && ingress_enable;


    // ============================================================
    // Internal parser interface
    // ============================================================

    wire [7:0]  parser_payload_data;
    wire        parser_payload_valid;
    wire        parser_payload_ready;

    wire        parser_payload_sof;
    wire        parser_payload_eof;

    wire        parser_frame_done;
    wire        parser_frame_valid;

    wire [7:0]  parser_sequence;
    wire        parser_meta_valid;


    // ============================================================
    // M3-A GMII receive adapter
    // ============================================================

    gmii_rx_adapter #(
        .MAX_RAW_BYTES(MAX_RAW_BYTES)
    )
    u_gmii_rx_adapter (

        .clk               (clk),
        .rst               (rst),

        .gmii_rxd          (gmii_rxd),
        .gmii_rx_dv        (gmii_rx_dv),
        .gmii_rx_er        (gmii_rx_er),

        .m_data            (body_data),
        .m_valid           (body_valid),
        .m_ready           (adapter_body_ready),

        .m_sof             (body_sof),
        .m_eof             (body_eof),

        .m_frame_length    (body_frame_length),

        .good_frame        (l2_good_frame),
        .output_frame_done (l2_output_frame_done),

        .crc_error         (l2_crc_error),
        .format_error      (l2_format_error),
        .length_error      (l2_length_error),
        .rx_error          (l2_rx_error),
        .overflow_error    (l2_overflow_error)
    );


    // ============================================================
    // M3-B Ethernet + IPv4 + UDP Parser
    // ============================================================

    afdx_eth_ipv4_udp_parser #(
        .MAX_PAYLOAD_BYTES(MAX_PAYLOAD_BYTES)
    )
    u_parser (

        .clk                (clk),
        .rst                (rst),

        .s_data             (body_data),
        .s_valid            (body_valid && ingress_enable),
        .s_ready            (parser_body_ready),

        .s_sof              (body_sof),
        .s_eof              (body_eof),

        .s_frame_length     (body_frame_length),

        .dst_mac            (dst_mac),
        .src_mac            (src_mac),
        .ether_type         (ether_type),

        .ip_total_length    (ip_total_length),
        .ip_ttl             (ip_ttl),
        .ip_protocol        (ip_protocol),
        .ip_header_checksum (ip_header_checksum),

        .src_ip             (src_ip),
        .dst_ip             (dst_ip),

        .udp_src_port       (udp_src_port),
        .udp_dst_port       (udp_dst_port),
        .udp_length         (udp_length),
        .udp_checksum       (udp_checksum),

        .payload_length     (payload_length),
        .padding_length     (padding_length),

        .afdx_sequence      (parser_sequence),
        .meta_valid         (parser_meta_valid),

        .payload_data       (parser_payload_data),
        .payload_valid      (parser_payload_valid),
        .payload_ready      (parser_payload_ready),

        .payload_sof        (parser_payload_sof),
        .payload_eof        (parser_payload_eof),

        .frame_done         (parser_frame_done),
        .frame_valid        (parser_frame_valid),

        .ether_type_error   (ether_type_error),
        .ip_version_error   (ip_version_error),
        .ip_ihl_error       (ip_ihl_error),
        .ip_checksum_error  (ip_checksum_error),
        .ip_protocol_error  (ip_protocol_error),
        .ip_length_error    (ip_length_error),
        .udp_length_error   (udp_length_error), .udp_checksum_error(),
        .structure_error    (structure_error)
    );


    // ============================================================
    // M3-C Virtual Link Identification + Whitelist
    // ============================================================

    afdx_vl_identifier #(.CONFIGURABLE(RX_CONFIGURABLE)) u_vl_identifier (
        .cfg_table(rx_cfg_table),

        .clk                  (clk),
        .rst                  (rst),

        .meta_valid           (parser_meta_valid),

        .dst_mac              (dst_mac),
        .src_ip               (src_ip),
        .dst_ip               (dst_ip),

        .udp_src_port         (udp_src_port),
        .udp_dst_port         (udp_dst_port),

        .payload_length       (payload_length),

        .result_valid         (vl_result_valid),
        .vl_accept            (vl_accept),
        .vl_reject            (vl_reject),

        .vl_index             (vl_index),
        .vl_id                (vl_id),
        .vl_lmax              (vl_lmax),

        .unknown_vl_error       (unknown_vl_error),
        .disabled_vl_error      (disabled_vl_error),
        .ip_whitelist_error     (ip_whitelist_error),
        .udp_whitelist_error    (udp_whitelist_error),
        .length_whitelist_error (length_whitelist_error)
    );


    // ============================================================
    // Frame Context Latch
    //
    // M3-C resolves the VL on the meta_valid pulse, while the
    // AFDX sequence byte only becomes available with the last
    // byte of the Ethernet body.
    // ============================================================

    reg        frame_vl_valid;
    reg        frame_vl_accept;

    reg [1:0]  frame_vl_index;
    reg [15:0] frame_vl_id;


    // ============================================================
    // Frame-level classification
    //
    // D2a's only responsibility is legality:
    //
    //   "Is this Ethernet/IPv4/UDP/VL frame legal?"
    //
    // Sequence new/duplicate/stale classification is left to
    // D1. Therefore D2a keeps NO sequence history.
    // ============================================================

    wire valid_candidate_at_eof =
           parser_frame_done
        && parser_frame_valid
        && frame_vl_valid
        && frame_vl_accept;

    wire parser_reject_at_eof =
           parser_frame_done
        && !parser_frame_valid;

    wire vl_reject_at_eof =
           parser_frame_done
        && parser_frame_valid
        && !(frame_vl_valid && frame_vl_accept);

    wire frame_reject_at_eof =
        parser_reject_at_eof || vl_reject_at_eof;


    // ============================================================
    // Frame payload capture tracking
    // ============================================================

    reg frame_payload_captured;

    wire parser_payload_fire =
        parser_payload_valid && parser_payload_ready;


    // ============================================================
    // Commit Buffer final decision
    // ============================================================

    wire commit_decision_valid =
           frame_payload_captured
        && (frame_reject_at_eof || decision_valid);

    wire commit_decision_accept =
           decision_valid
        && decision_accept;


    // ============================================================
    // Candidate interface
    // ============================================================

    wire candidate_fire =
        candidate_valid && candidate_ready;


    // ============================================================
    // Sequential state
    // ============================================================

    always @(posedge clk) begin

        if (rst) begin

            frame_vl_valid  <= 1'b0;
            frame_vl_accept <= 1'b0;
            frame_vl_index  <= 2'd0;
            frame_vl_id     <= 16'd0;

            frame_payload_captured <= 1'b0;

            candidate_valid        <= 1'b0;
            candidate_outstanding  <= 1'b0;

            candidate_vl_index       <= 2'd0;
            candidate_vl_id          <= 16'd0;
            candidate_payload_length <= 11'd0;
            candidate_sequence       <= 8'd0;

        end
        else begin

            // ----------------------------------------------------
            // Frame Context Latch
            // ----------------------------------------------------

            if (vl_result_valid) begin

                frame_vl_valid  <= 1'b1;
                frame_vl_accept <= vl_accept;

                frame_vl_index  <= vl_index;
                frame_vl_id     <= vl_id;

            end

            else if (frame_reject_at_eof || decision_valid) begin

                frame_vl_valid  <= 1'b0;
                frame_vl_accept <= 1'b0;

                frame_vl_index  <= 2'd0;
                frame_vl_id     <= 16'd0;

            end


            // ----------------------------------------------------
            // Payload capture tracking
            // ----------------------------------------------------

            if (parser_payload_fire)
                frame_payload_captured <= 1'b1;

            if (frame_reject_at_eof || decision_valid)
                frame_payload_captured <= 1'b0;


            // ----------------------------------------------------
            // Candidate latch
            //
            // candidate_valid is held (not pulsed) until the
            // downstream arbiter asserts candidate_ready.
            // ----------------------------------------------------

            if (candidate_fire) begin

                candidate_valid       <= 1'b0;
                candidate_outstanding <= 1'b1;

            end

            if (valid_candidate_at_eof) begin

                candidate_valid <= 1'b1;

                candidate_vl_index       <= frame_vl_index;
                candidate_vl_id          <= frame_vl_id;
                candidate_payload_length <= payload_length;
                candidate_sequence       <= parser_sequence;

            end

            if (decision_valid)
                candidate_outstanding <= 1'b0;

        end

    end


    // ============================================================
    // Parser frame interface (observable)
    // ============================================================

    assign afdx_sequence = parser_sequence;
    assign meta_valid     = parser_meta_valid;
    assign frame_done     = parser_frame_done;
    assign frame_valid    = parser_frame_valid;


    // ============================================================
    // M3-D Payload Commit Buffer
    //
    // Parser payload -> commit buffer -> (ACCEPT replay / REJECT
    // discard) based on the D1 decision.
    // ============================================================

    afdx_payload_commit_buffer #(
        .MAX_PAYLOAD_BYTES(MAX_PAYLOAD_BYTES)
    )
    u_commit_buffer (

        .clk             (clk),
        .rst             (rst),

        .in_data         (parser_payload_data),
        .in_valid        (parser_payload_valid),
        .in_ready        (parser_payload_ready),

        .in_sof          (parser_payload_sof),
        .in_eof          (parser_payload_eof),

        .decision_valid  (commit_decision_valid),
        .decision_accept (commit_decision_accept),

        .out_data        (payload_data),
        .out_valid       (payload_valid),
        .out_ready       (payload_ready),

        .out_sof         (payload_sof),
        .out_eof         (payload_eof),

        .capture_active  (
            commit_capture_active
        ),

        .frame_buffered  (
            commit_frame_buffered
        ),

        .replay_active   (
            commit_replay_active
        ),

        .overflow_error  (commit_overflow_error)
    );


endmodule
