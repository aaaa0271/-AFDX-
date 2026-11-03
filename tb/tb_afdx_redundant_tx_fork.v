`timescale 1ns / 1ps

module tb_afdx_redundant_tx_fork;


    // ========================================================
    // Clock / reset
    // ========================================================

    reg clk;
    reg rst_n;


    // ========================================================
    // Source
    // ========================================================

    reg  [7:0] s_data;
    reg        s_valid;
    wire       s_ready;


    // ========================================================
    // Network A
    // ========================================================

    wire [7:0] a_data;
    wire       a_valid;
    reg        a_ready;


    // ========================================================
    // Network B
    // ========================================================

    wire [7:0] b_data;
    wire       b_valid;
    reg        b_ready;


    // ========================================================
    // Debug
    // ========================================================

    wire fork_fire;


    // ========================================================
    // Counters
    // ========================================================

    integer error_count;
    integer tc_error;

    integer src_fire_count;
    integer a_fire_count;
    integer b_fire_count;

    integer src_before;
    integer a_before;
    integer b_before;

    integer i;


    // ========================================================
    // DUT
    // ========================================================

    afdx_redundant_tx_fork dut (
        .clk       (clk),
        .rst_n     (rst_n),

        .s_data    (s_data),
        .s_valid   (s_valid),
        .s_ready   (s_ready),

        .a_data    (a_data),
        .a_valid   (a_valid),
        .a_ready   (a_ready),

        .b_data    (b_data),
        .b_valid   (b_valid),
        .b_ready   (b_ready),

        .fork_fire (fork_fire)
    );


    // ========================================================
    // Clock
    // ========================================================

    initial begin

        clk = 1'b0;

        forever #5 clk = ~clk;

    end


    // ========================================================
    // Permanent transaction assertions
    //
    // The new multicast fork does NOT require A/B to fire on
    // the same cycle. It only guarantees, per source byte:
    //
    //   A accepts exactly once
    //   B accepts exactly once
    //
    // and the source advances only after both are done.
    // ========================================================

    always @(posedge clk) begin

        // ----------------------------------------------------
        // Whenever a redundant transfer completes, all three
        // copies must carry the same byte.
        // ----------------------------------------------------

        if (fork_fire) begin

            if (a_data !== s_data) begin

                $display(
                    "ERROR: A data mismatch source=%h A=%h at t=%0t",
                    s_data,
                    a_data,
                    $time
                );

                error_count = error_count + 1;

            end


            if (b_data !== s_data) begin

                $display(
                    "ERROR: B data mismatch source=%h B=%h at t=%0t",
                    s_data,
                    b_data,
                    $time
                );

                error_count = error_count + 1;

            end


            if (a_data !== b_data) begin

                $display(
                    "ERROR: A/B data mismatch A=%h B=%h at t=%0t",
                    a_data,
                    b_data,
                    $time
                );

                error_count = error_count + 1;

            end

        end


        // ----------------------------------------------------
        // Transaction counters
        //
        // source_fire = source advances one byte
        // a_fire      = A accepts one byte
        // b_fire      = B accepts one byte
        // ----------------------------------------------------

        if (s_valid && s_ready)
            src_fire_count = src_fire_count + 1;


        if (a_valid && a_ready)
            a_fire_count = a_fire_count + 1;


        if (b_valid && b_ready)
            b_fire_count = b_fire_count + 1;

    end


    // ========================================================
    // Reset
    // ========================================================

    task reset_dut;
    begin

        @(negedge clk);

        rst_n = 1'b0;

        s_valid = 1'b0;
        a_ready = 1'b0;
        b_ready = 1'b0;

        repeat (2)
            @(posedge clk);

        @(negedge clk);

        rst_n = 1'b1;

        @(posedge clk);
        #1;

    end
    endtask


    // ========================================================
    // Send one byte
    // ========================================================

    task send_byte;

        input [7:0] data_value;

    begin : send_byte_body

        @(negedge clk);

        s_data  = data_value;
        s_valid = 1'b1;


        begin : wait_for_accept

            while (1) begin

                @(posedge clk);

                if (s_ready)
                    disable wait_for_accept;

            end

        end


        @(negedge clk);

        s_valid = 1'b0;

    end
    endtask


    // ========================================================
    // Send sequential stream
    // ========================================================

    task send_stream;

        input integer byte_count;
        input [7:0] start_value;

        integer k;

    begin

        for (k = 0; k < byte_count; k = k + 1) begin

            send_byte(
                start_value + k
            );

        end

    end
    endtask


    // ========================================================
    // Deterministic alternating backpressure
    // ========================================================

    task drive_backpressure;

        input integer cycle_count;

        integer k;

    begin

        for (k = 0; k < cycle_count; k = k + 1) begin

            @(negedge clk);

            case (k % 6)

                0: begin
                    a_ready = 1'b1;
                    b_ready = 1'b1;
                end

                1: begin
                    a_ready = 1'b0;
                    b_ready = 1'b1;
                end

                2: begin
                    a_ready = 1'b1;
                    b_ready = 1'b0;
                end

                3: begin
                    a_ready = 1'b0;
                    b_ready = 1'b0;
                end

                4: begin
                    a_ready = 1'b1;
                    b_ready = 1'b1;
                end

                default: begin
                    a_ready = 1'b1;
                    b_ready = 1'b1;
                end

            endcase

        end


        @(negedge clk);

        a_ready = 1'b1;
        b_ready = 1'b1;

    end
    endtask


    // ========================================================
    // Main
    // ========================================================

    initial begin

        rst_n   = 1'b0;

        s_data  = 8'h00;
        s_valid = 1'b0;

        a_ready = 1'b0;
        b_ready = 1'b0;


        error_count = 0;
        tc_error    = 0;


        src_fire_count = 0;
        a_fire_count   = 0;
        b_fire_count   = 0;


        // ====================================================
        // TC-M5-A1-01
        // Reset / idle
        // ====================================================

        reset_dut();

        tc_error = 0;


        if (s_ready !== 1'b0) begin

            $display(
                "ERROR: source ready asserted after reset with no valid"
            );

            error_count = error_count + 1;
            tc_error    = tc_error + 1;

        end


        if (a_valid !== 1'b0) begin

            $display(
                "ERROR: A valid asserted while idle"
            );

            error_count = error_count + 1;
            tc_error    = tc_error + 1;

        end


        if (b_valid !== 1'b0) begin

            $display(
                "ERROR: B valid asserted while idle"
            );

            error_count = error_count + 1;
            tc_error    = tc_error + 1;

        end


        if (fork_fire !== 1'b0) begin

            $display(
                "ERROR: fork_fire asserted while idle"
            );

            error_count = error_count + 1;
            tc_error    = tc_error + 1;

        end


        if (tc_error == 0)
            $display(
                "TC-M5-A1-01 PASS: reset / idle"
            );


        // ====================================================
        // TC-M5-A1-02
        // Both branches ready
        // ====================================================

        tc_error = 0;


        src_before = src_fire_count;
        a_before   = a_fire_count;
        b_before   = b_fire_count;


        @(negedge clk);

        a_ready = 1'b1;
        b_ready = 1'b1;


        send_byte(8'hA5);


        #1;


        if ((src_fire_count - src_before) != 1) begin

            $display(
                "ERROR: expected one source transfer"
            );

            error_count = error_count + 1;
            tc_error    = tc_error + 1;

        end


        if ((a_fire_count - a_before) != 1) begin

            $display(
                "ERROR: expected one A transfer"
            );

            error_count = error_count + 1;
            tc_error    = tc_error + 1;

        end


        if ((b_fire_count - b_before) != 1) begin

            $display(
                "ERROR: expected one B transfer"
            );

            error_count = error_count + 1;
            tc_error    = tc_error + 1;

        end


        if (tc_error == 0)
            $display(
                "TC-M5-A1-02 PASS: simultaneous A/B transfer"
            );


        // ====================================================
        // TC-M5-A1-03
        // Network A stall
        //
        // B may accept first, but source must not advance
        // until A also accepts the SAME byte.
        // ====================================================

        tc_error = 0;


        src_before = src_fire_count;
        a_before   = a_fire_count;
        b_before   = b_fire_count;


        @(negedge clk);

        s_data  = 8'h5A;
        s_valid = 1'b1;

        a_ready = 1'b0;
        b_ready = 1'b1;


        // B accepts on the first accepting edge.
        @(posedge clk);
        #1;


        if ((b_fire_count - b_before) != 1) begin

            $display(
                "ERROR: B did not accept while A stalled"
            );

            error_count = error_count + 1;
            tc_error    = tc_error + 1;

        end


        if ((a_fire_count - a_before) != 0) begin

            $display(
                "ERROR: A accepted while stalled"
            );

            error_count = error_count + 1;
            tc_error    = tc_error + 1;

        end


        if ((src_fire_count - src_before) != 0) begin

            $display(
                "ERROR: source advanced before A completed"
            );

            error_count = error_count + 1;
            tc_error    = tc_error + 1;

        end


        // Source must stay blocked while A is stalled.
        repeat (2) begin

            @(posedge clk);
            #1;

            if (s_ready !== 1'b0) begin

                $display(
                    "ERROR: source advanced while A stalled"
                );

                error_count = error_count + 1;
                tc_error    = tc_error + 1;

            end

        end


        // Release A.
        @(negedge clk);

        a_ready = 1'b1;


        @(posedge clk);
        #1;


        if (fork_fire !== 1'b1) begin

            $display(
                "ERROR: transfer did not complete after A release"
            );

            error_count = error_count + 1;
            tc_error    = tc_error + 1;

        end


        @(negedge clk);

        s_valid = 1'b0;


        if ((src_fire_count - src_before) != 1) begin

            $display(
                "ERROR: source count incorrect after A stall"
            );

            error_count = error_count + 1;
            tc_error    = tc_error + 1;

        end


        if ((a_fire_count - a_before) != 1) begin

            $display(
                "ERROR: A count incorrect after A stall"
            );

            error_count = error_count + 1;
            tc_error    = tc_error + 1;

        end


        if ((b_fire_count - b_before) != 1) begin

            $display(
                "ERROR: B count incorrect after A stall"
            );

            error_count = error_count + 1;
            tc_error    = tc_error + 1;

        end


        if (tc_error == 0)
            $display(
                "TC-M5-A1-03 PASS: A stall (B accepts first, source waits)"
            );


        // ====================================================
        // TC-M5-A1-04
        // Network B stall
        // ====================================================

        tc_error = 0;


        src_before = src_fire_count;
        a_before   = a_fire_count;
        b_before   = b_fire_count;


        @(negedge clk);

        s_data  = 8'hC3;
        s_valid = 1'b1;

        a_ready = 1'b1;
        b_ready = 1'b0;


        @(posedge clk);
        #1;


        if ((a_fire_count - a_before) != 1) begin

            $display(
                "ERROR: A did not accept while B stalled"
            );

            error_count = error_count + 1;
            tc_error    = tc_error + 1;

        end


        if ((b_fire_count - b_before) != 0) begin

            $display(
                "ERROR: B accepted while stalled"
            );

            error_count = error_count + 1;
            tc_error    = tc_error + 1;

        end


        if ((src_fire_count - src_before) != 0) begin

            $display(
                "ERROR: source advanced before B completed"
            );

            error_count = error_count + 1;
            tc_error    = tc_error + 1;

        end


        repeat (2) begin

            @(posedge clk);
            #1;

            if (s_ready !== 1'b0) begin

                $display(
                    "ERROR: source advanced while B stalled"
                );

                error_count = error_count + 1;
                tc_error    = tc_error + 1;

            end

        end


        // Release B.
        @(negedge clk);

        b_ready = 1'b1;


        @(posedge clk);
        #1;


        if (fork_fire !== 1'b1) begin

            $display(
                "ERROR: transfer did not complete after B release"
            );

            error_count = error_count + 1;
            tc_error    = tc_error + 1;

        end


        @(negedge clk);

        s_valid = 1'b0;


        if ((src_fire_count - src_before) != 1) begin

            $display(
                "ERROR: source count incorrect after B stall"
            );

            error_count = error_count + 1;
            tc_error    = tc_error + 1;

        end


        if ((a_fire_count - a_before) != 1) begin

            $display(
                "ERROR: A count incorrect after B stall"
            );

            error_count = error_count + 1;
            tc_error    = tc_error + 1;

        end


        if ((b_fire_count - b_before) != 1) begin

            $display(
                "ERROR: B count incorrect after B stall"
            );

            error_count = error_count + 1;
            tc_error    = tc_error + 1;

        end


        if (tc_error == 0)
            $display(
                "TC-M5-A1-04 PASS: B stall (A accepts first, source waits)"
            );


        // ====================================================
        // TC-M5-A1-05
        // Both branches stalled
        // ====================================================

        tc_error = 0;


        src_before = src_fire_count;
        a_before   = a_fire_count;
        b_before   = b_fire_count;


        @(negedge clk);

        s_data  = 8'h77;
        s_valid = 1'b1;

        a_ready = 1'b0;
        b_ready = 1'b0;


        repeat (4)
            @(posedge clk);


        #1;


        if (fork_fire !== 1'b0) begin

            $display(
                "ERROR: fork fired while both branches stalled"
            );

            error_count = error_count + 1;
            tc_error    = tc_error + 1;

        end


        if ((src_fire_count != src_before) ||
            (a_fire_count   != a_before)   ||
            (b_fire_count   != b_before)) begin

            $display(
                "ERROR: transaction occurred during total stall"
            );

            error_count = error_count + 1;
            tc_error    = tc_error + 1;

        end


        // Release both.
        @(negedge clk);

        a_ready = 1'b1;
        b_ready = 1'b1;


        @(posedge clk);
        #1;


        if (!fork_fire) begin

            $display(
                "ERROR: total-stall transfer did not resume"
            );

            error_count = error_count + 1;
            tc_error    = tc_error + 1;

        end


        @(negedge clk);

        s_valid = 1'b0;


        if (((src_fire_count - src_before) != 1) ||
            ((a_fire_count   - a_before)   != 1) ||
            ((b_fire_count   - b_before)   != 1)) begin

            $display(
                "ERROR: total-stall final counts incorrect"
            );

            error_count = error_count + 1;
            tc_error    = tc_error + 1;

        end


        if (tc_error == 0)
            $display(
                "TC-M5-A1-05 PASS: total stall"
            );


        // ====================================================
        // TC-M5-A1-06
        // Alternating backpressure
        // ====================================================

        tc_error = 0;


        src_before = src_fire_count;
        a_before   = a_fire_count;
        b_before   = b_fire_count;


        fork

            begin

                send_stream(
                    32,
                    8'h40
                );

            end


            begin

                drive_backpressure(
                    120
                );

            end

        join


        #1;


        if ((src_fire_count - src_before) != 32) begin

            $display(
                "ERROR: alternating source count expected=32 actual=%0d",
                src_fire_count - src_before
            );

            error_count = error_count + 1;
            tc_error    = tc_error + 1;

        end


        if ((a_fire_count - a_before) != 32) begin

            $display(
                "ERROR: alternating A count expected=32 actual=%0d",
                a_fire_count - a_before
            );

            error_count = error_count + 1;
            tc_error    = tc_error + 1;

        end


        if ((b_fire_count - b_before) != 32) begin

            $display(
                "ERROR: alternating B count expected=32 actual=%0d",
                b_fire_count - b_before
            );

            error_count = error_count + 1;
            tc_error    = tc_error + 1;

        end


        if (tc_error == 0)
            $display(
                "TC-M5-A1-06 PASS: alternating backpressure"
            );


        // ====================================================
        // TC-M5-A1-07
        // 16-frame stress (960 bytes)
        // ====================================================

        tc_error = 0;


        src_before = src_fire_count;
        a_before   = a_fire_count;
        b_before   = b_fire_count;


        @(negedge clk);

        a_ready = 1'b1;
        b_ready = 1'b1;


        send_stream(
            960,
            8'h00
        );


        #1;


        if ((src_fire_count - src_before) != 960) begin

            $display(
                "ERROR: stress source expected=960 actual=%0d",
                src_fire_count - src_before
            );

            error_count = error_count + 1;
            tc_error    = tc_error + 1;

        end


        if ((a_fire_count - a_before) != 960) begin

            $display(
                "ERROR: stress A expected=960 actual=%0d",
                a_fire_count - a_before
            );

            error_count = error_count + 1;
            tc_error    = tc_error + 1;

        end


        if ((b_fire_count - b_before) != 960) begin

            $display(
                "ERROR: stress B expected=960 actual=%0d",
                b_fire_count - b_before
            );

            error_count = error_count + 1;
            tc_error    = tc_error + 1;

        end


        if (tc_error == 0)
            $display(
                "TC-M5-A1-07 PASS: 16-frame / 960-byte stress"
            );


        // ====================================================
        // TC-M5-A1-08
        // Final transaction accounting
        // ====================================================

        tc_error = 0;


        if (src_fire_count !== a_fire_count) begin

            $display(
                "ERROR: final source/A count mismatch %0d/%0d",
                src_fire_count,
                a_fire_count
            );

            error_count = error_count + 1;
            tc_error    = tc_error + 1;

        end


        if (src_fire_count !== b_fire_count) begin

            $display(
                "ERROR: final source/B count mismatch %0d/%0d",
                src_fire_count,
                b_fire_count
            );

            error_count = error_count + 1;
            tc_error    = tc_error + 1;

        end


        if (a_fire_count !== b_fire_count) begin

            $display(
                "ERROR: final A/B count mismatch %0d/%0d",
                a_fire_count,
                b_fire_count
            );

            error_count = error_count + 1;
            tc_error    = tc_error + 1;

        end


        if (tc_error == 0)
            $display(
                "TC-M5-A1-08 PASS: final lockstep accounting"
            );


        // ====================================================
        // FINAL
        // ====================================================

        $display("");
        $display(
            "=============================================="
        );

        $display(
            "Source transactions = %0d",
            src_fire_count
        );

        $display(
            "Network A transfers = %0d",
            a_fire_count
        );

        $display(
            "Network B transfers = %0d",
            b_fire_count
        );

        $display(
            "=============================================="
        );


        if (error_count == 0) begin

            $display(
                "M5-A1 REDUNDANT TX FORK ALL TESTS PASS"
            );

        end
        else begin

            $display(
                "M5-A1 FAILED: %0d error(s)",
                error_count
            );

        end


        #20;
        $finish;

    end


endmodule
