`timescale 1ns / 1ps
// LEGACY (M4 TX path): not instantiated by AFDX_competition_top or the
// competition AFDX_top; retained only for legacy ModelSim regression
// coverage. Do not use for new work.

module per_vl_seq_generator (
    input  wire       clk,
    input  wire       rst_n,

    // --------------------------------------------------------
    // One-hot commit from the scheduler transaction.
    //
    // Only the VL that was actually transmitted increments.
    // --------------------------------------------------------
    input  wire [3:0] tx_commit,

    // --------------------------------------------------------
    // Query interface
    //
    // The selected sequence value is the value used for the
    // CURRENT frame. It increments only after tx_commit.
    // --------------------------------------------------------
    input  wire [1:0] query_vl_id,
    output reg  [7:0] query_seq,

    // Debug / verification
    output wire [7:0] seq0,
    output wire [7:0] seq1,
    output wire [7:0] seq2,
    output wire [7:0] seq3
);


    reg [7:0] seq_reg0;
    reg [7:0] seq_reg1;
    reg [7:0] seq_reg2;
    reg [7:0] seq_reg3;


    // ========================================================
    // AFDX sequence progression
    //
    // Reset -> 00
    //
    // 00 -> 01 -> ... -> FF -> 01
    // ========================================================

    function [7:0] next_seq;

        input [7:0] current_seq;

        begin

            if (current_seq == 8'hFF)
                next_seq = 8'h01;
            else
                next_seq = current_seq + 8'd1;

        end

    endfunction


    // ========================================================
    // Per-VL sequence state
    // ========================================================

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            seq_reg0 <= 8'd0;
            seq_reg1 <= 8'd0;
            seq_reg2 <= 8'd0;
            seq_reg3 <= 8'd0;

        end
        else begin

            if (tx_commit[0])
                seq_reg0 <= next_seq(seq_reg0);

            if (tx_commit[1])
                seq_reg1 <= next_seq(seq_reg1);

            if (tx_commit[2])
                seq_reg2 <= next_seq(seq_reg2);

            if (tx_commit[3])
                seq_reg3 <= next_seq(seq_reg3);

        end

    end


    // ========================================================
    // Current sequence query
    // ========================================================

    always @* begin

        case (query_vl_id)

            2'd0:
                query_seq = seq_reg0;

            2'd1:
                query_seq = seq_reg1;

            2'd2:
                query_seq = seq_reg2;

            2'd3:
                query_seq = seq_reg3;

            default:
                query_seq = 8'd0;

        endcase

    end


    // ========================================================
    // Debug outputs
    // ========================================================

    assign seq0 = seq_reg0;
    assign seq1 = seq_reg1;
    assign seq2 = seq_reg2;
    assign seq3 = seq_reg3;


endmodule
