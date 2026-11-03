`timescale 1ns / 1ps
// LEGACY (M4 TX path): not instantiated by AFDX_competition_top or the
// competition AFDX_top; retained only for legacy ModelSim regression
// coverage. Do not use for new work.

module m4_metrics_monitor (
    input  wire        clk,
    input  wire        rst_n,

    // ========================================================
    // Measurement control
    // ========================================================

    input  wire        metrics_clear,
    input  wire        metrics_enable,

    // ========================================================
    // Independent observation points
    // ========================================================

    input  wire [3:0]  eligible,
    input  wire [3:0]  bag_ready,

    input  wire        schedule_fire,
    input  wire [1:0]  selected_vl,

    // ========================================================
    // Global
    // ========================================================

    output reg  [31:0] window_cycles,
    output reg  [31:0] total_commits,

    output reg  [31:0] bag_violation_count,
    output reg  [31:0] illegal_schedule_count,

    // ========================================================
    // Per-VL served count
    // ========================================================

    output reg  [31:0] served0,
    output reg  [31:0] served1,
    output reg  [31:0] served2,
    output reg  [31:0] served3,

    // ========================================================
    // Current eligible waiting time
    // ========================================================

    output reg  [31:0] current_wait0,
    output reg  [31:0] current_wait1,
    output reg  [31:0] current_wait2,
    output reg  [31:0] current_wait3,

    // ========================================================
    // Accumulated waiting time of SERVED frames
    // ========================================================

    output reg  [63:0] total_wait0,
    output reg  [63:0] total_wait1,
    output reg  [63:0] total_wait2,
    output reg  [63:0] total_wait3,

    // ========================================================
    // Maximum observed eligible wait
    //
    // This also includes currently-starved unsent traffic.
    // ========================================================

    output reg  [31:0] max_wait0,
    output reg  [31:0] max_wait1,
    output reg  [31:0] max_wait2,
    output reg  [31:0] max_wait3,

    // ========================================================
    // Service interval
    // ========================================================

    output reg  [31:0] min_interval0,
    output reg  [31:0] min_interval1,
    output reg  [31:0] min_interval2,
    output reg  [31:0] min_interval3,

    output reg  [31:0] max_interval0,
    output reg  [31:0] max_interval1,
    output reg  [31:0] max_interval2,
    output reg  [31:0] max_interval3
);


    // ========================================================
    // Last successful service timestamps
    // ========================================================

    reg [31:0] last_service0;
    reg [31:0] last_service1;
    reg [31:0] last_service2;
    reg [31:0] last_service3;


    reg seen_service0;
    reg seen_service1;
    reg seen_service2;
    reg seen_service3;


    reg seen_interval0;
    reg seen_interval1;
    reg seen_interval2;
    reg seen_interval3;


    // ========================================================
    // Main
    // ========================================================

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            window_cycles <= 32'd0;
            total_commits <= 32'd0;

            bag_violation_count    <= 32'd0;
            illegal_schedule_count <= 32'd0;


            served0 <= 32'd0;
            served1 <= 32'd0;
            served2 <= 32'd0;
            served3 <= 32'd0;


            current_wait0 <= 32'd0;
            current_wait1 <= 32'd0;
            current_wait2 <= 32'd0;
            current_wait3 <= 32'd0;


            total_wait0 <= 64'd0;
            total_wait1 <= 64'd0;
            total_wait2 <= 64'd0;
            total_wait3 <= 64'd0;


            max_wait0 <= 32'd0;
            max_wait1 <= 32'd0;
            max_wait2 <= 32'd0;
            max_wait3 <= 32'd0;


            min_interval0 <= 32'hFFFFFFFF;
            min_interval1 <= 32'hFFFFFFFF;
            min_interval2 <= 32'hFFFFFFFF;
            min_interval3 <= 32'hFFFFFFFF;

            max_interval0 <= 32'd0;
            max_interval1 <= 32'd0;
            max_interval2 <= 32'd0;
            max_interval3 <= 32'd0;


            last_service0 <= 32'd0;
            last_service1 <= 32'd0;
            last_service2 <= 32'd0;
            last_service3 <= 32'd0;


            seen_service0 <= 1'b0;
            seen_service1 <= 1'b0;
            seen_service2 <= 1'b0;
            seen_service3 <= 1'b0;

            seen_interval0 <= 1'b0;
            seen_interval1 <= 1'b0;
            seen_interval2 <= 1'b0;
            seen_interval3 <= 1'b0;

        end

        else if (metrics_clear) begin

            window_cycles <= 32'd0;
            total_commits <= 32'd0;

            bag_violation_count    <= 32'd0;
            illegal_schedule_count <= 32'd0;


            served0 <= 32'd0;
            served1 <= 32'd0;
            served2 <= 32'd0;
            served3 <= 32'd0;


            current_wait0 <= 32'd0;
            current_wait1 <= 32'd0;
            current_wait2 <= 32'd0;
            current_wait3 <= 32'd0;


            total_wait0 <= 64'd0;
            total_wait1 <= 64'd0;
            total_wait2 <= 64'd0;
            total_wait3 <= 64'd0;


            max_wait0 <= 32'd0;
            max_wait1 <= 32'd0;
            max_wait2 <= 32'd0;
            max_wait3 <= 32'd0;


            min_interval0 <= 32'hFFFFFFFF;
            min_interval1 <= 32'hFFFFFFFF;
            min_interval2 <= 32'hFFFFFFFF;
            min_interval3 <= 32'hFFFFFFFF;

            max_interval0 <= 32'd0;
            max_interval1 <= 32'd0;
            max_interval2 <= 32'd0;
            max_interval3 <= 32'd0;


            last_service0 <= 32'd0;
            last_service1 <= 32'd0;
            last_service2 <= 32'd0;
            last_service3 <= 32'd0;


            seen_service0 <= 1'b0;
            seen_service1 <= 1'b0;
            seen_service2 <= 1'b0;
            seen_service3 <= 1'b0;

            seen_interval0 <= 1'b0;
            seen_interval1 <= 1'b0;
            seen_interval2 <= 1'b0;
            seen_interval3 <= 1'b0;

        end

        else if (metrics_enable) begin

            // =================================================
            // Measurement time
            // =================================================

            if (window_cycles != 32'hFFFFFFFF)
                window_cycles <= window_cycles + 32'd1;


            // =================================================
            // Global transaction checks
            // =================================================

            if (schedule_fire) begin

                total_commits <=
                    total_commits + 32'd1;


                // BAG must still be ready on the accepting edge.
                if (!bag_ready[selected_vl]) begin

                    bag_violation_count <=
                        bag_violation_count + 32'd1;

                end


                // Stronger legality check.
                if (!eligible[selected_vl]) begin

                    illegal_schedule_count <=
                        illegal_schedule_count + 32'd1;

                end

            end


            // =================================================
            // VL0
            // =================================================

            if (schedule_fire &&
                (selected_vl == 2'd0)) begin

                served0 <= served0 + 32'd1;


                total_wait0 <=
                    total_wait0 +
                    {32'd0, current_wait0};


                if (current_wait0 > max_wait0)
                    max_wait0 <= current_wait0;


                current_wait0 <= 32'd0;


                // ---------------------------------------------
                // Service interval
                // ---------------------------------------------

                if (seen_service0) begin

                    if (!seen_interval0) begin

                        min_interval0 <=
                            window_cycles -
                            last_service0;

                        max_interval0 <=
                            window_cycles -
                            last_service0;

                        seen_interval0 <= 1'b1;

                    end

                    else begin

                        if ((window_cycles -
                             last_service0)
                            <
                            min_interval0)
                            min_interval0 <=
                                window_cycles -
                                last_service0;


                        if ((window_cycles -
                             last_service0)
                            >
                            max_interval0)
                            max_interval0 <=
                                window_cycles -
                                last_service0;

                    end

                end


                last_service0 <= window_cycles;
                seen_service0 <= 1'b1;

            end

            else if (eligible[0]) begin

                if (current_wait0 != 32'hFFFFFFFF) begin

                    current_wait0 <=
                        current_wait0 + 32'd1;


                    if ((current_wait0 + 32'd1)
                        >
                        max_wait0)
                        max_wait0 <=
                            current_wait0 + 32'd1;

                end

            end

            else begin

                current_wait0 <= 32'd0;

            end


            // =================================================
            // VL1
            // =================================================

            if (schedule_fire &&
                (selected_vl == 2'd1)) begin

                served1 <= served1 + 32'd1;


                total_wait1 <=
                    total_wait1 +
                    {32'd0, current_wait1};


                if (current_wait1 > max_wait1)
                    max_wait1 <= current_wait1;


                current_wait1 <= 32'd0;


                if (seen_service1) begin

                    if (!seen_interval1) begin

                        min_interval1 <=
                            window_cycles -
                            last_service1;

                        max_interval1 <=
                            window_cycles -
                            last_service1;

                        seen_interval1 <= 1'b1;

                    end

                    else begin

                        if ((window_cycles -
                             last_service1)
                            <
                            min_interval1)
                            min_interval1 <=
                                window_cycles -
                                last_service1;


                        if ((window_cycles -
                             last_service1)
                            >
                            max_interval1)
                            max_interval1 <=
                                window_cycles -
                                last_service1;

                    end

                end


                last_service1 <= window_cycles;
                seen_service1 <= 1'b1;

            end

            else if (eligible[1]) begin

                if (current_wait1 != 32'hFFFFFFFF) begin

                    current_wait1 <=
                        current_wait1 + 32'd1;


                    if ((current_wait1 + 32'd1)
                        >
                        max_wait1)
                        max_wait1 <=
                            current_wait1 + 32'd1;

                end

            end

            else begin

                current_wait1 <= 32'd0;

            end


            // =================================================
            // VL2
            // =================================================

            if (schedule_fire &&
                (selected_vl == 2'd2)) begin

                served2 <= served2 + 32'd1;


                total_wait2 <=
                    total_wait2 +
                    {32'd0, current_wait2};


                if (current_wait2 > max_wait2)
                    max_wait2 <= current_wait2;


                current_wait2 <= 32'd0;


                if (seen_service2) begin

                    if (!seen_interval2) begin

                        min_interval2 <=
                            window_cycles -
                            last_service2;

                        max_interval2 <=
                            window_cycles -
                            last_service2;

                        seen_interval2 <= 1'b1;

                    end

                    else begin

                        if ((window_cycles -
                             last_service2)
                            <
                            min_interval2)
                            min_interval2 <=
                                window_cycles -
                                last_service2;


                        if ((window_cycles -
                             last_service2)
                            >
                            max_interval2)
                            max_interval2 <=
                                window_cycles -
                                last_service2;

                    end

                end


                last_service2 <= window_cycles;
                seen_service2 <= 1'b1;

            end

            else if (eligible[2]) begin

                if (current_wait2 != 32'hFFFFFFFF) begin

                    current_wait2 <=
                        current_wait2 + 32'd1;


                    if ((current_wait2 + 32'd1)
                        >
                        max_wait2)
                        max_wait2 <=
                            current_wait2 + 32'd1;

                end

            end

            else begin

                current_wait2 <= 32'd0;

            end


            // =================================================
            // VL3
            // =================================================

            if (schedule_fire &&
                (selected_vl == 2'd3)) begin

                served3 <= served3 + 32'd1;


                total_wait3 <=
                    total_wait3 +
                    {32'd0, current_wait3};


                if (current_wait3 > max_wait3)
                    max_wait3 <= current_wait3;


                current_wait3 <= 32'd0;


                if (seen_service3) begin

                    if (!seen_interval3) begin

                        min_interval3 <=
                            window_cycles -
                            last_service3;

                        max_interval3 <=
                            window_cycles -
                            last_service3;

                        seen_interval3 <= 1'b1;

                    end

                    else begin

                        if ((window_cycles -
                             last_service3)
                            <
                            min_interval3)
                            min_interval3 <=
                                window_cycles -
                                last_service3;


                        if ((window_cycles -
                             last_service3)
                            >
                            max_interval3)
                            max_interval3 <=
                                window_cycles -
                                last_service3;

                    end

                end


                last_service3 <= window_cycles;
                seen_service3 <= 1'b1;

            end

            else if (eligible[3]) begin

                if (current_wait3 != 32'hFFFFFFFF) begin

                    current_wait3 <=
                        current_wait3 + 32'd1;


                    if ((current_wait3 + 32'd1)
                        >
                        max_wait3)
                        max_wait3 <=
                            current_wait3 + 32'd1;

                end

            end

            else begin

                current_wait3 <= 32'd0;

            end

        end

    end


endmodule
