`timescale 1ns / 1ps

module tb_m5c_fault_degraded;


    localparam MODE_RR = 2'b00;

    localparam MAX_TIMEOUT = 20000;


    reg clk;
    reg rst_n;


    // ========================================================
    // Scheduler / network control
    // ========================================================

    reg       tx_enable;
    reg [1:0] scheduler_mode;

    reg network_a_enable;
    reg network_b_enable;


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
    // Raw GMII (from degraded TX top)
    // ========================================================

    wire [7:0] gmii_a_txd;
    wire       gmii_a_tx_en;
    wire       gmii_a_tx_er;
    wire       gmii_a_frame_done;
    wire       gmii_a_underrun;

    wire [7:0] gmii_b_txd;
    wire       gmii_b_tx_en;
    wire       gmii_b_tx_er;
    wire       gmii_b_frame_done;
    wire       gmii_b_underrun;


    // ========================================================
    // DUT debug
    // ========================================================

    wire       core_busy;
    wire       core_frame_done;

    wire       schedule_fire_dbg;
    wire       frame_start_dbg;

    wire       commit_valid_dbg;
    wire [1:0] commit_vl_id_dbg;
    wire [7:0] commit_data_dbg;
    wire [7:0] commit_seq_dbg;

    wire [2:0] fifo_count0_dbg;
    wire [2:0] fifo_count1_dbg;
    wire [2:0] fifo_count2_dbg;
    wire [2:0] fifo_count3_dbg;

    wire [7:0] seq0_dbg;
    wire [7:0] seq1_dbg;
    wire [7:0] seq2_dbg;
    wire [7:0] seq3_dbg;

    wire [1:0] scheduler_mode_active_dbg;

    wire       network_a_active_dbg;
    wire       network_b_active_dbg;
    wire       any_network_enabled_dbg;
    wire       degraded_mode_dbg;


    // ========================================================
    // Fault injector A control
    // ========================================================

    reg        fault_enable_a;
    reg        corrupt_byte_enable_a;
    reg [15:0] corrupt_byte_index_a;
    reg [7:0]  corrupt_xor_mask_a;
    reg        drop_byte_enable_a;
    reg [15:0] drop_byte_index_a;
    reg        tx_error_byte_enable_a;
    reg [15:0] tx_error_byte_index_a;
    reg        drop_frame_done_enable_a;
    reg        mute_link_a;


    // ========================================================
    // Fault injector B control
    // ========================================================

    reg        fault_enable_b;
    reg        corrupt_byte_enable_b;
    reg [15:0] corrupt_byte_index_b;
    reg [7:0]  corrupt_xor_mask_b;
    reg        drop_byte_enable_b;
    reg [15:0] drop_byte_index_b;
    reg        tx_error_byte_enable_b;
    reg [15:0] tx_error_byte_index_b;
    reg        drop_frame_done_enable_b;
    reg        mute_link_b;


    // ========================================================
    // Faulted GMII (after injectors)
    // ========================================================

    wire [7:0] fa_txd;
    wire       fa_tx_en;
    wire       fa_tx_er;
    wire       fa_frame_done;
    wire       fa_underrun;

    wire [7:0] fb_txd;
    wire       fb_tx_en;
    wire       fb_tx_er;
    wire       fb_frame_done;
    wire       fb_underrun;


    // ========================================================
    // Monitor
    // ========================================================

    wire monitor_dual_mode_enable;

    wire        mon_redundancy_ok;
    wire [31:0] mon_a_frame_count;
    wire [31:0] mon_b_frame_count;
    wire [31:0] mon_a_active_byte_count;
    wire [31:0] mon_b_active_byte_count;
    wire [31:0] mon_byte_mismatch_count;
    wire [31:0] mon_frame_skew_cycle_count;
    wire [31:0] mon_frame_done_skew_count;
    wire [31:0] mon_tx_er_mismatch_count;
    wire [31:0] mon_a_tx_error_cycle_count;
    wire [31:0] mon_b_tx_error_cycle_count;
    wire [31:0] mon_a_underrun_count;
    wire [31:0] mon_b_underrun_count;


    assign monitor_dual_mode_enable =
        network_a_active_dbg &&
        network_b_active_dbg;


    // ========================================================
    // TB bookkeeping
    // ========================================================

    integer error_count;
    integer tc_error;

    integer logical_commit_count;
    integer core_done_count;
    integer a_frame_count;
    integer b_frame_count;

    integer timeout_count;


    // ========================================================
    // DUT
    // ========================================================

    multi_vl_dual_gmii_tx_degraded dut (
        .clk                       (clk),
        .rst_n                     (rst_n),

        .tx_enable                 (tx_enable),
        .scheduler_mode            (scheduler_mode),

        .network_a_enable          (network_a_enable),
        .network_b_enable          (network_b_enable),

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

        .selected_vl_dbg           (),
        .selected_seq_dbg          (),
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

        .core_stream_data_dbg      (),
        .core_stream_valid_dbg     (),
        .core_stream_ready_dbg     (),

        .fifo_count0_dbg           (fifo_count0_dbg),
        .fifo_count1_dbg           (fifo_count1_dbg),
        .fifo_count2_dbg           (fifo_count2_dbg),
        .fifo_count3_dbg           (fifo_count3_dbg),

        .seq0_dbg                  (seq0_dbg),
        .seq1_dbg                  (seq1_dbg),
        .seq2_dbg                  (seq2_dbg),
        .seq3_dbg                  (seq3_dbg),

        .scheduler_mode_active_dbg (scheduler_mode_active_dbg),

        .fork_fire_dbg             (),
        .a_stream_data_dbg         (),
        .a_stream_valid_dbg        (),
        .a_stream_ready_dbg        (),
        .b_stream_data_dbg         (),
        .b_stream_valid_dbg        (),
        .b_stream_ready_dbg        (),
        .redundant_frame_done_dbg  (),

        .network_a_active_dbg      (network_a_active_dbg),
        .network_b_active_dbg      (network_b_active_dbg),
        .any_network_enabled_dbg   (any_network_enabled_dbg),
        .degraded_mode_dbg         (degraded_mode_dbg)
    );


    // ========================================================
    // Fault injector A
    // ========================================================

    gmii_fault_injector inj_a (
        .clk                   (clk),
        .rst_n                 (rst_n),

        .in_txd                (gmii_a_txd),
        .in_tx_en              (gmii_a_tx_en),
        .in_tx_er              (gmii_a_tx_er),
        .in_frame_done         (gmii_a_frame_done),
        .in_underrun           (gmii_a_underrun),

        .fault_enable          (fault_enable_a),
        .corrupt_byte_enable   (corrupt_byte_enable_a),
        .corrupt_byte_index    (corrupt_byte_index_a),
        .corrupt_xor_mask      (corrupt_xor_mask_a),
        .drop_byte_enable      (drop_byte_enable_a),
        .drop_byte_index       (drop_byte_index_a),
        .tx_error_byte_enable  (tx_error_byte_enable_a),
        .tx_error_byte_index   (tx_error_byte_index_a),
        .drop_frame_done_enable (drop_frame_done_enable_a),
        .mute_link             (mute_link_a),

        .out_txd               (fa_txd),
        .out_tx_en             (fa_tx_en),
        .out_tx_er             (fa_tx_er),
        .out_frame_done        (fa_frame_done),
        .out_underrun          (fa_underrun),

        .active_byte_index_dbg (),
        .fault_applied_dbg     ()
    );


    // ========================================================
    // Fault injector B
    // ========================================================

    gmii_fault_injector inj_b (
        .clk                   (clk),
        .rst_n                 (rst_n),

        .in_txd                (gmii_b_txd),
        .in_tx_en              (gmii_b_tx_en),
        .in_tx_er              (gmii_b_tx_er),
        .in_frame_done         (gmii_b_frame_done),
        .in_underrun           (gmii_b_underrun),

        .fault_enable          (fault_enable_b),
        .corrupt_byte_enable   (corrupt_byte_enable_b),
        .corrupt_byte_index    (corrupt_byte_index_b),
        .corrupt_xor_mask      (corrupt_xor_mask_b),
        .drop_byte_enable      (drop_byte_enable_b),
        .drop_byte_index       (drop_byte_index_b),
        .tx_error_byte_enable  (tx_error_byte_enable_b),
        .tx_error_byte_index   (tx_error_byte_index_b),
        .drop_frame_done_enable (drop_frame_done_enable_b),
        .mute_link             (mute_link_b),

        .out_txd               (fb_txd),
        .out_tx_en             (fb_tx_en),
        .out_tx_er             (fb_tx_er),
        .out_frame_done        (fb_frame_done),
        .out_underrun          (fb_underrun),

        .active_byte_index_dbg (),
        .fault_applied_dbg     ()
    );


    // ========================================================
    // M5-B integrity monitor (observes faulted GMII)
    // ========================================================

    redundancy_integrity_monitor u_monitor (
        .clk                     (clk),
        .rst_n                   (rst_n),

        .monitor_clear           (1'b0),
        .monitor_enable          (monitor_dual_mode_enable),

        .gmii_a_txd              (fa_txd),
        .gmii_a_tx_en            (fa_tx_en),
        .gmii_a_tx_er            (fa_tx_er),
        .gmii_a_frame_done       (fa_frame_done),
        .gmii_a_underrun         (fa_underrun),

        .gmii_b_txd              (fb_txd),
        .gmii_b_tx_en            (fb_tx_en),
        .gmii_b_tx_er            (fb_tx_er),
        .gmii_b_frame_done       (fb_frame_done),
        .gmii_b_underrun         (fb_underrun),

        .redundancy_ok           (mon_redundancy_ok),
        .fault_event             (),

        .a_frame_count           (mon_a_frame_count),
        .b_frame_count           (mon_b_frame_count),
        .a_active_byte_count     (mon_a_active_byte_count),
        .b_active_byte_count     (mon_b_active_byte_count),
        .byte_mismatch_count     (mon_byte_mismatch_count),
        .frame_skew_cycle_count  (mon_frame_skew_cycle_count),
        .frame_done_skew_count   (mon_frame_done_skew_count),
        .tx_er_mismatch_count    (mon_tx_er_mismatch_count),
        .a_tx_error_cycle_count  (mon_a_tx_error_cycle_count),
        .b_tx_error_cycle_count  (mon_b_tx_error_cycle_count),
        .a_underrun_count        (mon_a_underrun_count),
        .b_underrun_count        (mon_b_underrun_count),
        .frame_count_match       (),
        .active_byte_count_match ()
    );


    // ========================================================
    // Clock
    // ========================================================

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end


    // ========================================================
    // Permanent counters
    // ========================================================

    always @(posedge clk) begin

        if (!rst_n) begin
            logical_commit_count = 0;
            core_done_count      = 0;
            a_frame_count        = 0;
            b_frame_count        = 0;
        end
        else begin
            if (commit_valid_dbg)
                logical_commit_count = logical_commit_count + 1;
            if (core_frame_done)
                core_done_count = core_done_count + 1;
            if (gmii_a_frame_done)
                a_frame_count = a_frame_count + 1;
            if (gmii_b_frame_done)
                b_frame_count = b_frame_count + 1;
        end

    end


    // ========================================================
    // Tasks
    // ========================================================

    task reset_dut;
    begin
        @(negedge clk);
        rst_n = 1'b0;
        tx_enable = 1'b0;
        cfg_we = 1'b0;
        app_wr_en = 1'b0;
        scheduler_mode = MODE_RR;

        network_a_enable = 1'b1;
        network_b_enable = 1'b1;

        clear_faults();

        repeat (4) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);
        #1;
    end
    endtask


    task clear_faults;
    begin
        fault_enable_a = 1'b0;
        corrupt_byte_enable_a = 1'b0;
        corrupt_byte_index_a = 16'd0;
        corrupt_xor_mask_a = 8'h00;
        drop_byte_enable_a = 1'b0;
        drop_byte_index_a = 16'd0;
        tx_error_byte_enable_a = 1'b0;
        tx_error_byte_index_a = 16'd0;
        drop_frame_done_enable_a = 1'b0;
        mute_link_a = 1'b0;

        fault_enable_b = 1'b0;
        corrupt_byte_enable_b = 1'b0;
        corrupt_byte_index_b = 16'd0;
        corrupt_xor_mask_b = 8'h00;
        drop_byte_enable_b = 1'b0;
        drop_byte_index_b = 16'd0;
        tx_error_byte_enable_b = 1'b0;
        tx_error_byte_index_b = 16'd0;
        drop_frame_done_enable_b = 1'b0;
        mute_link_b = 1'b0;
    end
    endtask


    task configure_vl;
        input [1:0] vl;
        input [1:0] priority;
        input [7:0] destination;
    begin
        @(negedge clk);
        cfg_vl_id = vl;
        cfg_bag = 32'd0;
        cfg_lmax = 16'd4;
        cfg_priority = priority;
        cfg_destination = destination;
        cfg_we = 1'b1;
        @(posedge clk); #1;
        cfg_we = 1'b0;
    end
    endtask


    task write_item;
        input [1:0] vl;
        input [7:0] data;
    begin
        @(negedge clk);
        app_wr_vl_id = vl;
        app_wr_data = data;
        app_wr_len = 16'd4;
        app_wr_en = 1'b1;
        #1;
        if (app_wr_accept !== 1'b1) begin
            $display("ERROR: write rejected VL%0d", vl);
            error_count = error_count + 1;
            tc_error = tc_error + 1;
        end
        @(posedge clk); #1;
        app_wr_en = 1'b0;
    end
    endtask


    // Configure 4 VLs with two frames each (total 8).
    task setup_workload_8;
    begin
        configure_vl(2'd0, 2'd1, 8'd2);
        configure_vl(2'd1, 2'd3, 8'd3);
        configure_vl(2'd2, 2'd2, 8'd4);
        configure_vl(2'd3, 2'd0, 8'd5);

        write_item(2'd0, 8'hA0);
        write_item(2'd0, 8'hA1);
        write_item(2'd1, 8'hB0);
        write_item(2'd1, 8'hB1);
        write_item(2'd2, 8'hC0);
        write_item(2'd2, 8'hC1);
        write_item(2'd3, 8'hD0);
        write_item(2'd3, 8'hD1);
    end
    endtask


    // Configure a single VL with one frame.
    task setup_workload_1;
    begin
        configure_vl(2'd0, 2'd1, 8'd2);
        write_item(2'd0, 8'hA0);
    end
    endtask


    // Wait until N raw-A frames have completed.
    task wait_a_frames;
        input integer n;
    begin
        timeout_count = 0;
        while ((a_frame_count < n) && (timeout_count < MAX_TIMEOUT)) begin
            @(posedge clk);
            timeout_count = timeout_count + 1;
        end
    end
    endtask


    // ========================================================
    // Main
    // ========================================================

    initial begin

        rst_n = 1'b0;
        tx_enable = 1'b0;
        scheduler_mode = MODE_RR;
        network_a_enable = 1'b1;
        network_b_enable = 1'b1;

        cfg_we = 1'b0;
        cfg_vl_id = 2'd0;
        cfg_bag = 32'd0;
        cfg_lmax = 16'd4;
        cfg_priority = 2'd0;
        cfg_destination = 8'd0;

        app_wr_en = 1'b0;
        app_wr_vl_id = 2'd0;
        app_wr_data = 8'd0;
        app_wr_len = 16'd4;

        error_count = 0;
        clear_faults();


        // ====================================================
        // M5-C-01 Healthy dual network
        // ====================================================

        reset_dut();
        tc_error = 0;

        setup_workload_8();

        @(negedge clk);
        tx_enable = 1'b1;

        wait_a_frames(8);
        wait_a_frames(8);

        @(negedge clk);
        tx_enable = 1'b0;
        repeat (5) @(posedge clk);
        #1;

        if ((a_frame_count !== 8) || (b_frame_count !== 8)) begin
            $display("ERROR: healthy dual frames %0d/%0d", a_frame_count, b_frame_count);
            error_count = error_count + 1; tc_error = tc_error + 1;
        end

        if (mon_redundancy_ok !== 1'b1) begin
            $display("ERROR: healthy dual monitor not ok");
            error_count = error_count + 1; tc_error = tc_error + 1;
        end

        if (tc_error == 0)
            $display("TC-M5-C-01 PASS: healthy dual network");


        // ====================================================
        // M5-C-02 A disabled -> B continues
        // ====================================================

        reset_dut();
        tc_error = 0;

        network_a_enable = 1'b0;
        network_b_enable = 1'b1;

        setup_workload_1();

        // Wait for network latch.
        repeat (3) @(posedge clk);
        #1;

        if (network_a_active_dbg !== 1'b0) begin
            $display("ERROR: A not latched disabled");
            error_count = error_count + 1; tc_error = tc_error + 1;
        end

        @(negedge clk);
        tx_enable = 1'b1;

        wait_a_frames(1);

        @(negedge clk);
        tx_enable = 1'b0;
        repeat (5) @(posedge clk);
        #1;

        if (logical_commit_count !== 1) begin
            $display("ERROR: A-disabled logical commit %0d", logical_commit_count);
            error_count = error_count + 1; tc_error = tc_error + 1;
        end

        if ((a_frame_count !== 0) || (b_frame_count !== 1)) begin
            $display("ERROR: A-disabled frames A/B %0d/%0d", a_frame_count, b_frame_count);
            error_count = error_count + 1; tc_error = tc_error + 1;
        end

        if (tc_error == 0)
            $display("TC-M5-C-02 PASS: A disabled / B continues");


        // ====================================================
        // M5-C-03 B disabled -> A continues
        // ====================================================

        reset_dut();
        tc_error = 0;

        network_a_enable = 1'b1;
        network_b_enable = 1'b0;

        setup_workload_1();

        repeat (3) @(posedge clk);
        #1;

        @(negedge clk);
        tx_enable = 1'b1;

        // Wait for A frame via b_frame_count == 0 approach: poll until core done.
        timeout_count = 0;
        while ((a_frame_count < 1) && (timeout_count < MAX_TIMEOUT)) begin
            @(posedge clk);
            timeout_count = timeout_count + 1;
        end

        @(negedge clk);
        tx_enable = 1'b0;
        repeat (5) @(posedge clk);
        #1;

        if ((a_frame_count !== 1) || (b_frame_count !== 0)) begin
            $display("ERROR: B-disabled frames A/B %0d/%0d", a_frame_count, b_frame_count);
            error_count = error_count + 1; tc_error = tc_error + 1;
        end

        if (tc_error == 0)
            $display("TC-M5-C-03 PASS: B disabled / A continues");


        // ====================================================
        // M5-C-04 A+B disabled -> logical TX blocked safely
        // ====================================================

        reset_dut();
        tc_error = 0;

        network_a_enable = 1'b0;
        network_b_enable = 1'b0;

        setup_workload_1();

        repeat (3) @(posedge clk);
        #1;

        if (any_network_enabled_dbg !== 1'b0) begin
            $display("ERROR: any_network_enabled should be 0");
            error_count = error_count + 1; tc_error = tc_error + 1;
        end

        @(negedge clk);
        tx_enable = 1'b1;

        repeat (20) @(posedge clk);
        #1;

        if ((logical_commit_count !== 0) ||
            (fifo_count0_dbg !== 3'd1)) begin
            $display("ERROR: both-disabled should not consume (commit=%0d fifo0=%0d)",
                     logical_commit_count, fifo_count0_dbg);
            error_count = error_count + 1; tc_error = tc_error + 1;
        end

        @(negedge clk);
        tx_enable = 1'b0;

        if (tc_error == 0)
            $display("TC-M5-C-04 PASS: both disabled safe block");


        // ====================================================
        // M5-C-05 Corrupt A byte
        // ====================================================

        reset_dut();
        tc_error = 0;

        setup_workload_1();

        // Inject corruption on A byte index 20.
        fault_enable_a = 1'b1;
        corrupt_byte_enable_a = 1'b1;
        corrupt_byte_index_a = 16'd20;
        corrupt_xor_mask_a = 8'h01;

        @(negedge clk);
        tx_enable = 1'b1;

        timeout_count = 0;
        while ((a_frame_count < 1) && (timeout_count < MAX_TIMEOUT)) begin
            @(posedge clk);
            timeout_count = timeout_count + 1;
        end

        @(negedge clk);
        tx_enable = 1'b0;
        repeat (5) @(posedge clk);
        #1;

        if (mon_byte_mismatch_count !== 32'd1) begin
            $display("ERROR: corrupt byte mismatch=%0d", mon_byte_mismatch_count);
            error_count = error_count + 1; tc_error = tc_error + 1;
        end

        if (mon_redundancy_ok !== 1'b0) begin
            $display("ERROR: corruption not latched");
            error_count = error_count + 1; tc_error = tc_error + 1;
        end

        if (tc_error == 0)
            $display("TC-M5-C-05 PASS: A byte corruption detected");


        // ====================================================
        // M5-C-06 Drop B physical byte
        // ====================================================

        reset_dut();
        tc_error = 0;

        setup_workload_1();

        fault_enable_b = 1'b1;
        drop_byte_enable_b = 1'b1;
        drop_byte_index_b = 16'd25;

        @(negedge clk);
        tx_enable = 1'b1;

        timeout_count = 0;
        while ((a_frame_count < 1) && (timeout_count < MAX_TIMEOUT)) begin
            @(posedge clk);
            timeout_count = timeout_count + 1;
        end

        @(negedge clk);
        tx_enable = 1'b0;
        repeat (5) @(posedge clk);
        #1;

        if (mon_frame_skew_cycle_count < 32'd1) begin
            $display("ERROR: drop byte frame skew=%0d", mon_frame_skew_cycle_count);
            error_count = error_count + 1; tc_error = tc_error + 1;
        end

        if ((mon_a_active_byte_count !== 32'd72) ||
            (mon_b_active_byte_count !== 32'd71)) begin
            $display("ERROR: drop byte count A/B %0d/%0d",
                     mon_a_active_byte_count, mon_b_active_byte_count);
            error_count = error_count + 1; tc_error = tc_error + 1;
        end

        if (mon_redundancy_ok !== 1'b0) begin
            $display("ERROR: drop byte not latched");
            error_count = error_count + 1; tc_error = tc_error + 1;
        end

        if (tc_error == 0)
            $display("TC-M5-C-06 PASS: B dropped byte detected");


        // ====================================================
        // M5-C-07 Drop B frame_done
        // ====================================================

        reset_dut();
        tc_error = 0;

        setup_workload_1();

        fault_enable_b = 1'b1;
        drop_frame_done_enable_b = 1'b1;

        @(negedge clk);
        tx_enable = 1'b1;

        timeout_count = 0;
        while ((a_frame_count < 1) && (timeout_count < MAX_TIMEOUT)) begin
            @(posedge clk);
            timeout_count = timeout_count + 1;
        end

        @(negedge clk);
        tx_enable = 1'b0;
        repeat (5) @(posedge clk);
        #1;

        if ((mon_a_frame_count !== 32'd1) || (mon_b_frame_count !== 32'd0)) begin
            $display("ERROR: drop done frame count A/B %0d/%0d",
                     mon_a_frame_count, mon_b_frame_count);
            error_count = error_count + 1; tc_error = tc_error + 1;
        end

        if (mon_frame_done_skew_count < 32'd1) begin
            $display("ERROR: drop done skew=%0d", mon_frame_done_skew_count);
            error_count = error_count + 1; tc_error = tc_error + 1;
        end

        if (mon_redundancy_ok !== 1'b0) begin
            $display("ERROR: drop done not latched");
            error_count = error_count + 1; tc_error = tc_error + 1;
        end

        if (tc_error == 0)
            $display("TC-M5-C-07 PASS: B frame_done loss detected");


        // ====================================================
        // M5-C-08 Force A tx_er
        // ====================================================

        reset_dut();
        tc_error = 0;

        setup_workload_1();

        fault_enable_a = 1'b1;
        tx_error_byte_enable_a = 1'b1;
        tx_error_byte_index_a = 16'd30;

        @(negedge clk);
        tx_enable = 1'b1;

        timeout_count = 0;
        while ((a_frame_count < 1) && (timeout_count < MAX_TIMEOUT)) begin
            @(posedge clk);
            timeout_count = timeout_count + 1;
        end

        @(negedge clk);
        tx_enable = 1'b0;
        repeat (5) @(posedge clk);
        #1;

        if (mon_tx_er_mismatch_count !== 32'd1) begin
            $display("ERROR: tx_er mismatch=%0d", mon_tx_er_mismatch_count);
            error_count = error_count + 1; tc_error = tc_error + 1;
        end

        if (mon_a_tx_error_cycle_count !== 32'd1) begin
            $display("ERROR: A tx_er cycle=%0d", mon_a_tx_error_cycle_count);
            error_count = error_count + 1; tc_error = tc_error + 1;
        end

        if (mon_redundancy_ok !== 1'b0) begin
            $display("ERROR: tx_er not latched");
            error_count = error_count + 1; tc_error = tc_error + 1;
        end

        if (tc_error == 0)
            $display("TC-M5-C-08 PASS: A tx_er detected");


        // ====================================================
        // M5-C-09 A permanent output failure -> B-only recovery
        // ====================================================

        reset_dut();
        tc_error = 0;

        setup_workload_8();

        // Start in healthy dual mode, but mute A externally.
        mute_link_a = 1'b1;

        @(negedge clk);
        tx_enable = 1'b1;

        // Let a few frames flow; A physical output is muted.
        timeout_count = 0;
        while ((core_done_count < 2) && (timeout_count < MAX_TIMEOUT)) begin
            @(posedge clk);
            timeout_count = timeout_count + 1;
        end

        // Monitor must have detected the mismatch.
        if (mon_redundancy_ok !== 1'b0) begin
            $display("ERROR: mute-A not detected by monitor");
            error_count = error_count + 1; tc_error = tc_error + 1;
        end

        // Quiesce TX.
        @(negedge clk);
        tx_enable = 1'b0;

        while (core_busy) @(posedge clk);

        // Switch to B-only.
        network_a_enable = 1'b0;
        network_b_enable = 1'b1;
        mute_link_a = 1'b0;

        repeat (3) @(posedge clk);
        #1;

        if (network_a_active_dbg !== 1'b0) begin
            $display("ERROR: A not disabled after switch");
            error_count = error_count + 1; tc_error = tc_error + 1;
        end

        if (degraded_mode_dbg !== 1'b1) begin
            $display("ERROR: not in degraded mode");
            error_count = error_count + 1; tc_error = tc_error + 1;
        end

        // Record counts before resuming.
        // Resume and send the remaining logical frames on B only.
        @(negedge clk);
        tx_enable = 1'b1;

        // Wait for all FIFOs to drain (4 VL x 2 frames = 8 total, some already sent).
        timeout_count = 0;
        while ((fifo_count0_dbg != 3'd0 || fifo_count1_dbg != 3'd0 ||
                fifo_count2_dbg != 3'd0 || fifo_count3_dbg != 3'd0) &&
               (timeout_count < MAX_TIMEOUT)) begin
            @(posedge clk);
            timeout_count = timeout_count + 1;
        end

        @(negedge clk);
        tx_enable = 1'b0;
        repeat (5) @(posedge clk);
        #1;

        // Sequence must increment exactly once per logical frame.
        if ((seq0_dbg !== 8'd2) || (seq1_dbg !== 8'd2) ||
            (seq2_dbg !== 8'd2) || (seq3_dbg !== 8'd2)) begin
            $display("ERROR: C-09 sequence %0d/%0d/%0d/%0d",
                     seq0_dbg, seq1_dbg, seq2_dbg, seq3_dbg);
            error_count = error_count + 1; tc_error = tc_error + 1;
        end

        if (tc_error == 0)
            $display("TC-M5-C-09 PASS: fault -> quiesce -> B-only recovery");


        // ====================================================
        // FINAL
        // ====================================================

        $display("");
        $display("========================================================");
        if (error_count == 0)
            $display("M5-C FAULT + DEGRADED ALL TESTS PASS");
        else
            $display("M5-C FAILED: %0d error(s)", error_count);
        $display("========================================================");

        #50;
        $finish;

    end


endmodule
