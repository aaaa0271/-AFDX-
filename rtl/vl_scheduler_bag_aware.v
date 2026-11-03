`timescale 1ns / 1ps
// LEGACY (M4 TX path): not instantiated by AFDX_competition_top or the
// competition AFDX_top; retained only for legacy ModelSim regression
// coverage. Do not use for new work.

module vl_scheduler_bag_aware #(
    parameter PRIORITY_SHIFT = 6
)(
    input  wire       clk,
    input  wire       rst_n,

    // --------------------------------------------------------
    // Eligibility from M4-C
    //
    // eligible already means:
    //   FIFO pending
    //   VL enabled
    //   BAG ready
    // --------------------------------------------------------
    input  wire [3:0] eligible,

    // --------------------------------------------------------
    // Per-VL priority
    //
    // 3 = highest
    // 0 = lowest
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

    // --------------------------------------------------------
    // Debug / M4-F metrics
    // --------------------------------------------------------
    output reg  [1:0] selected_priority,
    output reg  [7:0] selected_age,
    output reg  [8:0] selected_score,

    output wire [7:0] wait_age0_dbg,
    output wire [7:0] wait_age1_dbg,
    output wire [7:0] wait_age2_dbg,
    output wire [7:0] wait_age3_dbg
);


    // ========================================================
    // Eligible waiting age
    //
    // Age counts only while a VL is BAG-legal and waiting.
    // Saturation prevents wrap-around.
    // ========================================================

    reg [7:0] wait_age0;
    reg [7:0] wait_age1;
    reg [7:0] wait_age2;
    reg [7:0] wait_age3;


    // ========================================================
    // Current urgency scores
    //
    // score =
    //   priority * 64
    //   +
    //   eligible waiting age
    //
    // 9 bits are sufficient:
    //
    // max =
    //   3*64 + 255
    //   = 447
    // ========================================================

    reg [8:0] score0;
    reg [8:0] score1;
    reg [8:0] score2;
    reg [8:0] score3;


    // ========================================================
    // Candidate
    // ========================================================

    reg       candidate_valid;
    reg [1:0] candidate_vl;
    reg [3:0] candidate_onehot;

    reg [1:0] candidate_priority;
    reg [7:0] candidate_age;
    reg [8:0] candidate_score;


    // ========================================================
    // Hold state
    //
    // Same transactional semantics as D1 / D2.
    // ========================================================

    reg       hold_valid;
    reg [1:0] hold_vl;

    reg [1:0] hold_priority;
    reg [7:0] hold_age;
    reg [8:0] hold_score;


    // ========================================================
    // Score generation + arbitration
    //
    // Scan VL0 -> VL1 -> VL2 -> VL3.
    //
    // Replace winner only when score is STRICTLY higher.
    //
    // Equal score therefore keeps lower VL ID.
    // ========================================================

    always @* begin

        // ----------------------------------------------------
        // Score calculation
        // ----------------------------------------------------

        score0 =
            ({7'd0, priority0} << PRIORITY_SHIFT)
            +
            {1'b0, wait_age0};

        score1 =
            ({7'd0, priority1} << PRIORITY_SHIFT)
            +
            {1'b0, wait_age1};

        score2 =
            ({7'd0, priority2} << PRIORITY_SHIFT)
            +
            {1'b0, wait_age2};

        score3 =
            ({7'd0, priority3} << PRIORITY_SHIFT)
            +
            {1'b0, wait_age3};


        // ----------------------------------------------------
        // Default candidate
        // ----------------------------------------------------

        candidate_valid    = 1'b0;
        candidate_vl       = 2'd0;
        candidate_onehot   = 4'b0000;

        candidate_priority = 2'd0;
        candidate_age      = 8'd0;
        candidate_score    = 9'd0;


        // ----------------------------------------------------
        // VL0
        // ----------------------------------------------------

        if (eligible[0]) begin

            candidate_valid    = 1'b1;
            candidate_vl       = 2'd0;
            candidate_onehot   = 4'b0001;

            candidate_priority = priority0;
            candidate_age      = wait_age0;
            candidate_score    = score0;

        end


        // ----------------------------------------------------
        // VL1
        // ----------------------------------------------------

        if (eligible[1]) begin

            if (!candidate_valid ||
                (score1 > candidate_score)) begin

                candidate_valid    = 1'b1;
                candidate_vl       = 2'd1;
                candidate_onehot   = 4'b0010;

                candidate_priority = priority1;
                candidate_age      = wait_age1;
                candidate_score    = score1;

            end

        end


        // ----------------------------------------------------
        // VL2
        // ----------------------------------------------------

        if (eligible[2]) begin

            if (!candidate_valid ||
                (score2 > candidate_score)) begin

                candidate_valid    = 1'b1;
                candidate_vl       = 2'd2;
                candidate_onehot   = 4'b0100;

                candidate_priority = priority2;
                candidate_age      = wait_age2;
                candidate_score    = score2;

            end

        end


        // ----------------------------------------------------
        // VL3
        // ----------------------------------------------------

        if (eligible[3]) begin

            if (!candidate_valid ||
                (score3 > candidate_score)) begin

                candidate_valid    = 1'b1;
                candidate_vl       = 2'd3;
                candidate_onehot   = 4'b1000;

                candidate_priority = priority3;
                candidate_age      = wait_age3;
                candidate_score    = score3;

            end

        end

    end


    // ========================================================
    // Scheduler output
    // ========================================================

    always @* begin

        schedule_valid    = 1'b0;
        selected_vl       = 2'd0;
        selected_onehot   = 4'b0000;

        selected_priority = 2'd0;
        selected_age      = 8'd0;
        selected_score    = 9'd0;


        // ----------------------------------------------------
        // Held transaction
        // ----------------------------------------------------

        if (hold_valid) begin

            if (eligible[hold_vl]) begin

                schedule_valid    = 1'b1;
                selected_vl       = hold_vl;

                selected_priority = hold_priority;
                selected_age      = hold_age;
                selected_score    = hold_score;


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
        // New arbitration
        // ----------------------------------------------------

        else if (candidate_valid) begin

            schedule_valid    = 1'b1;
            selected_vl       = candidate_vl;
            selected_onehot   = candidate_onehot;

            selected_priority = candidate_priority;
            selected_age      = candidate_age;
            selected_score    = candidate_score;

        end

    end


    // ========================================================
    // Real scheduling event
    // ========================================================

    assign schedule_fire =
        schedule_valid &&
        grant_accept;


    // ========================================================
    // Hold control
    // ========================================================

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            hold_valid    <= 1'b0;
            hold_vl       <= 2'd0;

            hold_priority <= 2'd0;
            hold_age      <= 8'd0;
            hold_score    <= 9'd0;

        end

        else begin

            // ------------------------------------------------
            // Existing hold
            // ------------------------------------------------

            if (hold_valid) begin

                // VL lost legality before acceptance.
                if (!eligible[hold_vl]) begin

                    hold_valid <= 1'b0;

                end

                // Transaction completed.
                else if (schedule_fire) begin

                    hold_valid <= 1'b0;

                end

            end


            // ------------------------------------------------
            // No held transaction
            // ------------------------------------------------

            else begin

                if (candidate_valid) begin

                    // Immediate acceptance.
                    if (schedule_fire) begin

                        hold_valid <= 1'b0;

                    end

                    // Downstream stall.
                    else begin

                        hold_valid    <= 1'b1;
                        hold_vl       <= candidate_vl;

                        hold_priority <= candidate_priority;
                        hold_age      <= candidate_age;
                        hold_score    <= candidate_score;

                    end

                end

            end

        end

    end


    // ========================================================
    // Waiting-age update
    //
    // Rules:
    //
    // 1. Successful service -> reset age.
    // 2. Eligible but not served -> age++.
    // 3. Not eligible -> reset age.
    // 4. Saturate at 255.
    // ========================================================

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            wait_age0 <= 8'd0;
            wait_age1 <= 8'd0;
            wait_age2 <= 8'd0;
            wait_age3 <= 8'd0;

        end

        else begin

            // ------------------------------------------------
            // VL0
            // ------------------------------------------------

            if (schedule_fire &&
                (selected_vl == 2'd0)) begin

                wait_age0 <= 8'd0;

            end

            else if (eligible[0]) begin

                if (wait_age0 != 8'hFF)
                    wait_age0 <= wait_age0 + 8'd1;

            end

            else begin

                wait_age0 <= 8'd0;

            end


            // ------------------------------------------------
            // VL1
            // ------------------------------------------------

            if (schedule_fire &&
                (selected_vl == 2'd1)) begin

                wait_age1 <= 8'd0;

            end

            else if (eligible[1]) begin

                if (wait_age1 != 8'hFF)
                    wait_age1 <= wait_age1 + 8'd1;

            end

            else begin

                wait_age1 <= 8'd0;

            end


            // ------------------------------------------------
            // VL2
            // ------------------------------------------------

            if (schedule_fire &&
                (selected_vl == 2'd2)) begin

                wait_age2 <= 8'd0;

            end

            else if (eligible[2]) begin

                if (wait_age2 != 8'hFF)
                    wait_age2 <= wait_age2 + 8'd1;

            end

            else begin

                wait_age2 <= 8'd0;

            end


            // ------------------------------------------------
            // VL3
            // ------------------------------------------------

            if (schedule_fire &&
                (selected_vl == 2'd3)) begin

                wait_age3 <= 8'd0;

            end

            else if (eligible[3]) begin

                if (wait_age3 != 8'hFF)
                    wait_age3 <= wait_age3 + 8'd1;

            end

            else begin

                wait_age3 <= 8'd0;

            end

        end

    end


    // ========================================================
    // Debug
    // ========================================================

    assign wait_age0_dbg = wait_age0;
    assign wait_age1_dbg = wait_age1;
    assign wait_age2_dbg = wait_age2;
    assign wait_age3_dbg = wait_age3;


endmodule
