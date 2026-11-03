`timescale 1ns / 1ps

// ============================================================
// M5-D2c1
// Dual Candidate -> D2b Arbiter -> D1 Eliminator
//                  -> Decision Ownership Router
//
// This module connects:
//
//   Parser-A candidate ----\
//                           > D2b -> D1
//   Parser-B candidate ----/        |
//                                   |
//                            accept / reject
//                                   |
//                          ownership routing
//                            /             \
//                     decision-A      decision-B
//
// IMPORTANT:
//
// 1. This module does NOT contain GMII parsing.
// 2. This module does NOT contain payload replay arbitration.
// 3. D1 is the ONLY sequence / duplicate / stale classifier.
// 4. Decision is returned ONLY to the parser which generated
//    the candidate consumed by D1.
//
// decision_accept:
//   1 = D1 accepted this physical copy
//   0 = duplicate or stale -> parser must discard payload
//
// ============================================================

module afdx_rx_redundancy_decision_core #(
 parameter integer SKEW_MAX_CYCLES=16_000_000
) (
    input  wire        clk,
    input  wire        rst,

    // ========================================================
    // Clear D1 sequence/history/statistics
    // ========================================================

    input  wire        clear,


    // ========================================================
    // Candidate from Parser A
    // ========================================================

    input  wire        a_candidate_valid,
    output wire        a_candidate_ready,

    input  wire [1:0]  a_candidate_vl_index,
    input  wire [15:0] a_candidate_vl_id,
    input  wire [10:0] a_candidate_payload_length,
    input  wire [7:0]  a_candidate_sequence,


    // ========================================================
    // Candidate from Parser B
    // ========================================================

    input  wire        b_candidate_valid,
    output wire        b_candidate_ready,

    input  wire [1:0]  b_candidate_vl_index,
    input  wire [15:0] b_candidate_vl_id,
    input  wire [10:0] b_candidate_payload_length,
    input  wire [7:0]  b_candidate_sequence,


    // ========================================================
    // Decision returned to Parser A
    // ========================================================

    output wire        a_decision_valid,
    output wire        a_decision_accept,


    // ========================================================
    // Decision returned to Parser B
    // ========================================================

    output wire        b_decision_valid,
    output wire        b_decision_accept,


    // ========================================================
    // D1 events exposed for debug / statistics
    // ========================================================

    output wire        accept_event,
    output wire        duplicate_event,
    output wire        stale_event,
    output wire        gap_event,


    // ========================================================
    // D1 statistics
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
    // Debug
    // ========================================================

    output wire        arb_valid,
    output wire        arb_ready,

    output wire        arb_network,

    output wire [1:0]  arb_vl_index,
    output wire [7:0]  arb_sequence,

    output wire        decision_pending_network
);


// ============================================================
// D2b output
// ============================================================

wire        arb_out_valid;
wire        arb_out_ready;

wire        arb_out_network;

wire [1:0]  arb_out_vl_index;
wire [15:0] arb_out_vl_id;
wire [10:0] arb_out_payload_length;
wire [7:0]  arb_out_sequence;


// ============================================================
// D2b
// ============================================================

afdx_rx_dual_arbiter u_dual_arbiter (

    .clk (
        clk
    ),

    .rst (
        rst
    ),


    // --------------------------------------------------------
    // A
    // --------------------------------------------------------

    .a_valid (
        a_candidate_valid
    ),

    .a_ready (
        a_candidate_ready
    ),

    .a_vl_index (
        a_candidate_vl_index
    ),

    .a_vl_id (
        a_candidate_vl_id
    ),

    .a_payload_length (
        a_candidate_payload_length
    ),

    .a_sequence (
        a_candidate_sequence
    ),


    // --------------------------------------------------------
    // B
    // --------------------------------------------------------

    .b_valid (
        b_candidate_valid
    ),

    .b_ready (
        b_candidate_ready
    ),

    .b_vl_index (
        b_candidate_vl_index
    ),

    .b_vl_id (
        b_candidate_vl_id
    ),

    .b_payload_length (
        b_candidate_payload_length
    ),

    .b_sequence (
        b_candidate_sequence
    ),


    // --------------------------------------------------------
    // Serialized output
    // --------------------------------------------------------

    .out_valid (
        arb_out_valid
    ),

    .out_ready (
        arb_out_ready
    ),

    .out_network (
        arb_out_network
    ),

    .out_vl_index (
        arb_out_vl_index
    ),

    .out_vl_id (
        arb_out_vl_id
    ),

    .out_payload_length (
        arb_out_payload_length
    ),

    .out_sequence (
        arb_out_sequence
    )

);


// ============================================================
// D1 interface
// ============================================================

wire d1_rx_ready;


// D1 accepted logical-frame output.
//
// The real payload is NOT carried through D1 in M5-D2.
//
// D2a owns the complete payload inside its commit buffer.
//
// Therefore D1's 32-bit payload field is unused here.
// ============================================================

wire        d1_out_valid;
wire [1:0]  d1_out_vl_id;
wire [7:0]  d1_out_seq;
wire [31:0] d1_out_payload;
wire        d1_out_network;


// ============================================================
// Per-VL D1 debug
// ============================================================

wire       last_valid0_dbg;
wire       last_valid1_dbg;
wire       last_valid2_dbg;
wire       last_valid3_dbg;

wire [7:0] last_seq0_dbg;
wire [7:0] last_seq1_dbg;
wire [7:0] last_seq2_dbg;
wire [7:0] last_seq3_dbg;

wire [1:0] seen_mask0_dbg;
wire [1:0] seen_mask1_dbg;
wire [1:0] seen_mask2_dbg;
wire [1:0] seen_mask3_dbg;


// ============================================================
// Arbiter -> D1
// ============================================================

assign arb_out_ready =
    d1_rx_ready;


// ============================================================
// D1
//
// IMPORTANT:
//
// D1's rx_vl_id is actually the 2-bit internal VL index.
//
// The 16-bit external VL ID remains metadata only.
// ============================================================

afdx_rx_redundancy_eliminator #(.HISTORY_TIMEOUT_CYCLES(SKEW_MAX_CYCLES)) u_redundancy_eliminator (

    .clk (
        clk
    ),

    .rst_n (
        ~rst
    ),

    .clear (
        clear
    ),


    // --------------------------------------------------------
    // Candidate input
    // --------------------------------------------------------

    .rx_valid (
        arb_out_valid
    ),

    .rx_ready (
        d1_rx_ready
    ),

    .rx_network (
        arb_out_network
    ),

    .rx_vl_id (
        arb_out_vl_index
    ),

    .rx_seq (
        arb_out_sequence
    ),


    // D1 does not inspect payload for sequence classification.
    // Actual payload remains inside Parser A/B commit buffers.

    .rx_payload (
        32'd0
    ),


    // --------------------------------------------------------
    // Accepted logical descriptor
    // --------------------------------------------------------

    .out_valid (
        d1_out_valid
    ),

    // Always consume the D1 descriptor.
    //
    // The real accepted payload is replayed later by the
    // selected D2a commit buffer.

    .out_ready (
        1'b1
    ),

    .out_vl_id (
        d1_out_vl_id
    ),

    .out_seq (
        d1_out_seq
    ),

    .out_payload (
        d1_out_payload
    ),

    .out_network (
        d1_out_network
    ),


    // --------------------------------------------------------
    // Events
    // --------------------------------------------------------

    .accept_event (
        accept_event
    ),

    .duplicate_event (
        duplicate_event
    ),

    .stale_event (
        stale_event
    ),

    .gap_event (
        gap_event
    ),


    // --------------------------------------------------------
    // Statistics
    // --------------------------------------------------------

    .accepted_count (
        accepted_count
    ),

    .accepted_a_count (
        accepted_a_count
    ),

    .accepted_b_count (
        accepted_b_count
    ),

    .duplicate_count (
        duplicate_count
    ),

    .cross_network_duplicate_count (
        cross_network_duplicate_count
    ),

    .same_network_repeat_count (
        same_network_repeat_count
    ),

    .stale_count (
        stale_count
    ),

    .sequence_gap_count (
        sequence_gap_count
    ),


    // --------------------------------------------------------
    // Per-VL debug
    // --------------------------------------------------------

    .last_valid0_dbg (
        last_valid0_dbg
    ),

    .last_valid1_dbg (
        last_valid1_dbg
    ),

    .last_valid2_dbg (
        last_valid2_dbg
    ),

    .last_valid3_dbg (
        last_valid3_dbg
    ),

    .last_seq0_dbg (
        last_seq0_dbg
    ),

    .last_seq1_dbg (
        last_seq1_dbg
    ),

    .last_seq2_dbg (
        last_seq2_dbg
    ),

    .last_seq3_dbg (
        last_seq3_dbg
    ),

    .seen_mask0_dbg (
        seen_mask0_dbg
    ),

    .seen_mask1_dbg (
        seen_mask1_dbg
    ),

    .seen_mask2_dbg (
        seen_mask2_dbg
    ),

    .seen_mask3_dbg (
        seen_mask3_dbg
    )

);


// ============================================================
// Candidate accepted by D1 input
// ============================================================

wire d1_rx_fire;

assign d1_rx_fire =
    arb_out_valid
    &&
    d1_rx_ready;


// ============================================================
// Decision ownership pipeline
//
// D1 generates accept/duplicate/stale event AFTER rx_fire.
//
// At that point the arbiter may already be selecting another
// candidate.
//
// Therefore the source network of the consumed candidate MUST
// be registered here.
//
// This register is the ownership tag for the D1 result.
// ============================================================

reg pending_network;


always @(posedge clk) begin

    if (rst) begin

        pending_network <=
            1'b0;

    end
    else if (clear) begin

        pending_network <=
            1'b0;

    end
    else if (d1_rx_fire) begin

        pending_network <=
            arb_out_network;

    end

end


// ============================================================
// Convert D1 event interface into D2a decision interface.
//
// ACCEPT:
//   decision_valid  = 1
//   decision_accept = 1
//
// DUPLICATE / STALE:
//   decision_valid  = 1
//   decision_accept = 0
//
// GAP is NOT a rejection.
// A gap frame is still accepted.
// ============================================================

wire d1_decision_valid;
wire d1_decision_accept;


assign d1_decision_valid =
       accept_event
    || duplicate_event
    || stale_event;


assign d1_decision_accept =
    accept_event;


// ============================================================
// Decision ownership routing
//
// Never broadcast a decision to both parsers.
// ============================================================

assign a_decision_valid =
       d1_decision_valid
    &&
       (pending_network == 1'b0);


assign b_decision_valid =
       d1_decision_valid
    &&
       (pending_network == 1'b1);


assign a_decision_accept =
       a_decision_valid
    &&
       d1_decision_accept;


assign b_decision_accept =
       b_decision_valid
    &&
       d1_decision_accept;


// ============================================================
// Debug outputs
// ============================================================

assign arb_valid =
    arb_out_valid;


assign arb_ready =
    arb_out_ready;


assign arb_network =
    arb_out_network;


assign arb_vl_index =
    arb_out_vl_index;


assign arb_sequence =
    arb_out_sequence;


assign decision_pending_network =
    pending_network;


endmodule
