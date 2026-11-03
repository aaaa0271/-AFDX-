`timescale 1ns / 1ps

// ============================================================
// M5-D2b : Dual Parsed-Frame Arbiter
//
// Function:
//   Serialize candidate metadata from two M5-D2a parsers
//   (Network A / Network B) into one stream for M5-D1.
//
// IMPORTANT:
//   This module performs NO sequence/redundancy classification.
//
//   It does NOT decide:
//     - duplicate
//     - stale
//     - newer
//     - sequence gap
//     - wrap-around
//
//   Those decisions belong exclusively to M5-D1.
//
// Arbitration:
//   A only       -> A
//   B only       -> B
//   A + B        -> round-robin
//
// Reset behavior:
//   First simultaneous A/B tie grants A.
//
// out_network:
//   0 = Network A
//   1 = Network B
// ============================================================

module afdx_rx_dual_arbiter #(
    parameter integer VL_INDEX_WIDTH = 2,
    parameter integer LENGTH_WIDTH   = 11
)(
    input  wire                         clk,
    input  wire                         rst,

    // ========================================================
    // Parser A candidate
    // ========================================================

    input  wire                         a_valid,
    output wire                         a_ready,

    input  wire [VL_INDEX_WIDTH-1:0]    a_vl_index,
    input  wire [15:0]                  a_vl_id,
    input  wire [LENGTH_WIDTH-1:0]      a_payload_length,
    input  wire [7:0]                   a_sequence,

    // ========================================================
    // Parser B candidate
    // ========================================================

    input  wire                         b_valid,
    output wire                         b_ready,

    input  wire [VL_INDEX_WIDTH-1:0]    b_vl_index,
    input  wire [15:0]                  b_vl_id,
    input  wire [LENGTH_WIDTH-1:0]      b_payload_length,
    input  wire [7:0]                   b_sequence,

    // ========================================================
    // Serialized output -> M5-D1
    // ========================================================

    output wire                         out_valid,
    input  wire                         out_ready,

    output wire                         out_network,

    output wire [VL_INDEX_WIDTH-1:0]    out_vl_index,
    output wire [15:0]                  out_vl_id,
    output wire [LENGTH_WIDTH-1:0]      out_payload_length,
    output wire [7:0]                   out_sequence
);


// ============================================================
// Round-robin state
//
// last_grant:
//   0 = previous successful transfer was A
//   1 = previous successful transfer was B
//
// Reset to 1 so the first A+B tie selects A.
// ============================================================

reg last_grant;


// ============================================================
// Arbitration select
// ============================================================

wire select_a;
wire select_b;


assign select_a =
       a_valid
    &&
       (
           !b_valid
           ||
           (last_grant == 1'b1)
       );


assign select_b =
       b_valid
    &&
       (
           !a_valid
           ||
           (last_grant == 1'b0)
       );


// ============================================================
// Serialized output valid
// ============================================================

assign out_valid =
    select_a
    ||
    select_b;


// ============================================================
// Network ownership
// ============================================================

assign out_network =
    select_b;


// ============================================================
// Metadata mux
// ============================================================

assign out_vl_index =
    select_a
        ? a_vl_index
        : b_vl_index;


assign out_vl_id =
    select_a
        ? a_vl_id
        : b_vl_id;


assign out_payload_length =
    select_a
        ? a_payload_length
        : b_payload_length;


assign out_sequence =
    select_a
        ? a_sequence
        : b_sequence;


// ============================================================
// Input ready
// ============================================================

assign a_ready =
    out_ready
    &&
    select_a;


assign b_ready =
    out_ready
    &&
    select_b;


// ============================================================
// Round-robin update
// ============================================================

always @(posedge clk) begin

    if (rst) begin

        // First simultaneous tie after reset -> A.
        last_grant <= 1'b1;

    end
    else if (
        out_valid
        &&
        out_ready
    ) begin

        if (select_a) begin

            last_grant <= 1'b0;

        end
        else begin

            last_grant <= 1'b1;

        end

    end

end


endmodule
