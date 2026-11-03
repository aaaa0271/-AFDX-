`timescale 1ns / 1ps
// LEGACY (M4 TX path): not instantiated by AFDX_competition_top or the
// competition AFDX_top; retained only for legacy ModelSim regression
// coverage. Do not use for new work.

module multi_vl_gmii_tx_selectable (
    input  wire        clk,
    input  wire        rst_n,

    // ========================================================
    // Global TX enable
    // ========================================================

    input  wire        tx_enable,

    // ========================================================
    // Scheduler policy selection
    //
    // 00 = Round Robin
    // 01 = Fixed Priority
    // 10 = BAG-aware Aging
    // 11 = Safe Idle
    //
    // Policy may only change while TX scheduling is disabled.
    // ========================================================

    input  wire [1:0]  scheduler_mode,


    // ========================================================
    // M4-A configuration
    // ========================================================

    input  wire        cfg_we,
    input  wire [1:0]  cfg_vl_id,

    input  wire [31:0] cfg_bag,
    input  wire [15:0] cfg_lmax,
    input  wire [1:0]  cfg_priority,
    input  wire [7:0]  cfg_destination,


    // ========================================================
    // Application write
    // ========================================================

    input  wire        app_wr_en,
    input  wire [1:0]  app_wr_vl_id,
    input  wire [7:0]  app_wr_data,
    input  wire [15:0] app_wr_len,

    output wire        app_wr_accept,
    output wire        app_len_error,


    // ========================================================
    // GMII
    // ========================================================

    output wire [7:0]  gmii_txd,
    output wire        gmii_tx_en,
    output wire        gmii_tx_er,

    output wire        gmii_frame_done,
    output wire        gmii_underrun,


    // ========================================================
    // TX status
    // ========================================================

    output wire        core_busy,
    output wire        core_frame_done,


    // ========================================================
    // M4-E3 debug
    // ========================================================

    output wire [1:0]  scheduler_mode_active_dbg,

    output wire        schedule_fire_dbg,
    output wire        frame_start_dbg,

    output wire        commit_valid_dbg,
    output wire [1:0]  commit_vl_id_dbg,
    output wire [7:0]  commit_data_dbg,
    output wire [7:0]  commit_seq_dbg,

    output wire [1:0]  selected_vl_dbg,
    output wire [7:0]  selected_seq_dbg,
    output wire [7:0]  selected_destination_dbg,

    output wire [1:0]  policy_selected_priority_dbg,
    output wire [7:0]  policy_selected_age_dbg,
    output wire [8:0]  policy_selected_score_dbg,

    output wire [7:0]  ba_wait_age0_dbg,
    output wire [7:0]  ba_wait_age1_dbg,
    output wire [7:0]  ba_wait_age2_dbg,
    output wire [7:0]  ba_wait_age3_dbg,

    // M4-F independent metrics observation ports
    output wire [3:0]  bag_ready_metrics_dbg,
    output wire [3:0]  eligible_metrics_dbg,

    output wire [7:0]  core_stream_data_dbg,
    output wire        core_stream_valid_dbg,
    output wire        core_stream_ready_dbg,

    output wire [2:0]  fifo_count0_dbg,
    output wire [2:0]  fifo_count1_dbg,
    output wire [2:0]  fifo_count2_dbg,
    output wire [2:0]  fifo_count3_dbg,

    output wire [7:0]  seq0_dbg,
    output wire [7:0]  seq1_dbg,
    output wire [7:0]  seq2_dbg,
    output wire [7:0]  seq3_dbg
);


    // ========================================================
    // Safe scheduler mode latch
    //
    // Policy may only change while TX scheduling is disabled
    // and the frame builder is idle.
    // ========================================================

    reg [1:0] active_scheduler_mode;

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            active_scheduler_mode <= 2'b00;

        end
        else begin

            if (!tx_enable && !core_busy)
                active_scheduler_mode <= scheduler_mode;

        end

    end

    assign scheduler_mode_active_dbg =
        active_scheduler_mode;


    // ========================================================
    // M4 control outputs
    // ========================================================

    wire       control_tx_request;

    wire [1:0]  control_tx_vl_id;
    wire [7:0]  control_tx_data;
    wire [15:0] control_tx_len;
    wire [7:0]  control_tx_seq;

    wire [7:0]  control_tx_destination;
    wire [15:0] control_tx_lmax;
    wire [1:0]  control_tx_priority;

    wire control_schedule_fire;


    // ========================================================
    // M4 control commit observation
    // ========================================================

    wire        control_commit_valid;
    wire [1:0]  control_commit_vl_id;
    wire [7:0]  control_commit_data;
    wire [15:0] control_commit_len;
    wire [7:0]  control_commit_seq;


    // ========================================================
    // M4 debug
    // ========================================================

    wire [3:0] fifo_empty_unused;
    wire [3:0] fifo_full_unused;

    wire [2:0] fifo_count0;
    wire [2:0] fifo_count1;
    wire [2:0] fifo_count2;
    wire [2:0] fifo_count3;

    wire [31:0] bag_counter0_unused;
    wire [31:0] bag_counter1_unused;
    wire [31:0] bag_counter2_unused;
    wire [31:0] bag_counter3_unused;

    wire [7:0] seq0;
    wire [7:0] seq1;
    wire [7:0] seq2;
    wire [7:0] seq3;

    wire [3:0] enable_unused;
    wire [3:0] selected_onehot_unused;
    wire [3:0] tx_commit_unused;

    wire [1:0] rr_last_grant_unused;


    // ========================================================
    // Application length protection
    // ========================================================

    wire app_length_ok;

    wire control_app_wr_en;
    wire control_app_wr_accept;


    assign app_length_ok =
        (app_wr_len == 16'd4);


    assign control_app_wr_en =
        app_wr_en &&
        app_length_ok;


    assign app_len_error =
        app_wr_en &&
        !app_length_ok;


    assign app_wr_accept =
        control_app_wr_accept;


    // ========================================================
    // TX acceptance
    // ========================================================

    wire tx_builder_ready;

    wire selected_length_ok;

    wire control_tx_accept;


    assign selected_length_ok =
        (control_tx_len == 16'd4);


    assign control_tx_accept =
        tx_enable &&
        tx_builder_ready &&
        selected_length_ok;


    // ========================================================
    // Selectable M4 control core
    // ========================================================

    multi_vl_tx_control_selectable u_control (
        .clk                 (clk),
        .rst_n               (rst_n),

        .cfg_we              (cfg_we),
        .cfg_vl_id           (cfg_vl_id),
        .cfg_bag             (cfg_bag),
        .cfg_lmax            (cfg_lmax),
        .cfg_priority        (cfg_priority),
        .cfg_destination     (cfg_destination),

        .app_wr_en           (control_app_wr_en),
        .app_wr_vl_id        (app_wr_vl_id),
        .app_wr_data         (app_wr_data),
        .app_wr_len          (app_wr_len),

        .app_wr_accept       (control_app_wr_accept),

        .tx_accept           (control_tx_accept),

        .scheduler_enable    (tx_enable),
        .scheduler_mode      (active_scheduler_mode),

        .tx_request          (control_tx_request),

        .tx_vl_id            (control_tx_vl_id),
        .tx_data             (control_tx_data),
        .tx_len              (control_tx_len),
        .tx_seq              (control_tx_seq),

        .tx_destination      (control_tx_destination),
        .tx_lmax             (control_tx_lmax),
        .tx_priority         (control_tx_priority),

        .schedule_fire       (control_schedule_fire),

        .commit_valid        (control_commit_valid),
        .commit_vl_id        (control_commit_vl_id),
        .commit_data         (control_commit_data),
        .commit_len          (control_commit_len),
        .commit_seq          (control_commit_seq),

        .fifo_empty_dbg      (fifo_empty_unused),
        .fifo_full_dbg       (fifo_full_unused),

        .fifo_count0_dbg     (fifo_count0),
        .fifo_count1_dbg     (fifo_count1),
        .fifo_count2_dbg     (fifo_count2),
        .fifo_count3_dbg     (fifo_count3),

        .bag_ready_dbg       (bag_ready_metrics_dbg),
        .eligible_dbg        (eligible_metrics_dbg),

        .bag_counter0_dbg    (bag_counter0_unused),
        .bag_counter1_dbg    (bag_counter1_unused),
        .bag_counter2_dbg    (bag_counter2_unused),
        .bag_counter3_dbg    (bag_counter3_unused),

        .seq0_dbg            (seq0),
        .seq1_dbg            (seq1),
        .seq2_dbg            (seq2),
        .seq3_dbg            (seq3),

        .enable_all_dbg      (enable_unused),

        .selected_onehot_dbg (selected_onehot_unused),
        .tx_commit_dbg       (tx_commit_unused),

        .policy_selected_priority_dbg (policy_selected_priority_dbg),
        .policy_selected_age_dbg      (policy_selected_age_dbg),
        .policy_selected_score_dbg    (policy_selected_score_dbg),

        .ba_wait_age0_dbg     (ba_wait_age0_dbg),
        .ba_wait_age1_dbg     (ba_wait_age1_dbg),
        .ba_wait_age2_dbg     (ba_wait_age2_dbg),
        .ba_wait_age3_dbg     (ba_wait_age3_dbg),

        .rr_last_grant_dbg    (rr_last_grant_unused)
    );


    // ========================================================
    // 8-bit descriptor -> existing 32-bit payload
    // ========================================================

    wire [31:0] payload32;

    wire payload_length_ok_unused;


    m4_payload_adapter u_payload_adapter (
        .descriptor_data (control_tx_data),
        .descriptor_len  (control_tx_len),

        .payload_data    (payload32),
        .length_ok       (payload_length_ok_unused)
    );


    // ========================================================
    // Selected destination -> frame network fields
    // ========================================================

    wire [47:0] tx_cfg_dst_mac;
    wire [47:0] tx_cfg_src_mac;

    wire [31:0] tx_cfg_src_ip;
    wire [31:0] tx_cfg_dst_ip;

    wire [15:0] tx_cfg_src_port;
    wire [15:0] tx_cfg_dst_port;


    m4_vl_net_mapper u_net_mapper (
        .destination_code (control_tx_destination),

        .cfg_dst_mac      (tx_cfg_dst_mac),
        .cfg_src_mac      (tx_cfg_src_mac),

        .cfg_src_ip       (tx_cfg_src_ip),
        .cfg_dst_ip       (tx_cfg_dst_ip),

        .cfg_src_port     (tx_cfg_src_port),
        .cfg_dst_port     (tx_cfg_dst_port)
    );


    // ========================================================
    // M4 TX Engine
    // ========================================================

    wire [7:0] core_tx_data;
    wire       core_tx_valid;
    wire       core_tx_ready;

    wire       tx_engine_frame_start;


    afdx_tx_engine_m4 u_tx_engine (
        .clk             (clk),
        .rst_n           (rst_n),

        .frame_request   (
            control_tx_request &&
            tx_enable &&
            selected_length_ok
        ),

        .frame_ready     (tx_builder_ready),

        .seq_num         (control_tx_seq),

        .cfg_dst_mac     (tx_cfg_dst_mac),
        .cfg_src_mac     (tx_cfg_src_mac),

        .cfg_src_ip      (tx_cfg_src_ip),
        .cfg_dst_ip      (tx_cfg_dst_ip),

        .cfg_src_port    (tx_cfg_src_port),
        .cfg_dst_port    (tx_cfg_dst_port),

        .payload_data    (payload32),

        .tx_data         (core_tx_data),
        .tx_valid        (core_tx_valid),
        .tx_ready        (core_tx_ready),

        .busy            (core_busy),
        .frame_done      (core_frame_done),

        .frame_start_dbg (tx_engine_frame_start)
    );


    // ========================================================
    // Existing verified GMII adapter
    // ========================================================

    gmii_tx_adapter_60 u_gmii (
        .clk        (clk),
        .rst        (~rst_n),

        .s_data     (core_tx_data),
        .s_valid    (core_tx_valid),
        .s_ready    (core_tx_ready),

        .gmii_txd   (gmii_txd),
        .gmii_tx_en (gmii_tx_en),
        .gmii_tx_er (gmii_tx_er),

        .frame_done (gmii_frame_done),
        .underrun   (gmii_underrun)
    );


    // ========================================================
    // Debug
    // ========================================================

    assign schedule_fire_dbg =
        control_schedule_fire;

    assign frame_start_dbg =
        tx_engine_frame_start;


    assign commit_valid_dbg =
        control_commit_valid;

    assign commit_vl_id_dbg =
        control_commit_vl_id;

    assign commit_data_dbg =
        control_commit_data;

    assign commit_seq_dbg =
        control_commit_seq;


    assign selected_vl_dbg =
        control_tx_vl_id;

    assign selected_seq_dbg =
        control_tx_seq;

    assign selected_destination_dbg =
        control_tx_destination;


    assign core_stream_data_dbg =
        core_tx_data;

    assign core_stream_valid_dbg =
        core_tx_valid;

    assign core_stream_ready_dbg =
        core_tx_ready;


    assign fifo_count0_dbg = fifo_count0;
    assign fifo_count1_dbg = fifo_count1;
    assign fifo_count2_dbg = fifo_count2;
    assign fifo_count3_dbg = fifo_count3;


    assign seq0_dbg = seq0;
    assign seq1_dbg = seq1;
    assign seq2_dbg = seq2;
    assign seq3_dbg = seq3;


endmodule
