`timescale 1ns / 1ps
// LEGACY (M4 TX path): not instantiated by AFDX_competition_top or the
// competition AFDX_top; retained only for legacy ModelSim regression
// coverage. Do not use for new work.

module vl_scheduler_selectable (
    input  wire       clk,
    input  wire       rst_n,

    // 0 = scheduler state is inactive.
    input  wire       scheduler_enable,

    // 00 = RR
    // 01 = Fixed Priority
    // 10 = BAG-aware Aging
    // 11 = Safe Idle
    input  wire [1:0] scheduler_mode,

    input  wire [3:0] eligible,

    input  wire [1:0] priority0,
    input  wire [1:0] priority1,
    input  wire [1:0] priority2,
    input  wire [1:0] priority3,

    input  wire       grant_accept,

    output reg        schedule_valid,
    output reg  [1:0] selected_vl,
    output reg  [3:0] selected_onehot,

    output reg  [1:0] selected_priority,
    output reg  [7:0] selected_age,
    output reg  [8:0] selected_score,

    output reg        schedule_fire,

    // BAG-aware debug
    output wire [7:0] ba_wait_age0_dbg,
    output wire [7:0] ba_wait_age1_dbg,
    output wire [7:0] ba_wait_age2_dbg,
    output wire [7:0] ba_wait_age3_dbg,

    // RR debug
    output wire [1:0] rr_last_grant_dbg
);


    localparam MODE_RR = 2'b00;
    localparam MODE_FP = 2'b01;
    localparam MODE_BA = 2'b10;


    // ========================================================
    // Active eligibility
    //
    // Only the selected scheduler receives real eligibility.
    // Inactive schedulers see 0000.
    //
    // This prevents inactive hold / aging state from evolving.
    // ========================================================

    wire [3:0] active_eligible;

    wire [3:0] rr_eligible;
    wire [3:0] fp_eligible;
    wire [3:0] ba_eligible;


    assign active_eligible =
        scheduler_enable
        ? eligible
        : 4'b0000;


    assign rr_eligible =
        (scheduler_mode == MODE_RR)
        ? active_eligible
        : 4'b0000;

    assign fp_eligible =
        (scheduler_mode == MODE_FP)
        ? active_eligible
        : 4'b0000;

    assign ba_eligible =
        (scheduler_mode == MODE_BA)
        ? active_eligible
        : 4'b0000;


    // ========================================================
    // Grant routing
    //
    // Only the active scheduler is allowed to observe the
    // downstream acceptance event.
    // ========================================================

    wire rr_grant_accept;
    wire fp_grant_accept;
    wire ba_grant_accept;


    assign rr_grant_accept =
        (scheduler_mode == MODE_RR)
        ? grant_accept
        : 1'b0;

    assign fp_grant_accept =
        (scheduler_mode == MODE_FP)
        ? grant_accept
        : 1'b0;

    assign ba_grant_accept =
        (scheduler_mode == MODE_BA)
        ? grant_accept
        : 1'b0;


    // ========================================================
    // Round Robin
    // ========================================================

    wire       rr_valid;
    wire [1:0] rr_vl;
    wire [3:0] rr_onehot;
    wire       rr_fire;


    vl_scheduler_rr u_rr (
        .clk             (clk),
        .rst_n           (rst_n),

        .eligible        (rr_eligible),
        .grant_accept    (rr_grant_accept),

        .schedule_valid  (rr_valid),
        .selected_vl     (rr_vl),
        .selected_onehot (rr_onehot),

        .schedule_fire   (rr_fire),

        .last_grant_dbg  (rr_last_grant_dbg)
    );


    // ========================================================
    // Fixed Priority
    // ========================================================

    wire       fp_valid;
    wire [1:0] fp_vl;
    wire [3:0] fp_onehot;
    wire       fp_fire;

    wire [1:0] fp_selected_priority;


    vl_scheduler_fp u_fp (
        .clk               (clk),
        .rst_n             (rst_n),

        .eligible          (fp_eligible),

        .priority0         (priority0),
        .priority1         (priority1),
        .priority2         (priority2),
        .priority3         (priority3),

        .grant_accept      (fp_grant_accept),

        .schedule_valid    (fp_valid),
        .selected_vl       (fp_vl),
        .selected_onehot   (fp_onehot),

        .schedule_fire     (fp_fire),

        .selected_priority (fp_selected_priority)
    );


    // ========================================================
    // BAG-Aware Aging
    // ========================================================

    wire       ba_valid;
    wire [1:0] ba_vl;
    wire [3:0] ba_onehot;
    wire       ba_fire;

    wire [1:0] ba_selected_priority;
    wire [7:0] ba_selected_age;
    wire [8:0] ba_selected_score;


    vl_scheduler_bag_aware u_ba (
        .clk               (clk),
        .rst_n             (rst_n),

        .eligible          (ba_eligible),

        .priority0         (priority0),
        .priority1         (priority1),
        .priority2         (priority2),
        .priority3         (priority3),

        .grant_accept      (ba_grant_accept),

        .schedule_valid    (ba_valid),
        .selected_vl       (ba_vl),
        .selected_onehot   (ba_onehot),

        .schedule_fire     (ba_fire),

        .selected_priority (ba_selected_priority),
        .selected_age      (ba_selected_age),
        .selected_score    (ba_selected_score),

        .wait_age0_dbg     (ba_wait_age0_dbg),
        .wait_age1_dbg     (ba_wait_age1_dbg),
        .wait_age2_dbg     (ba_wait_age2_dbg),
        .wait_age3_dbg     (ba_wait_age3_dbg)
    );


    // ========================================================
    // RR selected priority lookup
    // ========================================================

    reg [1:0] rr_selected_priority;

    always @* begin

        case (rr_vl)

            2'd0:
                rr_selected_priority = priority0;

            2'd1:
                rr_selected_priority = priority1;

            2'd2:
                rr_selected_priority = priority2;

            2'd3:
                rr_selected_priority = priority3;

            default:
                rr_selected_priority = 2'd0;

        endcase

    end


    // ========================================================
    // Policy output mux
    // ========================================================

    always @* begin

        schedule_valid    = 1'b0;
        selected_vl       = 2'd0;
        selected_onehot   = 4'b0000;

        selected_priority = 2'd0;
        selected_age      = 8'd0;
        selected_score    = 9'd0;

        schedule_fire     = 1'b0;


        case (scheduler_mode)

            MODE_RR: begin

                schedule_valid    = rr_valid;
                selected_vl       = rr_vl;
                selected_onehot   = rr_onehot;

                selected_priority = rr_selected_priority;

                schedule_fire     = rr_fire;

            end


            MODE_FP: begin

                schedule_valid    = fp_valid;
                selected_vl       = fp_vl;
                selected_onehot   = fp_onehot;

                selected_priority = fp_selected_priority;

                schedule_fire     = fp_fire;

            end


            MODE_BA: begin

                schedule_valid    = ba_valid;
                selected_vl       = ba_vl;
                selected_onehot   = ba_onehot;

                selected_priority = ba_selected_priority;
                selected_age      = ba_selected_age;
                selected_score    = ba_selected_score;

                schedule_fire     = ba_fire;

            end


            // 11 = safe idle
            default: begin

                schedule_valid    = 1'b0;
                selected_vl       = 2'd0;
                selected_onehot   = 4'b0000;

                selected_priority = 2'd0;
                selected_age      = 8'd0;
                selected_score    = 9'd0;

                schedule_fire     = 1'b0;

            end

        endcase

    end


endmodule
