`timescale 1ns / 1ps

module tb_redundancy_integrity_monitor;


    reg clk;
    reg rst_n;


    reg monitor_clear;
    reg monitor_enable;


    // ========================================================
    // Network A synthetic GMII
    // ========================================================

    reg [7:0] gmii_a_txd;
    reg       gmii_a_tx_en;
    reg       gmii_a_tx_er;

    reg       gmii_a_frame_done;
    reg       gmii_a_underrun;


    // ========================================================
    // Network B synthetic GMII
    // ========================================================

    reg [7:0] gmii_b_txd;
    reg       gmii_b_tx_en;
    reg       gmii_b_tx_er;

    reg       gmii_b_frame_done;
    reg       gmii_b_underrun;


    // ========================================================
    // Monitor outputs
    // ========================================================

    wire redundancy_ok;
    wire fault_event;


    wire [31:0] a_frame_count;
    wire [31:0] b_frame_count;

    wire [31:0] a_active_byte_count;
    wire [31:0] b_active_byte_count;

    wire [31:0] byte_mismatch_count;

    wire [31:0] frame_skew_cycle_count;
    wire [31:0] frame_done_skew_count;

    wire [31:0] tx_er_mismatch_count;

    wire [31:0] a_tx_error_cycle_count;
    wire [31:0] b_tx_error_cycle_count;

    wire [31:0] a_underrun_count;
    wire [31:0] b_underrun_count;

    wire frame_count_match;
    wire active_byte_count_match;


    integer error_count;
    integer tc_error;

    integer k;
    integer f;


    // ========================================================
    // DUT
    // ========================================================

    redundancy_integrity_monitor dut (
        .clk                     (clk),
        .rst_n                   (rst_n),

        .monitor_clear           (monitor_clear),
        .monitor_enable          (monitor_enable),

        .gmii_a_txd              (gmii_a_txd),
        .gmii_a_tx_en            (gmii_a_tx_en),
        .gmii_a_tx_er            (gmii_a_tx_er),
        .gmii_a_frame_done       (gmii_a_frame_done),
        .gmii_a_underrun         (gmii_a_underrun),

        .gmii_b_txd              (gmii_b_txd),
        .gmii_b_tx_en            (gmii_b_tx_en),
        .gmii_b_tx_er            (gmii_b_tx_er),
        .gmii_b_frame_done       (gmii_b_frame_done),
        .gmii_b_underrun         (gmii_b_underrun),

        .redundancy_ok           (redundancy_ok),
        .fault_event             (fault_event),

        .a_frame_count           (a_frame_count),
        .b_frame_count           (b_frame_count),

        .a_active_byte_count     (a_active_byte_count),
        .b_active_byte_count     (b_active_byte_count),

        .byte_mismatch_count     (byte_mismatch_count),

        .frame_skew_cycle_count  (frame_skew_cycle_count),
        .frame_done_skew_count   (frame_done_skew_count),

        .tx_er_mismatch_count    (tx_er_mismatch_count),

        .a_tx_error_cycle_count  (a_tx_error_cycle_count),
        .b_tx_error_cycle_count  (b_tx_error_cycle_count),

        .a_underrun_count        (a_underrun_count),
        .b_underrun_count        (b_underrun_count),

        .frame_count_match       (frame_count_match),
        .active_byte_count_match (active_byte_count_match)
    );


    // ========================================================
    // Clock
    // ========================================================

    initial begin

        clk = 1'b0;

        forever #5 clk = ~clk;

    end


    // ========================================================
    // Idle all physical signals
    // ========================================================

    task idle_gmii;
    begin

        @(negedge clk);

        gmii_a_txd        = 8'h00;
        gmii_a_tx_en      = 1'b0;
        gmii_a_tx_er      = 1'b0;
        gmii_a_frame_done = 1'b0;
        gmii_a_underrun   = 1'b0;

        gmii_b_txd        = 8'h00;
        gmii_b_tx_en      = 1'b0;
        gmii_b_tx_er      = 1'b0;
        gmii_b_frame_done = 1'b0;
        gmii_b_underrun   = 1'b0;

    end
    endtask


    // ========================================================
    // Reset
    // ========================================================

    task reset_dut;
    begin

        @(negedge clk);

        rst_n          = 1'b0;
        monitor_clear  = 1'b0;
        monitor_enable = 1'b0;

        gmii_a_txd        = 8'h00;
        gmii_a_tx_en      = 1'b0;
        gmii_a_tx_er      = 1'b0;
        gmii_a_frame_done = 1'b0;
        gmii_a_underrun   = 1'b0;

        gmii_b_txd        = 8'h00;
        gmii_b_tx_en      = 1'b0;
        gmii_b_tx_er      = 1'b0;
        gmii_b_frame_done = 1'b0;
        gmii_b_underrun   = 1'b0;


        repeat (2)
            @(posedge clk);


        @(negedge clk);

        rst_n          = 1'b1;
        monitor_enable = 1'b1;


        @(posedge clk);
        #1;

    end
    endtask


    // ========================================================
    // Clear sticky state/counters
    //
    // Call only while synthetic GMII is idle.
    // ========================================================

    task clear_monitor;
    begin

        idle_gmii();


        @(negedge clk);

        monitor_clear = 1'b1;


        @(posedge clk);
        #1;


        @(negedge clk);

        monitor_clear = 1'b0;

    end
    endtask


    // ========================================================
    // Send one perfectly identical synthetic frame
    // ========================================================

    task send_identical_frame;

        input integer byte_count;
        input [7:0] start_value;

        integer i;

    begin

        for (i = 0; i < byte_count; i = i + 1) begin

            @(negedge clk);

            gmii_a_tx_en = 1'b1;
            gmii_b_tx_en = 1'b1;

            gmii_a_txd =
                start_value + i;

            gmii_b_txd =
                start_value + i;


            @(posedge clk);
            #1;

        end


        // End physical frame and pulse frame_done together.
        @(negedge clk);

        gmii_a_tx_en = 1'b0;
        gmii_b_tx_en = 1'b0;

        gmii_a_frame_done = 1'b1;
        gmii_b_frame_done = 1'b1;


        @(posedge clk);
        #1;


        @(negedge clk);

        gmii_a_frame_done = 1'b0;
        gmii_b_frame_done = 1'b0;

    end
    endtask


    // ========================================================
    // Main
    // ========================================================

    initial begin

        rst_n = 1'b0;

        monitor_clear  = 1'b0;
        monitor_enable = 1'b0;


        gmii_a_txd        = 8'h00;
        gmii_a_tx_en      = 1'b0;
        gmii_a_tx_er      = 1'b0;
        gmii_a_frame_done = 1'b0;
        gmii_a_underrun   = 1'b0;

        gmii_b_txd        = 8'h00;
        gmii_b_tx_en      = 1'b0;
        gmii_b_tx_er      = 1'b0;
        gmii_b_frame_done = 1'b0;
        gmii_b_underrun   = 1'b0;


        error_count = 0;
        tc_error    = 0;


        // ====================================================
        // M5-B-01 Reset / idle
        // ====================================================

        reset_dut();

        tc_error = 0;


        if (redundancy_ok !== 1'b1) begin

            $display(
                "ERROR: redundancy_ok should be 1 after reset"
            );

            error_count = error_count + 1;
            tc_error    = tc_error + 1;

        end


        if ((a_frame_count !== 0) ||
            (b_frame_count !== 0) ||
            (byte_mismatch_count !== 0) ||
            (frame_skew_cycle_count !== 0)) begin

            $display(
                "ERROR: counters not zero after reset"
            );

            error_count = error_count + 1;
            tc_error    = tc_error + 1;

        end


        if (tc_error == 0)
            $display(
                "TC-M5-B-01 PASS: reset / idle"
            );


        // ====================================================
        // M5-B-02 Healthy identical frame
        // ====================================================

        clear_monitor();

        tc_error = 0;


        send_identical_frame(
            16,
            8'h20
        );


        if ((a_frame_count !== 32'd1) ||
            (b_frame_count !== 32'd1)) begin

            $display(
                "ERROR: healthy frame count expected 1/1 actual %0d/%0d",
                a_frame_count,
                b_frame_count
            );

            error_count = error_count + 1;
            tc_error    = tc_error + 1;

        end


        if ((a_active_byte_count !== 32'd16) ||
            (b_active_byte_count !== 32'd16)) begin

            $display(
                "ERROR: healthy byte count expected 16/16 actual %0d/%0d",
                a_active_byte_count,
                b_active_byte_count
            );

            error_count = error_count + 1;
            tc_error    = tc_error + 1;

        end


        if ((byte_mismatch_count !== 0) ||
            (frame_skew_cycle_count !== 0) ||
            (frame_done_skew_count !== 0) ||
            (tx_er_mismatch_count !== 0)) begin

            $display(
                "ERROR: false redundancy fault during healthy frame"
            );

            error_count = error_count + 1;
            tc_error    = tc_error + 1;

        end


        if (redundancy_ok !== 1'b1) begin

            $display(
                "ERROR: healthy frame cleared redundancy_ok"
            );

            error_count = error_count + 1;
            tc_error    = tc_error + 1;

        end


        if (tc_error == 0)
            $display(
                "TC-M5-B-02 PASS: healthy identical frame"
            );


        // ====================================================
        // M5-B-03 Single-byte corruption
        // ====================================================

        clear_monitor();

        tc_error = 0;


        for (k = 0; k < 8; k = k + 1) begin

            @(negedge clk);

            gmii_a_tx_en = 1'b1;
            gmii_b_tx_en = 1'b1;

            gmii_a_txd =
                8'h80 + k;


            if (k == 3)
                gmii_b_txd =
                    (8'h80 + k) ^ 8'h01;
            else
                gmii_b_txd =
                    8'h80 + k;


            @(posedge clk);
            #1;

        end


        @(negedge clk);

        gmii_a_tx_en = 1'b0;
        gmii_b_tx_en = 1'b0;

        gmii_a_frame_done = 1'b1;
        gmii_b_frame_done = 1'b1;


        @(posedge clk);
        #1;


        @(negedge clk);

        gmii_a_frame_done = 1'b0;
        gmii_b_frame_done = 1'b0;


        if (byte_mismatch_count !== 32'd1) begin

            $display(
                "ERROR: corruption expected byte mismatch=1 actual=%0d",
                byte_mismatch_count
            );

            error_count = error_count + 1;
            tc_error    = tc_error + 1;

        end


        if (redundancy_ok !== 1'b0) begin

            $display(
                "ERROR: corruption did not latch redundancy failure"
            );

            error_count = error_count + 1;
            tc_error    = tc_error + 1;

        end


        if (tc_error == 0)
            $display(
                "TC-M5-B-03 PASS: byte corruption detected"
            );


        // ====================================================
        // M5-B-04 Frame-window skew
        // ====================================================

        clear_monitor();

        tc_error = 0;


        // One A-only physical byte cycle.
        @(negedge clk);

        gmii_a_tx_en = 1'b1;
        gmii_b_tx_en = 1'b0;

        gmii_a_txd = 8'h11;
        gmii_b_txd = 8'h11;


        @(posedge clk);
        #1;


        // Then both transmit together.
        repeat (4) begin

            @(negedge clk);

            gmii_a_tx_en = 1'b1;
            gmii_b_tx_en = 1'b1;

            gmii_a_txd = 8'h22;
            gmii_b_txd = 8'h22;


            @(posedge clk);
            #1;

        end


        @(negedge clk);

        gmii_a_tx_en = 1'b0;
        gmii_b_tx_en = 1'b0;

        gmii_a_frame_done = 1'b1;
        gmii_b_frame_done = 1'b1;


        @(posedge clk);
        #1;


        @(negedge clk);

        gmii_a_frame_done = 1'b0;
        gmii_b_frame_done = 1'b0;


        if (frame_skew_cycle_count !== 32'd1) begin

            $display(
                "ERROR: expected one TX-window skew cycle actual=%0d",
                frame_skew_cycle_count
            );

            error_count = error_count + 1;
            tc_error    = tc_error + 1;

        end


        if (a_active_byte_count !== 32'd5) begin

            $display(
                "ERROR: expected A active bytes=5 actual=%0d",
                a_active_byte_count
            );

            error_count = error_count + 1;
            tc_error    = tc_error + 1;

        end


        if (b_active_byte_count !== 32'd4) begin

            $display(
                "ERROR: expected B active bytes=4 actual=%0d",
                b_active_byte_count
            );

            error_count = error_count + 1;
            tc_error    = tc_error + 1;

        end


        if (redundancy_ok !== 1'b0) begin

            $display(
                "ERROR: frame skew not latched"
            );

            error_count = error_count + 1;
            tc_error    = tc_error + 1;

        end


        if (tc_error == 0)
            $display(
                "TC-M5-B-04 PASS: frame-window skew detected"
            );


        // ====================================================
        // M5-B-05 frame_done skew
        // ====================================================

        clear_monitor();

        tc_error = 0;


        // Four perfectly aligned bytes.
        for (k = 0; k < 4; k = k + 1) begin

            @(negedge clk);

            gmii_a_tx_en = 1'b1;
            gmii_b_tx_en = 1'b1;

            gmii_a_txd = 8'h55 + k;
            gmii_b_txd = 8'h55 + k;


            @(posedge clk);
            #1;

        end


        // A completes first.
        @(negedge clk);

        gmii_a_tx_en = 1'b0;
        gmii_b_tx_en = 1'b0;

        gmii_a_frame_done = 1'b1;
        gmii_b_frame_done = 1'b0;


        @(posedge clk);
        #1;


        // B completes one cycle later.
        @(negedge clk);

        gmii_a_frame_done = 1'b0;
        gmii_b_frame_done = 1'b1;


        @(posedge clk);
        #1;


        @(negedge clk);

        gmii_b_frame_done = 1'b0;


        if (frame_done_skew_count !== 32'd2) begin

            $display(
                "ERROR: expected done-skew cycles=2 actual=%0d",
                frame_done_skew_count
            );

            error_count = error_count + 1;
            tc_error    = tc_error + 1;

        end


        // Both frames did eventually finish.
        if ((a_frame_count !== 32'd1) ||
            (b_frame_count !== 32'd1)) begin

            $display(
                "ERROR: delayed completion frame counts incorrect %0d/%0d",
                a_frame_count,
                b_frame_count
            );

            error_count = error_count + 1;
            tc_error    = tc_error + 1;

        end


        if (redundancy_ok !== 1'b0) begin

            $display(
                "ERROR: frame_done skew not latched"
            );

            error_count = error_count + 1;
            tc_error    = tc_error + 1;

        end


        if (tc_error == 0)
            $display(
                "TC-M5-B-05 PASS: frame_done skew detected"
            );


        // ====================================================
        // M5-B-06 TX error / underrun
        // ====================================================

        clear_monitor();

        tc_error = 0;


        @(negedge clk);

        gmii_a_tx_er    = 1'b1;
        gmii_b_tx_er    = 1'b0;

        gmii_a_underrun = 1'b0;
        gmii_b_underrun = 1'b1;


        @(posedge clk);
        #1;


        @(negedge clk);

        gmii_a_tx_er    = 1'b0;
        gmii_b_tx_er    = 1'b0;

        gmii_a_underrun = 1'b0;
        gmii_b_underrun = 1'b0;


        if (tx_er_mismatch_count !== 32'd1) begin

            $display(
                "ERROR: tx_er mismatch expected=1 actual=%0d",
                tx_er_mismatch_count
            );

            error_count = error_count + 1;
            tc_error    = tc_error + 1;

        end


        if (a_tx_error_cycle_count !== 32'd1) begin

            $display(
                "ERROR: A TX error expected=1 actual=%0d",
                a_tx_error_cycle_count
            );

            error_count = error_count + 1;
            tc_error    = tc_error + 1;

        end


        if (b_underrun_count !== 32'd1) begin

            $display(
                "ERROR: B underrun expected=1 actual=%0d",
                b_underrun_count
            );

            error_count = error_count + 1;
            tc_error    = tc_error + 1;

        end


        if (redundancy_ok !== 1'b0) begin

            $display(
                "ERROR: physical error not latched"
            );

            error_count = error_count + 1;
            tc_error    = tc_error + 1;

        end


        if (tc_error == 0)
            $display(
                "TC-M5-B-06 PASS: physical errors detected"
            );


        // ====================================================
        // M5-B-07 Clear recovery
        // ====================================================

        clear_monitor();

        tc_error = 0;


        if (redundancy_ok !== 1'b1) begin

            $display(
                "ERROR: monitor_clear did not restore redundancy_ok"
            );

            error_count = error_count + 1;
            tc_error    = tc_error + 1;

        end


        if (
            (a_frame_count              !== 0) ||
            (b_frame_count              !== 0) ||
            (a_active_byte_count        !== 0) ||
            (b_active_byte_count        !== 0) ||
            (byte_mismatch_count        !== 0) ||
            (frame_skew_cycle_count     !== 0) ||
            (frame_done_skew_count      !== 0) ||
            (tx_er_mismatch_count       !== 0) ||
            (a_tx_error_cycle_count     !== 0) ||
            (b_tx_error_cycle_count     !== 0) ||
            (a_underrun_count           !== 0) ||
            (b_underrun_count           !== 0)
        ) begin

            $display(
                "ERROR: monitor_clear did not clear all counters"
            );

            error_count = error_count + 1;
            tc_error    = tc_error + 1;

        end


        if (tc_error == 0)
            $display(
                "TC-M5-B-07 PASS: clear recovery"
            );


        // ====================================================
        // M5-B-08 Healthy 4-frame / 288-byte stress
        // ====================================================

        clear_monitor();

        tc_error = 0;


        for (f = 0; f < 4; f = f + 1) begin

            send_identical_frame(
                72,
                8'h10 + (f * 8)
            );

        end


        if ((a_frame_count !== 32'd4) ||
            (b_frame_count !== 32'd4)) begin

            $display(
                "ERROR: stress frames expected 4/4 actual %0d/%0d",
                a_frame_count,
                b_frame_count
            );

            error_count = error_count + 1;
            tc_error    = tc_error + 1;

        end


        if ((a_active_byte_count !== 32'd288) ||
            (b_active_byte_count !== 32'd288)) begin

            $display(
                "ERROR: stress bytes expected 288/288 actual %0d/%0d",
                a_active_byte_count,
                b_active_byte_count
            );

            error_count = error_count + 1;
            tc_error    = tc_error + 1;

        end


        if (
            (byte_mismatch_count    !== 0) ||
            (frame_skew_cycle_count !== 0) ||
            (frame_done_skew_count  !== 0) ||
            (tx_er_mismatch_count   !== 0) ||
            (a_underrun_count       !== 0) ||
            (b_underrun_count       !== 0)
        ) begin

            $display(
                "ERROR: false failure during healthy stress"
            );

            error_count = error_count + 1;
            tc_error    = tc_error + 1;

        end


        if (redundancy_ok !== 1'b1) begin

            $display(
                "ERROR: healthy stress ended unhealthy"
            );

            error_count = error_count + 1;
            tc_error    = tc_error + 1;

        end


        if (!frame_count_match) begin

            $display(
                "ERROR: final frame counts do not match"
            );

            error_count = error_count + 1;
            tc_error    = tc_error + 1;

        end


        if (!active_byte_count_match) begin

            $display(
                "ERROR: final active-byte counts do not match"
            );

            error_count = error_count + 1;
            tc_error    = tc_error + 1;

        end


        if (tc_error == 0)
            $display(
                "TC-M5-B-08 PASS: healthy 4-frame / 288-byte stress"
            );


        // ====================================================
        // FINAL
        // ====================================================

        $display("");
        $display(
            "======================================================"
        );

        $display(
            "A frame count      = %0d",
            a_frame_count
        );

        $display(
            "B frame count      = %0d",
            b_frame_count
        );

        $display(
            "A active bytes     = %0d",
            a_active_byte_count
        );

        $display(
            "B active bytes     = %0d",
            b_active_byte_count
        );

        $display(
            "byte mismatches    = %0d",
            byte_mismatch_count
        );

        $display(
            "frame skew cycles  = %0d",
            frame_skew_cycle_count
        );

        $display(
            "done skew cycles   = %0d",
            frame_done_skew_count
        );

        $display(
            "redundancy_ok      = %0d",
            redundancy_ok
        );

        $display(
            "======================================================"
        );


        if (error_count == 0)
            $display(
                "M5-B REDUNDANCY MONITOR ALL TESTS PASS"
            );
        else
            $display(
                "M5-B FAILED: %0d error(s)",
                error_count
            );


        #20;
        $finish;

    end


endmodule
