module afdx_rx_frontend #(
    parameter integer MAX_RAW_BYTES     = 1518,
    parameter integer MAX_PAYLOAD_BYTES = 1471
)(
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
    // Checked by M3-D sequence integrity.
    // ========================================================

    output wire [7:0]  afdx_sequence,


    // ========================================================
    // Metadata event
    // ========================================================

    output wire        meta_valid,


    // ========================================================
    // Committed UDP payload stream
    //
    // M3-D: the parser payload is captured by the commit buffer
    // and is only replayed after the final frame decision:
    //
    //     Parser + VL + Sequence Integrity
    //
    // Therefore payload_valid == 1 always means that the whole
    // frame has been accepted.
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
    // M3-B/C/D FINAL FRAME DECISION
    //
    // Note:
    // Layer-2 frames rejected inside M3-A do not generate
    // rx_result_valid. They are reported through l2_* status.
    // ========================================================

    output wire        rx_result_valid,

    output wire        rx_accept,
    output wire        rx_reject,

    output wire [1:0]  rx_vl_index,
    output wire [15:0] rx_vl_id,

    output reg  [7:0]  rx_error_code,


    // ========================================================
    // M3-D Sequence Integrity status
    //
    // Classification of the frame reported by rx_result_valid.
    // ========================================================

    output wire        seq_first_frame,
    output wire        seq_reset_sequence,
    output wire        seq_single_loss,

    output wire        seq_duplicate_error,
    output wire        seq_sequence_error,

    output wire [7:0]  seq_psn_before,
    output wire [7:0]  seq_psn_after,


    // ========================================================
    // M3-D Payload Commit Buffer status
    // ========================================================

    output wire        commit_overflow_error
);


// ============================================================
// M3-D final frame error codes
//
// Legal whenever rx_result_valid is asserted.
// ============================================================

// No error

localparam [7:0] RX_ERR_NONE          = 8'h00;

// M3-B parser / protocol error

localparam [7:0] RX_ERR_PARSER        = 8'h20;

// M3-C VL / whitelist error

localparam [7:0] RX_ERR_VL_UNKNOWN    = 8'h30;
localparam [7:0] RX_ERR_VL_DISABLED   = 8'h31;
localparam [7:0] RX_ERR_IP_WHITELIST  = 8'h32;
localparam [7:0] RX_ERR_UDP_WHITELIST = 8'h33;
localparam [7:0] RX_ERR_LENGTH_LMAX   = 8'h34;

// M3-D sequence integrity error

localparam [7:0] RX_ERR_SEQ_DUPLICATE = 8'h40;
localparam [7:0] RX_ERR_SEQ_ORDER     = 8'h41;


// ============================================================
// Internal validated Ethernet-body stream
//
// These names are intentionally kept simple because the
// Integration Testbench will also observe them hierarchically.
// ============================================================

wire [7:0]  body_data;
wire        body_valid;
wire        body_ready;

wire        body_sof;
wire        body_eof;

wire [10:0] body_frame_length;


// ============================================================
// M3-D internal parser interface
//
// The parser payload stream no longer drives the application
// payload ports directly. It is captured by the commit buffer
// instead.
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
// M3-A
// GMII receive adapter
// ============================================================

gmii_rx_adapter #(
    .MAX_RAW_BYTES(
        MAX_RAW_BYTES
    )
)
u_gmii_rx_adapter (

    .clk               (clk),
    .rst               (rst),

    .gmii_rxd          (gmii_rxd),
    .gmii_rx_dv        (gmii_rx_dv),
    .gmii_rx_er        (gmii_rx_er),


    .m_data            (body_data),
    .m_valid           (body_valid),
    .m_ready           (body_ready),

    .m_sof             (body_sof),
    .m_eof             (body_eof),

    .m_frame_length    (body_frame_length),


    .good_frame        (l2_good_frame),

    .output_frame_done (
        l2_output_frame_done
    ),

    .crc_error         (l2_crc_error),
    .format_error      (l2_format_error),
    .length_error      (l2_length_error),
    .rx_error          (l2_rx_error),
    .overflow_error    (l2_overflow_error)
);


// ============================================================
// M3-B
// Ethernet + IPv4 + UDP Parser
// ============================================================

afdx_eth_ipv4_udp_parser #(
    .MAX_PAYLOAD_BYTES(
        MAX_PAYLOAD_BYTES
    )
)
u_parser (

    .clk                (clk),
    .rst                (rst),


    .s_data             (body_data),
    .s_valid            (body_valid),
    .s_ready            (body_ready),

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
// M3-C
// Virtual Link Identification + Whitelist
//
// Consumes the validated metadata produced by M3-B on the
// meta_valid pulse and resolves it to a configured VL.
// ============================================================

afdx_vl_identifier u_vl_identifier (
    .cfg_table(672'd0),

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
// M3-D
// Parser frame interface
//
// These signals stay observable, but the payload stream itself
// is now routed through the commit buffer.
// ============================================================

assign afdx_sequence = parser_sequence;

assign meta_valid    = parser_meta_valid;

assign frame_done    = parser_frame_done;
assign frame_valid   = parser_frame_valid;


wire        seq_result_valid;

wire        seq_accept;
wire        seq_reject;


// ============================================================
// M3-D
// Whitelist error encoding
//
// All M3-C error outputs are single-cycle pulses aligned with
// vl_result_valid.
// ============================================================

reg [7:0] vl_error_code;

always @(*) begin

    if (unknown_vl_error)
        vl_error_code = RX_ERR_VL_UNKNOWN;

    else if (disabled_vl_error)
        vl_error_code = RX_ERR_VL_DISABLED;

    else if (ip_whitelist_error)
        vl_error_code = RX_ERR_IP_WHITELIST;

    else if (udp_whitelist_error)
        vl_error_code = RX_ERR_UDP_WHITELIST;

    else if (length_whitelist_error)
        vl_error_code = RX_ERR_LENGTH_LMAX;

    else
        vl_error_code = RX_ERR_NONE;

end


// ============================================================
// M3-D
// Frame Context Latch
//
// M3-C resolves the VL on the meta_valid pulse, while the AFDX
// sequence number only becomes available with the last byte of
// the Ethernet body.
//
// The VL decision therefore has to be latched and held until
// the frame itself is finally resolved.
// ============================================================

reg        frame_vl_valid;
reg        frame_vl_accept;

reg [1:0]  frame_vl_index;
reg [15:0] frame_vl_id;

reg [7:0]  frame_vl_error;


// ============================================================
// M3-D
// Sequence Integrity request
//
// M3-B latches the sequence byte on the last byte of the
// Ethernet body, therefore the check can only be requested
// together with frame_done.
// ============================================================

wire seq_check_valid =
       parser_frame_done
    && parser_frame_valid
    && frame_vl_valid
    && frame_vl_accept;


// ============================================================
// M3-D
// Frame-level rejection
//
// A frame is rejected without any sequence check when either
// M3-B did not accept it, or M3-C rejected the VL.
//
// Both are only final at frame_done, which is also after the
// payload capture has completed.
// ============================================================

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
// M3-D
// Frame payload capture tracking
//
// frame_payload_captured means:
//
//     "the not yet resolved commit transaction did receive at
//      least one payload byte"
//
// It is deliberately NOT cleared at SOF, because the next
// frame may already start while the previous frame's sequence
// result is still in flight.
//
// It is cleared when the frame gets its final decision.
// ============================================================

reg frame_payload_captured;

wire parser_payload_fire =
    parser_payload_valid && parser_payload_ready;


// ============================================================
// M3-D
// Commit Buffer final decision
//
// Only frames that actually armed the commit buffer need a
// decision. A frame rejected before its first payload byte was
// captured never armed the buffer, so no decision is sent and
// no stale decision can survive into the next frame.
// ============================================================

wire commit_decision_valid =
       frame_payload_captured
    && (frame_reject_at_eof || seq_result_valid);

wire commit_decision_accept =
       seq_result_valid
    && seq_accept;


// ============================================================
// M3-D
// Final frame result
// ============================================================

assign rx_result_valid =
    frame_reject_at_eof || seq_result_valid;

assign rx_accept =
    seq_result_valid && seq_accept;

assign rx_reject =
       frame_reject_at_eof
    || (seq_result_valid && seq_reject);


// ============================================================
// M3-D
// Reported VL metadata
//
// VL identification may never have happened for a rejected
// frame, for example when the IPv4 checksum is bad. In that
// case the VL metadata must be reported as unknown, never as
// the previous frame's VL.
// ============================================================

assign rx_vl_index =
    frame_vl_valid ? frame_vl_index : 2'd0;

assign rx_vl_id =
    frame_vl_valid ? frame_vl_id : 16'd0;


// ============================================================
// M3-D
// Final frame error code
// ============================================================

always @(*) begin

    if (frame_reject_at_eof) begin

        if (parser_reject_at_eof)
            rx_error_code = RX_ERR_PARSER;

        else
            rx_error_code = frame_vl_error;

    end

    else if (seq_result_valid && seq_reject) begin

        if (seq_duplicate_error)
            rx_error_code = RX_ERR_SEQ_DUPLICATE;

        else
            rx_error_code = RX_ERR_SEQ_ORDER;

    end

    else begin

        rx_error_code = RX_ERR_NONE;

    end

end


// ============================================================
// M3-D
// Frame Context Latch
// ============================================================

always @(posedge clk) begin

    if (rst) begin

        frame_vl_valid  <= 1'b0;
        frame_vl_accept <= 1'b0;

        frame_vl_index  <= 2'd0;
        frame_vl_id     <= 16'd0;

        frame_vl_error  <= RX_ERR_NONE;

    end
    else begin

        // ----------------------------------------------------
        // Latch the VL result of the frame being received.
        //
        // This has priority: a new frame must never inherit
        // the previous frame's context.
        // ----------------------------------------------------

        if (vl_result_valid) begin

            frame_vl_valid  <= 1'b1;
            frame_vl_accept <= vl_accept;

            frame_vl_index  <= vl_index;
            frame_vl_id     <= vl_id;

            frame_vl_error  <= vl_error_code;

        end

        // ----------------------------------------------------
        // The frame has been finally resolved.
        // ----------------------------------------------------

        else if (frame_reject_at_eof || seq_result_valid) begin

            frame_vl_valid  <= 1'b0;
            frame_vl_accept <= 1'b0;

            frame_vl_index  <= 2'd0;
            frame_vl_id     <= 16'd0;

            frame_vl_error  <= RX_ERR_NONE;

        end

    end

end


// ============================================================
// M3-D
// Payload capture tracking
// ============================================================

always @(posedge clk) begin

    if (rst) begin

        frame_payload_captured <= 1'b0;

    end
    else begin

        if (parser_payload_fire)
            frame_payload_captured <= 1'b1;

        if (frame_reject_at_eof || seq_result_valid)
            frame_payload_captured <= 1'b0;

    end

end


// ============================================================
// M3-D
// Payload Commit Buffer
//
// Parser payload
//      |
//      v
// Commit Buffer
//      |
//      +-- ACCEPT -> replay to application
//      |
//      +-- REJECT -> discard
// ============================================================

afdx_payload_commit_buffer #(
    .MAX_PAYLOAD_BYTES(
        MAX_PAYLOAD_BYTES
    )
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


    .capture_active  (),
    .frame_buffered  (),
    .replay_active   (),

    .overflow_error  (commit_overflow_error)
);


// ============================================================
// M3-D
// Sequence Integrity
//
// One check per frame that passed both the parser and the VL
// whitelist.
// ============================================================

afdx_sequence_integrity u_sequence_integrity (

    .clk             (clk),
    .rst             (rst),


    .check_valid     (seq_check_valid),

    .vl_index        (frame_vl_index),
    .sequence_number (parser_sequence),


    .result_valid    (seq_result_valid),

    .seq_accept      (seq_accept),
    .seq_reject      (seq_reject),


    .first_frame     (seq_first_frame),
    .reset_sequence  (seq_reset_sequence),
    .single_loss     (seq_single_loss),

    .duplicate_error (seq_duplicate_error),
    .sequence_error  (seq_sequence_error),


    .psn_before      (seq_psn_before),
    .psn_after       (seq_psn_after)
);


endmodule
