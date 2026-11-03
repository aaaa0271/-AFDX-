`timescale 1ns / 1ps
// LEGACY (M4 TX path): not instantiated by AFDX_competition_top or the
// competition AFDX_top; retained only for legacy ModelSim regression
// coverage. Do not use for new work.

module multi_vl_tx_control_selectable (
    input  wire        clk,
    input  wire        rst_n,

    // ========================================================
    // M4-A Configuration Write Interface
    // ========================================================

    input  wire        cfg_we,
    input  wire [1:0]  cfg_vl_id,

    input  wire [31:0] cfg_bag,
    input  wire [15:0] cfg_lmax,
    input  wire [1:0]  cfg_priority,
    input  wire [7:0]  cfg_destination,


    // ========================================================
    // Application -> Per-VL FIFO
    // ========================================================

    input  wire        app_wr_en,
    input  wire [1:0]  app_wr_vl_id,
    input  wire [7:0]  app_wr_data,
    input  wire [15:0] app_wr_len,

    output wire        app_wr_accept,


    // ========================================================
    // TX accept
    // ========================================================

    input  wire        tx_accept,


    // ========================================================
    // Scheduler policy selection
    // ========================================================

    input  wire        scheduler_enable,
    input  wire [1:0]  scheduler_mode,


    // ========================================================
    // Live TX request
    // ========================================================

    output wire        tx_request,

    output wire [1:0]  tx_vl_id,
    output wire [7:0]  tx_data,
    output wire [15:0] tx_len,
    output wire [7:0]  tx_seq,

    output wire [7:0]  tx_destination,
    output wire [15:0] tx_lmax,
    output wire [1:0]  tx_priority,


    // ========================================================
    // Atomic commit event
    // ========================================================

    output wire        schedule_fire,


    // ========================================================
    // Registered committed-frame observation
    // ========================================================

    output reg         commit_valid,
    output reg  [1:0]  commit_vl_id,
    output reg  [7:0]  commit_data,
    output reg  [15:0] commit_len,
    output reg  [7:0]  commit_seq,


    // ========================================================
    // Debug / verification
    // ========================================================

    output wire [3:0]  fifo_empty_dbg,
    output wire [3:0]  fifo_full_dbg,

    output wire [2:0]  fifo_count0_dbg,
    output wire [2:0]  fifo_count1_dbg,
    output wire [2:0]  fifo_count2_dbg,
    output wire [2:0]  fifo_count3_dbg,

    output wire [3:0]  bag_ready_dbg,
    output wire [3:0]  eligible_dbg,

    output wire [31:0] bag_counter0_dbg,
    output wire [31:0] bag_counter1_dbg,
    output wire [31:0] bag_counter2_dbg,
    output wire [31:0] bag_counter3_dbg,

    output wire [7:0]  seq0_dbg,
    output wire [7:0]  seq1_dbg,
    output wire [7:0]  seq2_dbg,
    output wire [7:0]  seq3_dbg,

    output wire [3:0]  enable_all_dbg,

    output wire [3:0]  selected_onehot_dbg,
    output wire [3:0]  tx_commit_dbg,

    // Scheduler policy debug
    output wire [1:0]  policy_selected_priority_dbg,
    output wire [7:0]  policy_selected_age_dbg,
    output wire [8:0]  policy_selected_score_dbg,

    output wire [7:0]  ba_wait_age0_dbg,
    output wire [7:0]  ba_wait_age1_dbg,
    output wire [7:0]  ba_wait_age2_dbg,
    output wire [7:0]  ba_wait_age3_dbg,

    output wire [1:0]  rr_last_grant_dbg
);


    // ========================================================
    // Configuration signals
    // ========================================================

    wire [31:0] bag0;
    wire [31:0] bag1;
    wire [31:0] bag2;
    wire [31:0] bag3;

    wire [1:0] priority0;
    wire [1:0] priority1;
    wire [1:0] priority2;
    wire [1:0] priority3;

    wire [3:0] enable_all;


    // Selected-VL query outputs
    wire [31:0] query_bag;
    wire [15:0] query_lmax;
    wire [1:0]  query_priority;
    wire [7:0]  query_destination;
    wire        query_enable;


    // ========================================================
    // FIFO signals
    // ========================================================

    wire [7:0]  fifo_rd_data;
    wire [15:0] fifo_rd_len;

    wire [3:0] fifo_empty;
    wire [3:0] fifo_full;

    wire [2:0] fifo_count0;
    wire [2:0] fifo_count1;
    wire [2:0] fifo_count2;
    wire [2:0] fifo_count3;

    wire       fifo_rd_en;
    wire [1:0] fifo_rd_vl_id;


    // ========================================================
    // BAG signals
    // ========================================================

    wire [3:0] bag_ready;
    wire [3:0] eligible;

    wire [31:0] bag_counter0;
    wire [31:0] bag_counter1;
    wire [31:0] bag_counter2;
    wire [31:0] bag_counter3;


    // ========================================================
    // Scheduler signals
    // ========================================================

    wire       schedule_valid;
    wire [1:0] selected_vl;
    wire [3:0] selected_onehot;

    wire       schedule_fire_int;


    // ========================================================
    // Scheduler policy observation
    // ========================================================

    wire [1:0] policy_selected_priority;
    wire [7:0] policy_selected_age;
    wire [8:0] policy_selected_score;

    wire [7:0] ba_wait_age0;
    wire [7:0] ba_wait_age1;
    wire [7:0] ba_wait_age2;
    wire [7:0] ba_wait_age3;

    wire [1:0] rr_last_grant;


    // ========================================================
    // Commit signals
    // ========================================================

    wire [3:0] tx_commit;
    wire [3:0] seq_commit;


    // ========================================================
    // Sequence signals
    // ========================================================

    wire [7:0] selected_seq;

    wire [7:0] seq0;
    wire [7:0] seq1;
    wire [7:0] seq2;
    wire [7:0] seq3;


    // ========================================================
    // M4-A: Configuration Table
    // ========================================================

    vl_config config_table (
        .clk              (clk),
        .rst_n            (rst_n),

        .cfg_we           (cfg_we),
        .cfg_vl_id        (cfg_vl_id),

        .cfg_bag          (cfg_bag),
        .cfg_lmax         (cfg_lmax),
        .cfg_priority     (cfg_priority),
        .cfg_destination  (cfg_destination),

        // Selected VL query
        .query_vl_id      (selected_vl),

        .vl_bag           (query_bag),
        .vl_lmax          (query_lmax),
        .vl_priority      (query_priority),
        .vl_destination   (query_destination),
        .vl_enable        (query_enable),

        // Parallel scheduler/BAG view
        .bag0             (bag0),
        .bag1             (bag1),
        .bag2             (bag2),
        .bag3             (bag3),

        .priority0        (priority0),
        .priority1        (priority1),
        .priority2        (priority2),
        .priority3        (priority3),

        .enable_all       (enable_all)
    );


    // ========================================================
    // M4-B: Per-VL FIFO
    // ========================================================

    per_vl_fifo fifo_bank (
        .clk         (clk),
        .rst_n       (rst_n),

        .wr_en       (app_wr_en),
        .wr_vl_id    (app_wr_vl_id),
        .wr_data     (app_wr_data),
        .wr_len      (app_wr_len),

        // FIFO is popped ONLY after schedule_fire.
        .rd_en       (fifo_rd_en),
        .rd_vl_id    (fifo_rd_vl_id),

        .rd_data     (fifo_rd_data),
        .rd_len      (fifo_rd_len),

        .fifo_empty  (fifo_empty),
        .fifo_full   (fifo_full),

        .fifo_count0 (fifo_count0),
        .fifo_count1 (fifo_count1),
        .fifo_count2 (fifo_count2),
        .fifo_count3 (fifo_count3)
    );


    // ========================================================
    // Application write acknowledgement
    // ========================================================

    assign app_wr_accept =
        app_wr_en &&
        !fifo_full[app_wr_vl_id];


    // ========================================================
    // M4-C: Per-VL BAG
    // ========================================================

    per_vl_bag_regulator bag_bank (
        .clk          (clk),
        .rst_n        (rst_n),

        .bag0         (bag0),
        .bag1         (bag1),
        .bag2         (bag2),
        .bag3         (bag3),

        .vl_enable    (enable_all),

        .fifo_empty   (fifo_empty),

        // Reload BAG only after a REAL accepted transaction.
        .tx_commit    (tx_commit),

        .bag_ready    (bag_ready),
        .eligible     (eligible),

        .bag_counter0 (bag_counter0),
        .bag_counter1 (bag_counter1),
        .bag_counter2 (bag_counter2),
        .bag_counter3 (bag_counter3)
    );


    // ========================================================
    // M4-D: Selectable Scheduler (RR / FP / BAG-aware)
    // ========================================================

    vl_scheduler_selectable u_scheduler (
        .clk                  (clk),
        .rst_n                (rst_n),

        .scheduler_enable     (scheduler_enable),
        .scheduler_mode       (scheduler_mode),

        .eligible             (eligible),

        .priority0            (priority0),
        .priority1            (priority1),
        .priority2            (priority2),
        .priority3            (priority3),

        .grant_accept         (tx_accept),

        .schedule_valid       (schedule_valid),
        .selected_vl          (selected_vl),
        .selected_onehot      (selected_onehot),

        .selected_priority    (policy_selected_priority),
        .selected_age         (policy_selected_age),
        .selected_score       (policy_selected_score),

        .schedule_fire        (schedule_fire_int),

        .ba_wait_age0_dbg     (ba_wait_age0),
        .ba_wait_age1_dbg     (ba_wait_age1),
        .ba_wait_age2_dbg     (ba_wait_age2),
        .ba_wait_age3_dbg     (ba_wait_age3),

        .rr_last_grant_dbg    (rr_last_grant)
    );


    // ========================================================
    // Per-VL Sequence Generator
    // ========================================================

    per_vl_seq_generator seq_bank (
        .clk          (clk),
        .rst_n        (rst_n),

        .tx_commit    (seq_commit),

        .query_vl_id  (selected_vl),
        .query_seq    (selected_seq),

        .seq0         (seq0),
        .seq1         (seq1),
        .seq2         (seq2),
        .seq3         (seq3)
    );


    // ========================================================
    // ATOMIC COMMIT POINT
    // ========================================================

    assign fifo_rd_en =
        schedule_fire_int;

    assign fifo_rd_vl_id =
        selected_vl;


    assign tx_commit =
        selected_onehot &
        {4{schedule_fire_int}};


    assign seq_commit =
        selected_onehot &
        {4{schedule_fire_int}};


    // ========================================================
    // Live TX request
    // ========================================================

    assign tx_request =
        schedule_valid;

    assign tx_vl_id =
        selected_vl;

    assign tx_data =
        fifo_rd_data;

    assign tx_len =
        fifo_rd_len;

    assign tx_seq =
        selected_seq;

    assign tx_destination =
        query_destination;

    assign tx_lmax =
        query_lmax;

    assign tx_priority =
        query_priority;


    assign schedule_fire =
        schedule_fire_int;


    // ========================================================
    // Capture the exact transaction consumed on schedule_fire.
    // ========================================================

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            commit_valid <= 1'b0;
            commit_vl_id <= 2'd0;
            commit_data  <= 8'd0;
            commit_len   <= 16'd0;
            commit_seq   <= 8'd0;

        end

        else begin

            commit_valid <= schedule_fire_int;

            if (schedule_fire_int) begin

                commit_vl_id <= selected_vl;
                commit_data  <= fifo_rd_data;
                commit_len   <= fifo_rd_len;
                commit_seq   <= selected_seq;

            end

        end

    end


    // ========================================================
    // Debug
    // ========================================================

    assign fifo_empty_dbg = fifo_empty;
    assign fifo_full_dbg  = fifo_full;

    assign fifo_count0_dbg = fifo_count0;
    assign fifo_count1_dbg = fifo_count1;
    assign fifo_count2_dbg = fifo_count2;
    assign fifo_count3_dbg = fifo_count3;

    assign bag_ready_dbg = bag_ready;
    assign eligible_dbg  = eligible;

    assign bag_counter0_dbg = bag_counter0;
    assign bag_counter1_dbg = bag_counter1;
    assign bag_counter2_dbg = bag_counter2;
    assign bag_counter3_dbg = bag_counter3;

    assign seq0_dbg = seq0;
    assign seq1_dbg = seq1;
    assign seq2_dbg = seq2;
    assign seq3_dbg = seq3;

    assign enable_all_dbg = enable_all;

    assign selected_onehot_dbg = selected_onehot;
    assign tx_commit_dbg        = tx_commit;


    assign policy_selected_priority_dbg =
        policy_selected_priority;

    assign policy_selected_age_dbg =
        policy_selected_age;

    assign policy_selected_score_dbg =
        policy_selected_score;


    assign ba_wait_age0_dbg =
        ba_wait_age0;

    assign ba_wait_age1_dbg =
        ba_wait_age1;

    assign ba_wait_age2_dbg =
        ba_wait_age2;

    assign ba_wait_age3_dbg =
        ba_wait_age3;


    assign rr_last_grant_dbg =
        rr_last_grant;


endmodule
