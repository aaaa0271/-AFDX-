module afdx_sequence_integrity
(
    input  wire        clk,
    input  wire        rst,

    // ========================================================
    // One check event per valid + accepted VL frame
    // ========================================================

    input  wire        check_valid,

    input  wire [1:0]  vl_index,
    input  wire [7:0]  sequence_number,

    // ========================================================
    // Result pulse
    // ========================================================

    output reg         result_valid,

    output reg         seq_accept,
    output reg         seq_reject,

    // ========================================================
    // Classification
    // ========================================================

    output reg         first_frame,
    output reg         reset_sequence,
    output reg         single_loss,

    output reg         duplicate_error,
    output reg         sequence_error,

    // ========================================================
    // Debug / verification
    // ========================================================

    output reg  [7:0]  psn_before,
    output reg  [7:0]  psn_after
);


// ============================================================
// Per-VL Previous Sequence Number
//
// Current project:
//     VL0
//     VL1
//     VL2
//     VL3
//
// Each VL MUST maintain independent sequence state.
// ============================================================

reg [7:0] psn_mem [0:3];

reg       psn_valid_mem [0:3];

integer i;


// ============================================================
// AFDX sequence increment
//
// Normal sequence space:
//
//     1 ... 254, 255, 1 ...
//
// 0 is reserved for transmitter reset indication.
// ============================================================

function [7:0] sequence_next;

    input [7:0] value;

    begin

        if (value == 8'hFF)
            sequence_next = 8'h01;
        else
            sequence_next = value + 8'h01;

    end

endfunction


// ============================================================
// Main sequence checker
// ============================================================

always @(posedge clk) begin

    if (rst) begin

        result_valid    <= 1'b0;

        seq_accept      <= 1'b0;
        seq_reject      <= 1'b0;

        first_frame     <= 1'b0;
        reset_sequence  <= 1'b0;
        single_loss     <= 1'b0;

        duplicate_error <= 1'b0;
        sequence_error  <= 1'b0;

        psn_before      <= 8'h00;
        psn_after       <= 8'h00;


        for (i = 0; i < 4; i = i + 1) begin

            psn_mem[i]       <= 8'h00;
            psn_valid_mem[i] <= 1'b0;

        end

    end
    else begin

        // ----------------------------------------------------
        // All result/status outputs are one-clock pulses.
        // ----------------------------------------------------

        result_valid    <= 1'b0;

        seq_accept      <= 1'b0;
        seq_reject      <= 1'b0;

        first_frame     <= 1'b0;
        reset_sequence  <= 1'b0;
        single_loss     <= 1'b0;

        duplicate_error <= 1'b0;
        sequence_error  <= 1'b0;


        // ----------------------------------------------------
        // New frame sequence check
        // ----------------------------------------------------

        if (check_valid) begin

            result_valid <= 1'b1;

            // -----------------------------------------------
            // Verification visibility
            // -----------------------------------------------

            if (psn_valid_mem[vl_index])
                psn_before <= psn_mem[vl_index];
            else
                psn_before <= 8'h00;

            psn_after <= sequence_number;


            // ===============================================
            // CASE 1:
            // First valid frame for this VL after receiver
            // reset.
            //
            // Any SN is accepted.
            // ===============================================

            if (!psn_valid_mem[vl_index]) begin

                seq_accept  <= 1'b1;
                first_frame <= 1'b1;

                // SN=0 still carries transmitter-reset meaning.
                if (sequence_number == 8'h00)
                    reset_sequence <= 1'b1;

            end


            // ===============================================
            // CASE 2:
            // SN = 0
            //
            // Always accepted.
            // Indicates transmitting end-system reset.
            // ===============================================

            else if (sequence_number == 8'h00) begin

                seq_accept     <= 1'b1;
                reset_sequence <= 1'b1;

            end


            // ===============================================
            // CASE 3:
            // Normal increment
            //
            // SN = PSN + 1
            // ===============================================

            else if (
                sequence_number
                ==
                sequence_next(
                    psn_mem[vl_index]
                )
            ) begin

                seq_accept <= 1'b1;

            end


            // ===============================================
            // CASE 4:
            // One missing frame
            //
            // SN = PSN + 2
            //
            // Frame is ACCEPTED, but loss event is reported.
            // ===============================================

            else if (
                sequence_number
                ==
                sequence_next(
                    sequence_next(
                        psn_mem[vl_index]
                    )
                )
            ) begin

                seq_accept  <= 1'b1;
                single_loss <= 1'b1;

            end


            // ===============================================
            // CASE 5:
            // Duplicate frame on this channel
            //
            // Note:
            // A/B redundant-copy elimination belongs to M5
            // High Integrity + A/B Redundancy.
            // ===============================================

            else if (
                sequence_number
                ==
                psn_mem[vl_index]
            ) begin

                seq_reject      <= 1'b1;
                duplicate_error <= 1'b1;

            end


            // ===============================================
            // CASE 6:
            // Other discontinuity / out-of-order / large gap
            // ===============================================

            else begin

                seq_reject     <= 1'b1;
                sequence_error <= 1'b1;

            end


            // ===============================================
            // CRITICAL AFDX RULE
            //
            // PSN is updated from the LAST RECEIVED frame,
            // including a frame rejected by integrity checking.
            //
            // Do NOT put this assignment only inside ACCEPT.
            // ===============================================

            psn_mem[vl_index] <= sequence_number;

            psn_valid_mem[vl_index] <= 1'b1;

        end

    end

end


endmodule
