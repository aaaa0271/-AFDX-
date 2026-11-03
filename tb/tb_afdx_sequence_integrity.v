`timescale 1ns / 1ps

module tb_afdx_sequence_integrity;


// ============================================================
// Clock / reset
// ============================================================

reg clk;
reg rst;

initial begin

    clk = 1'b0;

    forever #5
        clk = ~clk;

end


// ============================================================
// DUT input
// ============================================================

reg        check_valid;

reg [1:0]  vl_index;
reg [7:0]  sequence_number;


// ============================================================
// DUT output
// ============================================================

wire       result_valid;

wire       seq_accept;
wire       seq_reject;

wire       first_frame;
wire       reset_sequence;
wire       single_loss;

wire       duplicate_error;
wire       sequence_error;

wire [7:0] psn_before;
wire [7:0] psn_after;


// ============================================================
// DUT
// ============================================================

afdx_sequence_integrity dut
(
    .clk             (clk),
    .rst             (rst),

    .check_valid     (check_valid),

    .vl_index        (vl_index),
    .sequence_number (sequence_number),

    .result_valid    (result_valid),

    .seq_accept      (seq_accept),
    .seq_reject      (seq_reject),

    .first_frame     (first_frame),
    .reset_sequence  (reset_sequence),
    .single_loss     (single_loss),

    .duplicate_error (duplicate_error),
    .sequence_error  (sequence_error),

    .psn_before      (psn_before),
    .psn_after       (psn_after)
);


// ============================================================
// Scoreboard
// ============================================================

integer error_count;


// ============================================================
// Test task
// ============================================================

task run_case;

    input integer tc;

    input [1:0] t_vl;
    input [7:0] t_sn;

    input exp_accept;
    input exp_reject;

    input exp_first;
    input exp_reset;
    input exp_loss;

    input exp_duplicate;
    input exp_seq_error;

    input [7:0] exp_psn_before;
    input [7:0] exp_psn_after;

    integer error_before;

    begin

        error_before = error_count;


        // --------------------------------------------
        // Drive input before active clock edge
        // --------------------------------------------

        @(negedge clk);

        vl_index        = t_vl;
        sequence_number = t_sn;
        check_valid     = 1'b1;


        // --------------------------------------------
        // DUT captures here
        // --------------------------------------------

        @(posedge clk);

        #1;


        // --------------------------------------------
        // Result checks
        // --------------------------------------------

        if (result_valid !== 1'b1) begin

            $display(
                "TC-M3D-%0d FAIL: result_valid",
                tc
            );

            error_count = error_count + 1;

        end


        if (seq_accept !== exp_accept) begin

            $display(
                "TC-M3D-%0d FAIL: seq_accept",
                tc
            );

            error_count = error_count + 1;

        end


        if (seq_reject !== exp_reject) begin

            $display(
                "TC-M3D-%0d FAIL: seq_reject",
                tc
            );

            error_count = error_count + 1;

        end


        if (first_frame !== exp_first) begin

            $display(
                "TC-M3D-%0d FAIL: first_frame",
                tc
            );

            error_count = error_count + 1;

        end


        if (reset_sequence !== exp_reset) begin

            $display(
                "TC-M3D-%0d FAIL: reset_sequence",
                tc
            );

            error_count = error_count + 1;

        end


        if (single_loss !== exp_loss) begin

            $display(
                "TC-M3D-%0d FAIL: single_loss",
                tc
            );

            error_count = error_count + 1;

        end


        if (duplicate_error !== exp_duplicate) begin

            $display(
                "TC-M3D-%0d FAIL: duplicate_error",
                tc
            );

            error_count = error_count + 1;

        end


        if (sequence_error !== exp_seq_error) begin

            $display(
                "TC-M3D-%0d FAIL: sequence_error",
                tc
            );

            error_count = error_count + 1;

        end


        if (psn_before !== exp_psn_before) begin

            $display(
                "TC-M3D-%0d FAIL: PSN before = %0d expected %0d",
                tc,
                psn_before,
                exp_psn_before
            );

            error_count = error_count + 1;

        end


        if (psn_after !== exp_psn_after) begin

            $display(
                "TC-M3D-%0d FAIL: PSN after = %0d expected %0d",
                tc,
                psn_after,
                exp_psn_after
            );

            error_count = error_count + 1;

        end


        // --------------------------------------------
        // PASS only when this case added no error
        // --------------------------------------------

        if (error_count == error_before) begin

            $display(
                "TC-M3D-%0d PASS  VL=%0d SN=%0d  PSN:%0d->%0d",
                tc,
                t_vl,
                t_sn,
                psn_before,
                psn_after
            );

        end


        // --------------------------------------------
        // Remove event
        // --------------------------------------------

        @(negedge clk);

        check_valid = 1'b0;


        @(posedge clk);

        #1;


        if (result_valid !== 1'b0) begin

            $display(
                "TC-M3D-%0d FAIL: result_valid not pulse",
                tc
            );

            error_count = error_count + 1;

        end

    end

endtask


// ============================================================
// Main test
// ============================================================

initial begin

    error_count = 0;

    rst             = 1'b1;
    check_valid     = 1'b0;

    vl_index        = 2'd0;
    sequence_number = 8'd0;


    repeat (5)
        @(posedge clk);


    @(negedge clk);

    rst = 1'b0;


    $display("");
    $display("==============================================");
    $display("M3-D SEQUENCE INTEGRITY STANDALONE TEST");
    $display("==============================================");
    $display("");


    // ========================================================
    // TC-001
    // First frame on VL0: arbitrary SN must be accepted.
    // ========================================================

    run_case(
        1,
        2'd0,
        8'd1,
        1, 0,
        1, 0, 0,
        0, 0,
        8'd0,
        8'd1
    );


    // ========================================================
    // TC-002
    // Normal increment 1 -> 2
    // ========================================================

    run_case(
        2,
        2'd0,
        8'd2,
        1, 0,
        0, 0, 0,
        0, 0,
        8'd1,
        8'd2
    );


    // ========================================================
    // TC-003
    // Single frame lost:
    // 2 -> 4, missing SN=3.
    //
    // Must ACCEPT and assert single_loss.
    // ========================================================

    run_case(
        3,
        2'd0,
        8'd4,
        1, 0,
        0, 0, 1,
        0, 0,
        8'd2,
        8'd4
    );


    // ========================================================
    // TC-004
    // Duplicate 4 -> 4
    // ========================================================

    run_case(
        4,
        2'd0,
        8'd4,
        0, 1,
        0, 0, 0,
        1, 0,
        8'd4,
        8'd4
    );


    // ========================================================
    // TC-005
    // Recovery after duplicate.
    // Duplicate frame was rejected but PSN remains 4.
    // 4 -> 5 must pass.
    // ========================================================

    run_case(
        5,
        2'd0,
        8'd5,
        1, 0,
        0, 0, 0,
        0, 0,
        8'd4,
        8'd5
    );


    // ========================================================
    // TC-006
    // VL1 first frame.
    //
    // Demonstrates independent PSN state.
    // ========================================================

    run_case(
        6,
        2'd1,
        8'd200,
        1, 0,
        1, 0, 0,
        0, 0,
        8'd0,
        8'd200
    );


    // ========================================================
    // TC-007
    // VL0 must still remember PSN=5.
    // ========================================================

    run_case(
        7,
        2'd0,
        8'd6,
        1, 0,
        0, 0, 0,
        0, 0,
        8'd5,
        8'd6
    );


    // ========================================================
    // TC-008
    // VL2 first frame near wrap.
    // ========================================================

    run_case(
        8,
        2'd2,
        8'd254,
        1, 0,
        1, 0, 0,
        0, 0,
        8'd0,
        8'd254
    );


    // ========================================================
    // TC-009
    // 254 -> 255
    // ========================================================

    run_case(
        9,
        2'd2,
        8'd255,
        1, 0,
        0, 0, 0,
        0, 0,
        8'd254,
        8'd255
    );


    // ========================================================
    // TC-010
    // AFDX wrap:
    // 255 -> 1
    // ========================================================

    run_case(
        10,
        2'd2,
        8'd1,
        1, 0,
        0, 0, 0,
        0, 0,
        8'd255,
        8'd1
    );


    // ========================================================
    // TC-011
    // SN=0 transmitter reset indication.
    // Always accepted.
    // ========================================================

    run_case(
        11,
        2'd2,
        8'd0,
        1, 0,
        0, 1, 0,
        0, 0,
        8'd1,
        8'd0
    );


    // ========================================================
    // TC-012
    // After reset indication:
    // 0 -> 1
    // ========================================================

    run_case(
        12,
        2'd2,
        8'd1,
        1, 0,
        0, 0, 0,
        0, 0,
        8'd0,
        8'd1
    );


    // ========================================================
    // TC-013
    // VL3 first frame.
    // ========================================================

    run_case(
        13,
        2'd3,
        8'd10,
        1, 0,
        1, 0, 0,
        0, 0,
        8'd0,
        8'd10
    );


    // ========================================================
    // TC-014
    // Large illegal jump.
    //
    // 10 -> 20
    //
    // Reject, but PSN MUST become 20.
    // ========================================================

    run_case(
        14,
        2'd3,
        8'd20,
        0, 1,
        0, 0, 0,
        0, 1,
        8'd10,
        8'd20
    );


    // ========================================================
    // TC-015
    // Critical recovery requirement:
    //
    // If discarded SN=20 was correctly stored as PSN,
    // then 21 must now pass.
    // ========================================================

    run_case(
        15,
        2'd3,
        8'd21,
        1, 0,
        0, 0, 0,
        0, 0,
        8'd20,
        8'd21
    );


    // ========================================================
    // Final result
    // ========================================================

    $display("");
    $display("==============================================");

    if (error_count == 0) begin

        $display("M3-D SEQUENCE INTEGRITY STANDALONE PASS");
        $display("PER-VL PSN VERIFIED");
        $display("NORMAL INCREMENT VERIFIED");
        $display("SINGLE FRAME LOSS VERIFIED");
        $display("DUPLICATE DETECTION VERIFIED");
        $display("255 -> 1 WRAP VERIFIED");
        $display("SN=0 RESET SEMANTICS VERIFIED");
        $display("DISCARDED-FRAME PSN UPDATE VERIFIED");

    end
    else begin

        $fatal(
            1,
            "M3-D SEQUENCE INTEGRITY FAIL: %0d errors",
            error_count
        );

    end

    $display("==============================================");
    $display("");


    #100;

    $finish;

end


// ============================================================
// Global watchdog
// ============================================================

initial begin

    #100000;

    $fatal(
        1,
        "M3-D SEQUENCE INTEGRITY GLOBAL TIMEOUT"
    );

end


endmodule
