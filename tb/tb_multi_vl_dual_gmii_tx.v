`timescale 1ns / 1ps

module tb_multi_vl_dual_gmii_tx;


    localparam MODE_RR = 2'b00;

    localparam TARGET_FRAMES     = 8;
    localparam BODY_BYTES_TOTAL  = 480;
    localparam MAX_TIMEOUT       = 20000;


    // ========================================================
    // Clock / reset
    // ========================================================

    reg clk;
    reg rst_n;


    // ========================================================
    // Scheduler
    // ========================================================

    reg       tx_enable;
    reg [1:0] scheduler_mode;


    // ========================================================
    // Configuration
    // ========================================================

    reg        cfg_we;
    reg [1:0]  cfg_vl_id;

    reg [31:0] cfg_bag;
    reg [15:0] cfg_lmax;
    reg [1:0]  cfg_priority;
    reg [7:0]  cfg_destination;


    // ========================================================
    // Application
    // ========================================================

    reg        app_wr_en;
    reg [1:0]  app_wr_vl_id;
    reg [7:0]  app_wr_data;
    reg [15:0] app_wr_len;

    wire       app_wr_accept;
    wire       app_len_error;


    // ========================================================
    // Network A
    // ========================================================

    wire [7:0] gmii_a_txd;
    wire       gmii_a_tx_en;
    wire       gmii_a_tx_er;

    wire       gmii_a_frame_done;
    wire       gmii_a_underrun;


    // ========================================================
    // Network B
    // ========================================================

    wire [7:0] gmii_b_txd;
    wire       gmii_b_tx_en;
    wire       gmii_b_tx_er;

    wire       gmii_b_frame_done;
    wire       gmii_b_underrun;


    // ========================================================
    // M4 debug
    // ========================================================

    wire       core_busy;
    wire       core_frame_done;

    wire       schedule_fire_dbg;
    wire       frame_start_dbg;

    wire       commit_valid_dbg;
    wire [1:0] commit_vl_id_dbg;
    wire [7:0] commit_data_dbg;
    wire [7:0] commit_seq_dbg;

    wire [1:0] selected_vl_dbg;
    wire [7:0] selected_seq_dbg;

    wire [7:0] core_stream_data_dbg;
    wire       core_stream_valid_dbg;
    wire       core_stream_ready_dbg;

    wire [2:0] fifo_count0_dbg;
    wire [2:0] fifo_count1_dbg;
    wire [2:0] fifo_count2_dbg;
    wire [2:0] fifo_count3_dbg;

    wire [7:0] seq0_dbg;
    wire [7:0] seq1_dbg;
    wire [7:0] seq2_dbg;
    wire [7:0] seq3_dbg;

    wire [1:0] scheduler_mode_active_dbg;


    // ========================================================
    // M5-A2 debug
    // ========================================================

    wire       fork_fire_dbg;

    wire [7:0] a_stream_data_dbg;
    wire       a_stream_valid_dbg;
    wire       a_stream_ready_dbg;

    wire [7:0] b_stream_data_dbg;
    wire       b_stream_valid_dbg;
    wire       b_stream_ready_dbg;

    wire       redundant_frame_done_dbg;


    // ========================================================
    // Counters
    // ========================================================

    integer error_count;

    integer logical_commit_count;
    integer core_done_count;

    integer a_frame_count;
    integer b_frame_count;

    integer fork_fire_count;
    integer a_stream_take_count;
    integer b_stream_take_count;

    integer a_gmii_byte_count;
    integer b_gmii_byte_count;

    integer ab_mismatch_count;

    integer timeout_count;


    // ========================================================
    // Sticky errors
    // ========================================================

    reg a_underrun_seen;
    reg b_underrun_seen;

    reg a_tx_error_seen;
    reg b_tx_error_seen;


    // ========================================================
    // Expected commit sequence
    // ========================================================

    reg [1:0] expected_vl   [0:7];
    reg [7:0] expected_data [0:7];
    reg [7:0] expected_seq  [0:7];


    // ========================================================
    // DUT
    // ========================================================

    multi_vl_dual_gmii_tx_selectable dut (
        .clk                       (clk),
        .rst_n                     (rst_n),

        .tx_enable                 (tx_enable),
        .scheduler_mode            (scheduler_mode),

        .cfg_we                    (cfg_we),
        .cfg_vl_id                 (cfg_vl_id),
        .cfg_bag                   (cfg_bag),
        .cfg_lmax                  (cfg_lmax),
        .cfg_priority              (cfg_priority),
        .cfg_destination           (cfg_destination),

        .app_wr_en                 (app_wr_en),
        .app_wr_vl_id              (app_wr_vl_id),
        .app_wr_data               (app_wr_data),
        .app_wr_len                (app_wr_len),

        .app_wr_accept             (app_wr_accept),
        .app_len_error             (app_len_error),

        .gmii_a_txd                (gmii_a_txd),
        .gmii_a_tx_en              (gmii_a_tx_en),
        .gmii_a_tx_er              (gmii_a_tx_er),
        .gmii_a_frame_done         (gmii_a_frame_done),
        .gmii_a_underrun           (gmii_a_underrun),

        .gmii_b_txd                (gmii_b_txd),
        .gmii_b_tx_en              (gmii_b_tx_en),
        .gmii_b_tx_er              (gmii_b_tx_er),
        .gmii_b_frame_done         (gmii_b_frame_done),
        .gmii_b_underrun           (gmii_b_underrun),

        .core_busy                 (core_busy),
        .core_frame_done           (core_frame_done),

        .schedule_fire_dbg         (schedule_fire_dbg),
        .frame_start_dbg           (frame_start_dbg),

        .commit_valid_dbg          (commit_valid_dbg),
        .commit_vl_id_dbg          (commit_vl_id_dbg),
        .commit_data_dbg           (commit_data_dbg),
        .commit_seq_dbg            (commit_seq_dbg),

        .selected_vl_dbg           (selected_vl_dbg),
        .selected_seq_dbg          (selected_seq_dbg),
        .selected_destination_dbg  (),

        .policy_selected_priority_dbg (),
        .policy_selected_age_dbg      (),
        .policy_selected_score_dbg    (),

        .ba_wait_age0_dbg          (),
        .ba_wait_age1_dbg          (),
        .ba_wait_age2_dbg          (),
        .ba_wait_age3_dbg          (),

        .bag_ready_metrics_dbg     (),
        .eligible_metrics_dbg      (),

        .core_stream_data_dbg      (core_stream_data_dbg),
        .core_stream_valid_dbg     (core_stream_valid_dbg),
        .core_stream_ready_dbg     (core_stream_ready_dbg),

        .fifo_count0_dbg           (fifo_count0_dbg),
        .fifo_count1_dbg           (fifo_count1_dbg),
        .fifo_count2_dbg           (fifo_count2_dbg),
        .fifo_count3_dbg           (fifo_count3_dbg),

        .seq0_dbg                  (seq0_dbg),
        .seq1_dbg                  (seq1_dbg),
        .seq2_dbg                  (seq2_dbg),
        .seq3_dbg                  (seq3_dbg),

        .scheduler_mode_active_dbg (scheduler_mode_active_dbg),

        .fork_fire_dbg             (fork_fire_dbg),

        .a_stream_data_dbg         (a_stream_data_dbg),
        .a_stream_valid_dbg        (a_stream_valid_dbg),
        .a_stream_ready_dbg        (a_stream_ready_dbg),

        .b_stream_data_dbg         (b_stream_data_dbg),
        .b_stream_valid_dbg        (b_stream_valid_dbg),
        .b_stream_ready_dbg        (b_stream_ready_dbg),

        .redundant_frame_done_dbg  (redundant_frame_done_dbg)
    );


    // ========================================================
    // Clock
    // ========================================================

    initial begin

        clk = 1'b0;

        forever #5 clk = ~clk;

    end


    // ========================================================
    // Permanent monitoring
    // ========================================================

    always @(posedge clk) begin

        if (!rst_n) begin

            logical_commit_count = 0;
            core_done_count      = 0;

            a_frame_count        = 0;
            b_frame_count        = 0;

            fork_fire_count      = 0;

            a_stream_take_count  = 0;
            b_stream_take_count  = 0;

            a_gmii_byte_count    = 0;
            b_gmii_byte_count    = 0;

            ab_mismatch_count    = 0;

            a_underrun_seen      = 1'b0;
            b_underrun_seen      = 1'b0;

            a_tx_error_seen      = 1'b0;
            b_tx_error_seen      = 1'b0;

        end
        else begin

            // =================================================
            // M4 invariant must still survive M5.
            // =================================================

            if (schedule_fire_dbg !== frame_start_dbg) begin

                $display(
                    "ERROR: schedule_fire != frame_start at t=%0t",
                    $time
                );

                error_count       = error_count + 1;
                ab_mismatch_count = ab_mismatch_count + 1;

            end


            // =================================================
            // Normal dual-GMII operation must remain aligned.
            // =================================================

            if (gmii_a_tx_en !== gmii_b_tx_en) begin

                $display(
                    "ERROR: A/B tx_en mismatch A=%b B=%b t=%0t",
                    gmii_a_tx_en,
                    gmii_b_tx_en,
                    $time
                );

                error_count       = error_count + 1;
                ab_mismatch_count = ab_mismatch_count + 1;

            end


            if (gmii_a_tx_en &&
                gmii_b_tx_en &&
                (gmii_a_txd !== gmii_b_txd)) begin

                $display(
                    "ERROR: A/B GMII byte mismatch A=%h B=%h t=%0t",
                    gmii_a_txd,
                    gmii_b_txd,
                    $time
                );

                error_count       = error_count + 1;
                ab_mismatch_count = ab_mismatch_count + 1;

            end


            if (gmii_a_tx_er !== gmii_b_tx_er) begin

                $display(
                    "ERROR: A/B tx_er mismatch t=%0t",
                    $time
                );

                error_count       = error_count + 1;
                ab_mismatch_count = ab_mismatch_count + 1;

            end


            if (gmii_a_frame_done !== gmii_b_frame_done) begin

                $display(
                    "ERROR: A/B frame_done skew t=%0t",
                    $time
                );

                error_count       = error_count + 1;
                ab_mismatch_count = ab_mismatch_count + 1;

            end


            // =================================================
            // Logical commit scoreboard
            // =================================================

            if (commit_valid_dbg) begin

                if (logical_commit_count < TARGET_FRAMES) begin

                    if (
                        commit_vl_id_dbg
                        !==
                        expected_vl[logical_commit_count]
                    ) begin

                        $display(
                            "ERROR: commit %0d VL expected=%0d actual=%0d",
                            logical_commit_count,
                            expected_vl[logical_commit_count],
                            commit_vl_id_dbg
                        );

                        error_count = error_count + 1;

                    end


                    if (
                        commit_data_dbg
                        !==
                        expected_data[logical_commit_count]
                    ) begin

                        $display(
                            "ERROR: commit %0d data expected=%h actual=%h",
                            logical_commit_count,
                            expected_data[logical_commit_count],
                            commit_data_dbg
                        );

                        error_count = error_count + 1;

                    end


                    if (
                        commit_seq_dbg
                        !==
                        expected_seq[logical_commit_count]
                    ) begin

                        $display(
                            "ERROR: commit %0d seq expected=%0d actual=%0d",
                            logical_commit_count,
                            expected_seq[logical_commit_count],
                            commit_seq_dbg
                        );

                        error_count = error_count + 1;

                    end

                end
                else begin

                    $display(
                        "ERROR: unexpected extra logical commit"
                    );

                    error_count = error_count + 1;

                end


                logical_commit_count =
                    logical_commit_count + 1;

            end


            // =================================================
            // Frame Builder completion count
            // =================================================

            if (core_frame_done)
                core_done_count =
                    core_done_count + 1;


            // =================================================
            // Fork byte accounting
            // =================================================

            if (fork_fire_dbg)
                fork_fire_count =
                    fork_fire_count + 1;


            if (a_stream_valid_dbg &&
                a_stream_ready_dbg)
                a_stream_take_count =
                    a_stream_take_count + 1;


            if (b_stream_valid_dbg &&
                b_stream_ready_dbg)
                b_stream_take_count =
                    b_stream_take_count + 1;


            // =================================================
            // Physical GMII accounting
            // =================================================

            if (gmii_a_tx_en)
                a_gmii_byte_count =
                    a_gmii_byte_count + 1;


            if (gmii_b_tx_en)
                b_gmii_byte_count =
                    b_gmii_byte_count + 1;


            if (gmii_a_frame_done)
                a_frame_count =
                    a_frame_count + 1;


            if (gmii_b_frame_done)
                b_frame_count =
                    b_frame_count + 1;


            // =================================================
            // Sticky physical faults
            // =================================================

            if (gmii_a_underrun)
                a_underrun_seen = 1'b1;


            if (gmii_b_underrun)
                b_underrun_seen = 1'b1;


            if (gmii_a_tx_er)
                a_tx_error_seen = 1'b1;


            if (gmii_b_tx_er)
                b_tx_error_seen = 1'b1;

        end

    end


    // ========================================================
    // Reset
    // ========================================================

    task reset_dut;
    begin

        @(negedge clk);

        rst_n = 1'b0;

        tx_enable = 1'b0;

        cfg_we    = 1'b0;
        app_wr_en = 1'b0;


        repeat (4)
            @(posedge clk);


        @(negedge clk);

        rst_n = 1'b1;


        repeat (2)
            @(posedge clk);

        #1;

    end
    endtask


    // ========================================================
    // Configure VL
    // ========================================================

    task configure_vl;

        input [1:0] vl;
        input [1:0] priority;
        input [7:0] destination;

    begin

        @(negedge clk);

        cfg_vl_id       = vl;

        cfg_bag         = 32'd0;
        cfg_lmax        = 16'd4;

        cfg_priority    = priority;
        cfg_destination = destination;

        cfg_we = 1'b1;


        @(posedge clk);
        #1;


        cfg_we = 1'b0;

    end
    endtask


    // ========================================================
    // Write one 4-byte descriptor
    // ========================================================

    task write_item;

        input [1:0] vl;
        input [7:0] data_value;

    begin

        @(negedge clk);

        app_wr_vl_id = vl;
        app_wr_data  = data_value;
        app_wr_len   = 16'd4;

        app_wr_en = 1'b1;

        #1;


        if (app_wr_accept !== 1'b1) begin

            $display(
                "ERROR: write rejected VL%0d data=%h",
                vl,
                data_value
            );

            error_count = error_count + 1;

        end


        if (app_len_error !== 1'b0) begin

            $display(
                "ERROR: unexpected app_len_error"
            );

            error_count = error_count + 1;

        end


        @(posedge clk);
        #1;


        app_wr_en = 1'b0;

    end
    endtask


    // ========================================================
    // Main
    // ========================================================

    initial begin

        rst_n = 1'b0;

        tx_enable      = 1'b0;
        scheduler_mode = MODE_RR;


        cfg_we          = 1'b0;
        cfg_vl_id       = 2'd0;

        cfg_bag         = 32'd0;
        cfg_lmax        = 16'd4;
        cfg_priority    = 2'd0;
        cfg_destination = 8'd0;


        app_wr_en       = 1'b0;
        app_wr_vl_id    = 2'd0;
        app_wr_data     = 8'd0;
        app_wr_len      = 16'd4;


        error_count = 0;


        // ====================================================
        // Expected RR commit order
        // ====================================================

        expected_vl[0] = 2'd0;
        expected_vl[1] = 2'd1;
        expected_vl[2] = 2'd2;
        expected_vl[3] = 2'd3;
        expected_vl[4] = 2'd0;
        expected_vl[5] = 2'd1;
        expected_vl[6] = 2'd2;
        expected_vl[7] = 2'd3;


        expected_data[0] = 8'hA0;
        expected_data[1] = 8'hB0;
        expected_data[2] = 8'hC0;
        expected_data[3] = 8'hD0;

        expected_data[4] = 8'hA1;
        expected_data[5] = 8'hB1;
        expected_data[6] = 8'hC1;
        expected_data[7] = 8'hD1;


        expected_seq[0] = 8'd0;
        expected_seq[1] = 8'd0;
        expected_seq[2] = 8'd0;
        expected_seq[3] = 8'd0;

        expected_seq[4] = 8'd1;
        expected_seq[5] = 8'd1;
        expected_seq[6] = 8'd1;
        expected_seq[7] = 8'd1;


        // ====================================================
        // TC-M5-A2-01 Reset + scheduler mode
        // ====================================================

        reset_dut();


        @(negedge clk);

        scheduler_mode = MODE_RR;
        tx_enable       = 1'b0;


        repeat (2)
            @(posedge clk);

        #1;


        if (scheduler_mode_active_dbg !== MODE_RR) begin

            $display(
                "ERROR: RR mode not active"
            );

            error_count = error_count + 1;

        end
        else begin

            $display(
                "TC-M5-A2-01 PASS: reset / RR mode"
            );

        end


        // ====================================================
        // Configure four VLs
        // ====================================================

        configure_vl(
            2'd0,
            2'd1,
            8'd2
        );

        configure_vl(
            2'd1,
            2'd3,
            8'd3
        );

        configure_vl(
            2'd2,
            2'd2,
            8'd4
        );

        configure_vl(
            2'd3,
            2'd0,
            8'd5
        );


        // ====================================================
        // Two frames per VL
        // ====================================================

        write_item(2'd0, 8'hA0);
        write_item(2'd0, 8'hA1);

        write_item(2'd1, 8'hB0);
        write_item(2'd1, 8'hB1);

        write_item(2'd2, 8'hC0);
        write_item(2'd2, 8'hC1);

        write_item(2'd3, 8'hD0);
        write_item(2'd3, 8'hD1);


        if ((fifo_count0_dbg !== 3'd2) ||
            (fifo_count1_dbg !== 3'd2) ||
            (fifo_count2_dbg !== 3'd2) ||
            (fifo_count3_dbg !== 3'd2)) begin

            $display(
                "ERROR: FIFO preload expected 2/2/2/2 actual=%0d/%0d/%0d/%0d",
                fifo_count0_dbg,
                fifo_count1_dbg,
                fifo_count2_dbg,
                fifo_count3_dbg
            );

            error_count = error_count + 1;

        end
        else begin

            $display(
                "TC-M5-A2-02 PASS: workload loaded"
            );

        end


        // ====================================================
        // Start redundant TX
        // ====================================================

        @(negedge clk);

        tx_enable = 1'b1;


        timeout_count = 0;


        while (
            (
                (logical_commit_count < TARGET_FRAMES) ||
                (a_frame_count        < TARGET_FRAMES) ||
                (b_frame_count        < TARGET_FRAMES)
            )
            &&
            (timeout_count < MAX_TIMEOUT)
        ) begin

            @(posedge clk);
            #1;

            timeout_count =
                timeout_count + 1;

        end


        @(negedge clk);

        tx_enable = 1'b0;


        repeat (5)
            @(posedge clk);

        #1;


        // ====================================================
        // TC-M5-A2-03 Logical frame accounting
        // ====================================================

        if (logical_commit_count !== TARGET_FRAMES) begin

            $display(
                "ERROR: logical commits expected=%0d actual=%0d",
                TARGET_FRAMES,
                logical_commit_count
            );

            error_count = error_count + 1;

        end


        if (core_done_count !== TARGET_FRAMES) begin

            $display(
                "ERROR: Frame Builder done expected=%0d actual=%0d",
                TARGET_FRAMES,
                core_done_count
            );

            error_count = error_count + 1;

        end


        if ((fifo_count0_dbg !== 3'd0) ||
            (fifo_count1_dbg !== 3'd0) ||
            (fifo_count2_dbg !== 3'd0) ||
            (fifo_count3_dbg !== 3'd0)) begin

            $display(
                "ERROR: FIFO not empty after transmission"
            );

            error_count = error_count + 1;

        end


        if (error_count == 0)
            $display(
                "TC-M5-A2-03 PASS: logical frame accounting"
            );


        // ====================================================
        // TC-M5-A2-04 Dual physical frame accounting
        // ====================================================

        if (a_frame_count !== TARGET_FRAMES) begin

            $display(
                "ERROR: Network A frames expected=%0d actual=%0d",
                TARGET_FRAMES,
                a_frame_count
            );

            error_count = error_count + 1;

        end


        if (b_frame_count !== TARGET_FRAMES) begin

            $display(
                "ERROR: Network B frames expected=%0d actual=%0d",
                TARGET_FRAMES,
                b_frame_count
            );

            error_count = error_count + 1;

        end


        if (a_frame_count !== b_frame_count) begin

            $display(
                "ERROR: A/B frame count mismatch %0d/%0d",
                a_frame_count,
                b_frame_count
            );

            error_count = error_count + 1;

        end


        if (ab_mismatch_count !== 0) begin

            $display(
                "ERROR: A/B mismatch count=%0d",
                ab_mismatch_count
            );

            error_count = error_count + 1;

        end


        if (a_gmii_byte_count !== b_gmii_byte_count) begin

            $display(
                "ERROR: A/B GMII byte count mismatch %0d/%0d",
                a_gmii_byte_count,
                b_gmii_byte_count
            );

            error_count = error_count + 1;

        end


        if (ab_mismatch_count == 0)
            $display(
                "TC-M5-A2-04 PASS: A/B GMII byte-for-byte identical"
            );


        // ====================================================
        // TC-M5-A2-05 Fork accounting
        // ====================================================

        if (fork_fire_count !== BODY_BYTES_TOTAL) begin

            $display(
                "ERROR: fork source bytes expected=%0d actual=%0d",
                BODY_BYTES_TOTAL,
                fork_fire_count
            );

            error_count = error_count + 1;

        end


        if (a_stream_take_count !== BODY_BYTES_TOTAL) begin

            $display(
                "ERROR: A stream bytes expected=%0d actual=%0d",
                BODY_BYTES_TOTAL,
                a_stream_take_count
            );

            error_count = error_count + 1;

        end


        if (b_stream_take_count !== BODY_BYTES_TOTAL) begin

            $display(
                "ERROR: B stream bytes expected=%0d actual=%0d",
                BODY_BYTES_TOTAL,
                b_stream_take_count
            );

            error_count = error_count + 1;

        end


        if ((fork_fire_count == BODY_BYTES_TOTAL) &&
            (a_stream_take_count == BODY_BYTES_TOTAL) &&
            (b_stream_take_count == BODY_BYTES_TOTAL)) begin

            $display(
                "TC-M5-A2-05 PASS: 480-byte redundant stream accounting"
            );

        end


        // ====================================================
        // TC-M5-A2-06 Sequence state
        // ====================================================

        if ((seq0_dbg !== 8'd2) ||
            (seq1_dbg !== 8'd2) ||
            (seq2_dbg !== 8'd2) ||
            (seq3_dbg !== 8'd2)) begin

            $display(
                "ERROR: final sequence expected 2/2/2/2 actual=%0d/%0d/%0d/%0d",
                seq0_dbg,
                seq1_dbg,
                seq2_dbg,
                seq3_dbg
            );

            error_count = error_count + 1;

        end
        else begin

            $display(
                "TC-M5-A2-06 PASS: per-VL sequence increments once per logical frame"
            );

        end


        // ====================================================
        // Physical error checks
        // ====================================================

        if (a_underrun_seen) begin

            $display(
                "ERROR: Network A underrun"
            );

            error_count = error_count + 1;

        end


        if (b_underrun_seen) begin

            $display(
                "ERROR: Network B underrun"
            );

            error_count = error_count + 1;

        end


        if (a_tx_error_seen) begin

            $display(
                "ERROR: Network A TX error"
            );

            error_count = error_count + 1;

        end


        if (b_tx_error_seen) begin

            $display(
                "ERROR: Network B TX error"
            );

            error_count = error_count + 1;

        end


        // ====================================================
        // FINAL
        // ====================================================

        $display("");
        $display(
            "========================================================"
        );

        $display(
            "Logical commits       = %0d",
            logical_commit_count
        );

        $display(
            "Frame Builder done    = %0d",
            core_done_count
        );

        $display(
            "Network A frames      = %0d",
            a_frame_count
        );

        $display(
            "Network B frames      = %0d",
            b_frame_count
        );

        $display(
            "Fork body bytes       = %0d",
            fork_fire_count
        );

        $display(
            "A body-byte accepts   = %0d",
            a_stream_take_count
        );

        $display(
            "B body-byte accepts   = %0d",
            b_stream_take_count
        );

        $display(
            "A GMII active bytes   = %0d",
            a_gmii_byte_count
        );

        $display(
            "B GMII active bytes   = %0d",
            b_gmii_byte_count
        );

        $display(
            "A/B mismatch count    = %0d",
            ab_mismatch_count
        );

        $display(
            "========================================================"
        );


        if (error_count == 0) begin

            $display(
                "M5-A2 DUAL GMII TX ALL TESTS PASS"
            );

        end
        else begin

            $display(
                "M5-A2 FAILED: %0d error(s)",
                error_count
            );

        end


        #50;
        $finish;

    end


endmodule
