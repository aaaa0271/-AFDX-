`timescale 1ns / 1ps

// ============================================================
// M5-D2c2
// Dual Payload Frame Arbiter
//
// Purpose:
//
//   Merge replay payload streams from Parser-A and Parser-B
//   commit buffers into one frame-atomic output stream.
//
// CRITICAL PROPERTY:
//
//   Once one network wins arbitration, ownership is locked
//   until that frame's EOF is successfully transferred.
//
// Therefore:
//
//   A frame can NEVER switch to B in the middle,
//   and B can NEVER switch to A in the middle.
//
// Input / output protocol:
//   valid / ready
//   sof
//   eof
//
// Arbitration:
//   - A only -> A
//   - B only -> B
//   - A+B simultaneously -> round-robin
//
// Reset:
//   First simultaneous arbitration -> A
//
// out_network:
//   0 = A
//   1 = B
// ============================================================

module afdx_rx_payload_frame_arbiter (
    input  wire       clk,
    input  wire       rst,

    // ========================================================
    // Payload stream A
    // ========================================================

    input  wire [7:0] a_data,
    input  wire       a_valid,
    output wire       a_ready,
    input  wire       a_sof,
    input  wire       a_eof,

    // ========================================================
    // Payload stream B
    // ========================================================

    input  wire [7:0] b_data,
    input  wire       b_valid,
    output wire       b_ready,
    input  wire       b_sof,
    input  wire       b_eof,

    // ========================================================
    // Merged payload output
    // ========================================================

    output wire [7:0] out_data,
    output wire       out_valid,
    input  wire       out_ready,
    output wire       out_sof,
    output wire       out_eof,

    // Source network of current output frame
    output wire       out_network,

    // Debug
    output wire       frame_active
);


// ============================================================
// State
// ============================================================

localparam [1:0]
    ST_IDLE = 2'd0,
    ST_A    = 2'd1,
    ST_B    = 2'd2;


reg [1:0] state;


// ============================================================
// Round-robin history
//
// 0 = previous completed/selected frame was A
// 1 = previous completed/selected frame was B
//
// Reset to B so first A+B tie selects A.
// ============================================================

reg last_grant;


// ============================================================
// IDLE arbitration
// ============================================================

wire idle_select_a;
wire idle_select_b;


assign idle_select_a =
       (state == ST_IDLE)
    &&
       a_valid
    &&
       (
           !b_valid
           ||
           (last_grant == 1'b1)
       );


assign idle_select_b =
       (state == ST_IDLE)
    &&
       b_valid
    &&
       (
           !a_valid
           ||
           (last_grant == 1'b0)
       );


// ============================================================
// Effective ownership
//
// In IDLE we combinationally select a source so the first byte
// can transfer without inserting an unnecessary bubble.
//
// Once its first byte transfers, state becomes ST_A/ST_B and
// ownership remains locked until EOF handshake.
// ============================================================

wire own_a;
wire own_b;


assign own_a =
       (state == ST_A)
    ||
       idle_select_a;


assign own_b =
       (state == ST_B)
    ||
       idle_select_b;


// ============================================================
// Output mux
// ============================================================

assign out_valid =
       (own_a && a_valid)
    ||
       (own_b && b_valid);


assign out_data =
    own_a
        ? a_data
        : b_data;


assign out_sof =
    own_a
        ? a_sof
        : b_sof;


assign out_eof =
    own_a
        ? a_eof
        : b_eof;


assign out_network =
    own_b;


// ============================================================
// Input ready
//
// Exactly ONE source can receive ready.
//
// During an active frame, the non-owner receives ready=0 for
// the entire frame.
// ============================================================

assign a_ready =
       out_ready
    &&
       own_a;


assign b_ready =
       out_ready
    &&
       own_b;


// ============================================================
// Output handshake
// ============================================================

wire out_fire;

assign out_fire =
       out_valid
    &&
       out_ready;


// ============================================================
// Debug
// ============================================================

assign frame_active =
    (state != ST_IDLE);


// ============================================================
// State machine
// ============================================================

always @(posedge clk) begin

    if (rst) begin

        state <=
            ST_IDLE;

        // First simultaneous tie -> A.
        last_grant <=
            1'b1;

    end
    else begin

        case (state)

            // =================================================
            // IDLE
            // =================================================

            ST_IDLE: begin

                // ---------------------------------------------
                // A wins.
                // ---------------------------------------------

                if (
                    idle_select_a
                    &&
                    out_fire
                ) begin

                    // A has now actually transferred data.
                    last_grant <=
                        1'b0;


                    // Single-byte frame:
                    //
                    // SOF and EOF may theoretically be asserted
                    // on the same transfer.
                    //
                    // In that case do not enter locked state.

                    if (a_eof) begin

                        state <=
                            ST_IDLE;

                    end
                    else begin

                        state <=
                            ST_A;

                    end

                end


                // ---------------------------------------------
                // B wins.
                // ---------------------------------------------

                else if (
                    idle_select_b
                    &&
                    out_fire
                ) begin

                    last_grant <=
                        1'b1;


                    if (b_eof) begin

                        state <=
                            ST_IDLE;

                    end
                    else begin

                        state <=
                            ST_B;

                    end

                end

            end


            // =================================================
            // Locked to A
            // =================================================

            ST_A: begin

                if (
                    out_fire
                    &&
                    a_eof
                ) begin

                    state <=
                        ST_IDLE;

                end

            end


            // =================================================
            // Locked to B
            // =================================================

            ST_B: begin

                if (
                    out_fire
                    &&
                    b_eof
                ) begin

                    state <=
                        ST_IDLE;

                end

            end


            // =================================================
            // Recovery
            // =================================================

            default: begin

                state <=
                    ST_IDLE;

                last_grant <=
                    1'b1;

            end

        endcase

    end

end


endmodule
