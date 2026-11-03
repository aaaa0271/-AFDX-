`timescale 1ns / 1ps
// LEGACY (M4 TX path): not instantiated by AFDX_competition_top or the
// competition AFDX_top; retained only for legacy ModelSim regression
// coverage. Do not use for new work.

module vl_scheduler_fp (
    input  wire       clk,
    input  wire       rst_n,

    // --------------------------------------------------------
    // M4-C eligibility
    //
    // eligible already contains:
    //   FIFO pending
    //   BAG ready
    //   VL enabled
    // --------------------------------------------------------
    input  wire [3:0] eligible,

    // --------------------------------------------------------
    // Per-VL priority
    //
    // 3 = highest
    // 0 = lowest
    //
    // Equal priority:
    // lower VL ID wins.
    // --------------------------------------------------------
    input  wire [1:0] priority0,
    input  wire [1:0] priority1,
    input  wire [1:0] priority2,
    input  wire [1:0] priority3,

    // --------------------------------------------------------
    // Downstream acceptance
    // --------------------------------------------------------
    input  wire       grant_accept,

    // --------------------------------------------------------
    // Scheduler outputs
    // --------------------------------------------------------
    output reg        schedule_valid,
    output reg  [1:0] selected_vl,
    output reg  [3:0] selected_onehot,

    output wire       schedule_fire,

    // Debug / future metrics
    output reg  [1:0] selected_priority
);


    // ========================================================
    // Candidate result
    // ========================================================

    reg       candidate_valid;
    reg [1:0] candidate_vl;
    reg [3:0] candidate_onehot;
    reg [1:0] candidate_priority;


    // ========================================================
    // Hold state
    //
    // Once a request is exposed but not accepted,
    // keep that request stable until:
    //
    //   1. grant_accept happens, or
    //   2. the held VL becomes ineligible.
    // ========================================================

    reg       hold_valid;
    reg [1:0] hold_vl;
    reg [1:0] hold_priority;


    // ========================================================
    // Fixed Priority Candidate Selection
    //
    // Scan:
    //
    //   VL0 -> VL1 -> VL2 -> VL3
    //
    // A later VL only replaces the winner when its
    // priority is STRICTLY GREATER.
    //
    // Therefore equal priority naturally keeps the
    // lower VL ID.
    // ========================================================

    always @* begin

        candidate_valid    = 1'b0;
        candidate_vl       = 2'd0;
        candidate_onehot   = 4'b0000;
        candidate_priority = 2'd0;


        // ----------------------------------------------------
        // VL0
        // ----------------------------------------------------

        if (eligible[0]) begin

            candidate_valid    = 1'b1;
            candidate_vl       = 2'd0;
            candidate_onehot   = 4'b0001;
            candidate_priority = priority0;

        end


        // ----------------------------------------------------
        // VL1
        // ----------------------------------------------------

        if (eligible[1]) begin

            if (!candidate_valid ||
                (priority1 > candidate_priority)) begin

                candidate_valid    = 1'b1;
                candidate_vl       = 2'd1;
                candidate_onehot   = 4'b0010;
                candidate_priority = priority1;

            end

        end


        // ----------------------------------------------------
        // VL2
        // ----------------------------------------------------

        if (eligible[2]) begin

            if (!candidate_valid ||
                (priority2 > candidate_priority)) begin

                candidate_valid    = 1'b1;
                candidate_vl       = 2'd2;
                candidate_onehot   = 4'b0100;
                candidate_priority = priority2;

            end

        end


        // ----------------------------------------------------
        // VL3
        // ----------------------------------------------------

        if (eligible[3]) begin

            if (!candidate_valid ||
                (priority3 > candidate_priority)) begin

                candidate_valid    = 1'b1;
                candidate_vl       = 2'd3;
                candidate_onehot   = 4'b1000;
                candidate_priority = priority3;

            end

        end

    end


    // ========================================================
    // Scheduler Output
    // ========================================================

    always @* begin

        schedule_valid    = 1'b0;
        selected_vl       = 2'd0;
        selected_onehot   = 4'b0000;
        selected_priority = 2'd0;


        // ----------------------------------------------------
        // Existing held request
        // ----------------------------------------------------

        if (hold_valid) begin

            // Held request remains externally visible only
            // while the VL is still eligible.
            if (eligible[hold_vl]) begin

                schedule_valid    = 1'b1;
                selected_vl       = hold_vl;
                selected_priority = hold_priority;

                case (hold_vl)

                    2'd0:
                        selected_onehot = 4'b0001;

                    2'd1:
                        selected_onehot = 4'b0010;

                    2'd2:
                        selected_onehot = 4'b0100;

                    2'd3:
                        selected_onehot = 4'b1000;

                    default:
                        selected_onehot = 4'b0000;

                endcase

            end

        end


        // ----------------------------------------------------
        // New arbitration result
        // ----------------------------------------------------

        else if (candidate_valid) begin

            schedule_valid    = 1'b1;
            selected_vl       = candidate_vl;
            selected_onehot   = candidate_onehot;
            selected_priority = candidate_priority;

        end

    end


    // ========================================================
    // Real transaction
    // ========================================================

    assign schedule_fire =
        schedule_valid &&
        grant_accept;


    // ========================================================
    // Hold Control
    // ========================================================

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            hold_valid    <= 1'b0;
            hold_vl       <= 2'd0;
            hold_priority <= 2'd0;

        end
        else begin

            // ------------------------------------------------
            // Currently holding one request
            // ------------------------------------------------

            if (hold_valid) begin

                // VL became illegal before acceptance.
                if (!eligible[hold_vl]) begin

                    hold_valid <= 1'b0;

                end

                // Real downstream acceptance.
                else if (schedule_fire) begin

                    hold_valid <= 1'b0;

                end

            end


            // ------------------------------------------------
            // No held request
            // ------------------------------------------------

            else begin

                if (candidate_valid) begin

                    // Immediate acceptance:
                    // no hold required.
                    if (schedule_fire) begin

                        hold_valid <= 1'b0;

                    end

                    // Request presented but downstream
                    // did not accept it yet.
                    else begin

                        hold_valid    <= 1'b1;
                        hold_vl       <= candidate_vl;
                        hold_priority <= candidate_priority;

                    end

                end

            end

        end

    end


endmodule
