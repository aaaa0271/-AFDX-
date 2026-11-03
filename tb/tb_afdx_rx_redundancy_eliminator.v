`timescale 1ns / 1ps

module tb_afdx_rx_redundancy_eliminator;


    reg clk;
    reg rst_n;
    reg clear;


    reg        rx_valid;
    wire       rx_ready;

    reg        rx_network;
    reg [1:0]  rx_vl_id;
    reg [7:0]  rx_seq;
    reg [31:0] rx_payload;


    wire        out_valid;
    reg         out_ready;

    wire [1:0]  out_vl_id;
    wire [7:0]  out_seq;
    wire [31:0] out_payload;
    wire        out_network;


    wire accept_event;
    wire duplicate_event;
    wire stale_event;
    wire gap_event;


    wire [31:0] accepted_count;

    wire [31:0] accepted_a_count;
    wire [31:0] accepted_b_count;

    wire [31:0] duplicate_count;

    wire [31:0] cross_network_duplicate_count;
    wire [31:0] same_network_repeat_count;

    wire [31:0] stale_count;
    wire [31:0] sequence_gap_count;


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


    integer error_count;
    integer tc_error;


    afdx_rx_redundancy_eliminator dut (
        .clk                           (clk),
        .rst_n                         (rst_n),

        .clear                         (clear),

        .rx_valid                      (rx_valid),
        .rx_ready                      (rx_ready),

        .rx_network                    (rx_network),
        .rx_vl_id                      (rx_vl_id),
        .rx_seq                        (rx_seq),
        .rx_payload                    (rx_payload),

        .out_valid                     (out_valid),
        .out_ready                     (out_ready),

        .out_vl_id                     (out_vl_id),
        .out_seq                       (out_seq),
        .out_payload                   (out_payload),
        .out_network                   (out_network),

        .accept_event                  (accept_event),
        .duplicate_event               (duplicate_event),
        .stale_event                   (stale_event),
        .gap_event                     (gap_event),

        .accepted_count                (accepted_count),

        .accepted_a_count              (accepted_a_count),
        .accepted_b_count              (accepted_b_count),

        .duplicate_count               (duplicate_count),

        .cross_network_duplicate_count (cross_network_duplicate_count),
        .same_network_repeat_count     (same_network_repeat_count),

        .stale_count                   (stale_count),
        .sequence_gap_count            (sequence_gap_count),

        .last_valid0_dbg               (last_valid0_dbg),
        .last_valid1_dbg               (last_valid1_dbg),
        .last_valid2_dbg               (last_valid2_dbg),
        .last_valid3_dbg               (last_valid3_dbg),

        .last_seq0_dbg                 (last_seq0_dbg),
        .last_seq1_dbg                 (last_seq1_dbg),
        .last_seq2_dbg                 (last_seq2_dbg),
        .last_seq3_dbg                 (last_seq3_dbg),

        .seen_mask0_dbg                (seen_mask0_dbg),
        .seen_mask1_dbg                (seen_mask1_dbg),
        .seen_mask2_dbg                (seen_mask2_dbg),
        .seen_mask3_dbg                (seen_mask3_dbg)
    );


    // ========================================================
    // Clock
    // ========================================================

    initial begin

        clk = 1'b0;

        forever #5 clk = ~clk;

    end


    // ========================================================
    // Reset
    // ========================================================

    task reset_dut;
    begin

        @(negedge clk);

        rst_n = 1'b0;
        clear = 1'b0;

        rx_valid   = 1'b0;
        rx_network = 1'b0;
        rx_vl_id   = 2'd0;
        rx_seq     = 8'd0;
        rx_payload = 32'd0;

        out_ready = 1'b1;


        repeat (2)
            @(posedge clk);


        @(negedge clk);

        rst_n = 1'b1;


        @(posedge clk);
        #1;

    end
    endtask


    // ========================================================
    // Clear
    // ========================================================

    task clear_dut;
    begin

        @(negedge clk);

        rx_valid = 1'b0;
        clear    = 1'b1;


        @(posedge clk);
        #1;


        @(negedge clk);

        clear = 1'b0;

    end
    endtask


    // ========================================================
    // Push exactly one parsed physical frame
    // ========================================================

    task push_frame;

        input        network;
        input [1:0]  vl;
        input [7:0]  seq;
        input [31:0] payload;

    begin : push_frame_body

        @(negedge clk);

        rx_network = network;
        rx_vl_id   = vl;
        rx_seq     = seq;
        rx_payload = payload;

        rx_valid = 1'b1;


        begin : wait_accept

            while (1) begin

                @(posedge clk);

                if (rx_ready)
                    disable wait_accept;

            end

        end


        @(negedge clk);

        rx_valid = 1'b0;

    end
    endtask


    // ========================================================
    // Allow currently-valid logical output to be consumed.
    // ========================================================

    task consume_output;
    begin

        out_ready = 1'b1;

        @(posedge clk);
        #1;

    end
    endtask


    // ========================================================
    // Main
    // ========================================================

    initial begin

        rst_n = 1'b0;
        clear = 1'b0;

        rx_valid   = 1'b0;
        rx_network = 1'b0;
        rx_vl_id   = 2'd0;
        rx_seq     = 8'd0;
        rx_payload = 32'd0;

        out_ready = 1'b1;


        error_count = 0;
        tc_error    = 0;


        // ====================================================
        // M5-D1-01 Reset
        // ====================================================

        reset_dut();

        tc_error = 0;


        if (accepted_count !== 0 ||
            duplicate_count !== 0 ||
            stale_count !== 0 ||
            out_valid !== 0) begin

            $display(
                "ERROR: reset state incorrect"
            );

            error_count = error_count + 1;
            tc_error    = tc_error + 1;

        end


        if (tc_error == 0)
            $display(
                "TC-M5-D1-01 PASS: reset"
            );


        // ====================================================
        // M5-D1-02 First physical copy accepted
        // ====================================================

        clear_dut();

        tc_error = 0;


        push_frame(
            1'b0,
            2'd0,
            8'd10,
            32'hAABBCCDD
        );


        if (!out_valid ||
            out_vl_id !== 2'd0 ||
            out_seq !== 8'd10 ||
            out_payload !== 32'hAABBCCDD ||
            out_network !== 1'b0) begin

            $display(
                "ERROR: first copy output incorrect"
            );

            error_count = error_count + 1;
            tc_error    = tc_error + 1;

        end


        if (accepted_count !== 32'd1 ||
            accepted_a_count !== 32'd1 ||
            last_seq0_dbg !== 8'd10 ||
            seen_mask0_dbg !== 2'b01) begin

            $display(
                "ERROR: first-copy state incorrect"
            );

            error_count = error_count + 1;
            tc_error    = tc_error + 1;

        end


        consume_output();


        if (tc_error == 0)
            $display(
                "TC-M5-D1-02 PASS: first copy accepted"
            );


        // ====================================================
        // M5-D1-03 B-first + A duplicate
        // ====================================================

        clear_dut();

        tc_error = 0;


        push_frame(
            1'b1,
            2'd1,
            8'd7,
            32'h11112222
        );

        consume_output();


        push_frame(
            1'b0,
            2'd1,
            8'd7,
            32'h11112222
        );


        if (accepted_count !== 32'd1 ||
            duplicate_count !== 32'd1 ||
            cross_network_duplicate_count !== 32'd1 ||
            seen_mask1_dbg !== 2'b11) begin

            $display(
                "ERROR: cross-network duplicate handling"
            );

            error_count = error_count + 1;
            tc_error    = tc_error + 1;

        end


        if (out_valid) begin

            $display(
                "ERROR: duplicate leaked to logical output"
            );

            error_count = error_count + 1;
            tc_error    = tc_error + 1;

        end


        if (tc_error == 0)
            $display(
                "TC-M5-D1-03 PASS: first-valid-wins duplicate elimination"
            );


        // ====================================================
        // M5-D1-04 Same-network repeat
        // ====================================================

        clear_dut();

        tc_error = 0;


        push_frame(
            1'b0,
            2'd0,
            8'd9,
            32'h01020304
        );

        consume_output();


        push_frame(
            1'b0,
            2'd0,
            8'd9,
            32'h01020304
        );


        if (duplicate_count !== 32'd1 ||
            same_network_repeat_count !== 32'd1 ||
            cross_network_duplicate_count !== 32'd0) begin

            $display(
                "ERROR: same-network repeat classification"
            );

            error_count = error_count + 1;
            tc_error    = tc_error + 1;

        end


        if (tc_error == 0)
            $display(
                "TC-M5-D1-04 PASS: same-network repeat dropped"
            );


        // ====================================================
        // M5-D1-05 Normal forward sequence
        // ====================================================

        clear_dut();

        tc_error = 0;


        push_frame(
            1'b0,
            2'd0,
            8'd10,
            32'h10000010
        );

        consume_output();


        push_frame(
            1'b1,
            2'd0,
            8'd11,
            32'h10000011
        );


        if (accepted_count !== 32'd2 ||
            last_seq0_dbg !== 8'd11 ||
            out_seq !== 8'd11 ||
            out_network !== 1'b1) begin

            $display(
                "ERROR: forward sequence handling"
            );

            error_count = error_count + 1;
            tc_error    = tc_error + 1;

        end


        consume_output();


        if (tc_error == 0)
            $display(
                "TC-M5-D1-05 PASS: forward sequence"
            );


        // ====================================================
        // M5-D1-06 Sequence wrap 255 -> 1 (zero is reset)
        // ====================================================

        clear_dut();

        tc_error = 0;


        push_frame(
            1'b0,
            2'd2,
            8'hFF,
            32'hFFFF0001
        );

        consume_output();


        push_frame(
            1'b1,
            2'd2,
            8'h01,
            32'h00000002
        );


        if (accepted_count !== 32'd2 ||
            stale_count !== 32'd0 ||
            sequence_gap_count !== 32'd0 ||
            last_seq2_dbg !== 8'h01) begin

            $display(
                "ERROR: sequence wrap handling"
            );

            error_count = error_count + 1;
            tc_error    = tc_error + 1;

        end


        consume_output();


        if (tc_error == 0)
            $display(
                "TC-M5-D1-06 PASS: 255 to 1 wrap"
            );


        // ====================================================
        // M5-D1-07 Sequence gap
        //
        // 10 -> 13 means missing 11 and 12.
        // ====================================================

        clear_dut();

        tc_error = 0;


        push_frame(
            1'b0,
            2'd3,
            8'd10,
            32'h30000010
        );

        consume_output();


        push_frame(
            1'b1,
            2'd3,
            8'd13,
            32'h30000013
        );


        if (accepted_count !== 32'd2 ||
            sequence_gap_count !== 32'd2 ||
            gap_event !== 1'b1 ||
            last_seq3_dbg !== 8'd13) begin

            $display(
                "ERROR: sequence gap detection"
            );

            error_count = error_count + 1;
            tc_error    = tc_error + 1;

        end


        consume_output();


        if (tc_error == 0)
            $display(
                "TC-M5-D1-07 PASS: sequence gap detected"
            );


        // ====================================================
        // M5-D1-08 Stale / out-of-order frame
        // ====================================================

        clear_dut();

        tc_error = 0;


        push_frame(
            1'b0,
            2'd0,
            8'd20,
            32'h20000020
        );

        consume_output();


        push_frame(
            1'b1,
            2'd0,
            8'd19,
            32'h20000019
        );


        if (accepted_count !== 32'd1 ||
            stale_count !== 32'd1 ||
            last_seq0_dbg !== 8'd20 ||
            out_valid !== 1'b0) begin

            $display(
                "ERROR: stale frame handling"
            );

            error_count = error_count + 1;
            tc_error    = tc_error + 1;

        end


        if (tc_error == 0)
            $display(
                "TC-M5-D1-08 PASS: stale frame dropped"
            );


        // ====================================================
        // M5-D1-09 Per-VL isolation
        // ====================================================

        clear_dut();

        tc_error = 0;


        push_frame(
            1'b0,
            2'd0,
            8'd50,
            32'h00000050
        );

        consume_output();


        push_frame(
            1'b1,
            2'd2,
            8'd50,
            32'h22220050
        );


        if (accepted_count !== 32'd2 ||
            last_seq0_dbg !== 8'd50 ||
            last_seq2_dbg !== 8'd50 ||
            !last_valid0_dbg ||
            !last_valid2_dbg) begin

            $display(
                "ERROR: per-VL isolation"
            );

            error_count = error_count + 1;
            tc_error    = tc_error + 1;

        end


        consume_output();


        if (tc_error == 0)
            $display(
                "TC-M5-D1-09 PASS: per-VL sequence isolation"
            );


        // ====================================================
        // M5-D1-10 Output backpressure
        // ====================================================

        clear_dut();

        tc_error = 0;

        out_ready = 1'b0;


        push_frame(
            1'b0,
            2'd0,
            8'd1,
            32'hAAAA0001
        );


        if (!out_valid ||
            out_payload !== 32'hAAAA0001) begin

            $display(
                "ERROR: output did not hold accepted frame"
            );

            error_count = error_count + 1;
            tc_error    = tc_error + 1;

        end


        // Opposite-network duplicate should NOT need output room.
        push_frame(
            1'b1,
            2'd0,
            8'd1,
            32'hAAAA0001
        );


        if (duplicate_count !== 32'd1) begin

            $display(
                "ERROR: duplicate blocked unnecessarily"
            );

            error_count = error_count + 1;
            tc_error    = tc_error + 1;

        end


        // Present a NEW logical frame while output is full.
        @(negedge clk);

        rx_network = 1'b0;
        rx_vl_id   = 2'd1;
        rx_seq     = 8'd1;
        rx_payload = 32'hBBBB0001;
        rx_valid   = 1'b1;


        repeat (3) begin

            @(posedge clk);
            #1;

            if (rx_ready !== 1'b0) begin

                $display(
                    "ERROR: new logical frame not backpressured"
                );

                error_count = error_count + 1;
                tc_error    = tc_error + 1;

            end

        end


        if (accepted_count !== 32'd1) begin

            $display(
                "ERROR: blocked frame was incorrectly accepted"
            );

            error_count = error_count + 1;
            tc_error    = tc_error + 1;

        end


        // Release old output and accept new frame atomically.
        @(negedge clk);

        out_ready = 1'b1;


        @(posedge clk);
        #1;


        @(negedge clk);

        rx_valid = 1'b0;


        if (accepted_count !== 32'd2 ||
            !out_valid ||
            out_vl_id !== 2'd1 ||
            out_payload !== 32'hBBBB0001) begin

            $display(
                "ERROR: backpressure release/replace incorrect"
            );

            error_count = error_count + 1;
            tc_error    = tc_error + 1;

        end


        consume_output();


        if (tc_error == 0)
            $display(
                "TC-M5-D1-10 PASS: output backpressure"
            );


        // ====================================================
        // M5-D1-11 Very late old copy
        // ====================================================

        clear_dut();

        tc_error = 0;


        push_frame(
            1'b0,
            2'd0,
            8'd30,
            32'h00000030
        );

        consume_output();


        push_frame(
            1'b0,
            2'd0,
            8'd31,
            32'h00000031
        );

        consume_output();


        push_frame(
            1'b1,
            2'd0,
            8'd30,
            32'h00000030
        );


        if (accepted_count !== 32'd2 ||
            stale_count !== 32'd1 ||
            last_seq0_dbg !== 8'd31 ||
            out_valid !== 1'b0) begin

            $display(
                "ERROR: delayed old duplicate was not eliminated"
            );

            error_count = error_count + 1;
            tc_error    = tc_error + 1;

        end


        if (tc_error == 0)
            $display(
                "TC-M5-D1-11 PASS: late old copy eliminated"
            );


        // ====================================================
        // FINAL
        // ====================================================

        $display("");
        $display(
            "======================================================"
        );


        if (error_count == 0) begin

            $display(
                "M5-D1 RX REDUNDANCY ELIMINATOR ALL TESTS PASS"
            );

        end
        else begin

            $display(
                "M5-D1 FAILED: %0d error(s)",
                error_count
            );

        end


        $display(
            "======================================================"
        );


        #20;
        $finish;

    end


endmodule
