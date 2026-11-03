`timescale 1ns / 1ps
// LEGACY (M4 TX path): not instantiated by AFDX_competition_top or the
// competition AFDX_top; retained only for legacy ModelSim regression
// coverage. Do not use for new work.

module vl_scheduler_rr (
    input  wire       clk,
    input  wire       rst_n,

    // Eligible VLs from M4-C
    input  wire [3:0] eligible,

    // Downstream accepted the currently selected VL.
    // This must mean "real transmission launch accepted",
    // not merely "scheduler selected a VL".
    input  wire       grant_accept,

    // Scheduler output
    output reg        schedule_valid,
    output reg  [1:0] selected_vl,
    output reg  [3:0] selected_onehot,

    // valid && accept
    output wire       schedule_fire,

    // Debug / verification
    output wire [1:0] last_grant_dbg
);


    // ========================================================
    // Round-robin state
    // ========================================================

    reg [1:0] last_grant;


    // ========================================================
    // Hold state
    //
    // If the selected VL is not accepted immediately,
    // keep the same VL stable until it is accepted or
    // becomes ineligible.
    // ========================================================

    reg       hold_valid;
    reg [1:0] hold_vl;


    // ========================================================
    // Combinational RR candidate
    // ========================================================

    reg       candidate_valid;
    reg [1:0] candidate_vl;
    reg [3:0] candidate_onehot;


    always @* begin

        candidate_valid  = 1'b0;
        candidate_vl     = 2'd0;
        candidate_onehot = 4'b0000;


        case (last_grant)

            // Last accepted VL0:
            // search 1 -> 2 -> 3 -> 0
            2'd0: begin

                if (eligible[1]) begin
                    candidate_valid  = 1'b1;
                    candidate_vl     = 2'd1;
                    candidate_onehot = 4'b0010;
                end
                else if (eligible[2]) begin
                    candidate_valid  = 1'b1;
                    candidate_vl     = 2'd2;
                    candidate_onehot = 4'b0100;
                end
                else if (eligible[3]) begin
                    candidate_valid  = 1'b1;
                    candidate_vl     = 2'd3;
                    candidate_onehot = 4'b1000;
                end
                else if (eligible[0]) begin
                    candidate_valid  = 1'b1;
                    candidate_vl     = 2'd0;
                    candidate_onehot = 4'b0001;
                end

            end


            // Last accepted VL1:
            // search 2 -> 3 -> 0 -> 1
            2'd1: begin

                if (eligible[2]) begin
                    candidate_valid  = 1'b1;
                    candidate_vl     = 2'd2;
                    candidate_onehot = 4'b0100;
                end
                else if (eligible[3]) begin
                    candidate_valid  = 1'b1;
                    candidate_vl     = 2'd3;
                    candidate_onehot = 4'b1000;
                end
                else if (eligible[0]) begin
                    candidate_valid  = 1'b1;
                    candidate_vl     = 2'd0;
                    candidate_onehot = 4'b0001;
                end
                else if (eligible[1]) begin
                    candidate_valid  = 1'b1;
                    candidate_vl     = 2'd1;
                    candidate_onehot = 4'b0010;
                end

            end


            // Last accepted VL2:
            // search 3 -> 0 -> 1 -> 2
            2'd2: begin

                if (eligible[3]) begin
                    candidate_valid  = 1'b1;
                    candidate_vl     = 2'd3;
                    candidate_onehot = 4'b1000;
                end
                else if (eligible[0]) begin
                    candidate_valid  = 1'b1;
                    candidate_vl     = 2'd0;
                    candidate_onehot = 4'b0001;
                end
                else if (eligible[1]) begin
                    candidate_valid  = 1'b1;
                    candidate_vl     = 2'd1;
                    candidate_onehot = 4'b0010;
                end
                else if (eligible[2]) begin
                    candidate_valid  = 1'b1;
                    candidate_vl     = 2'd2;
                    candidate_onehot = 4'b0100;
                end

            end


            // Last accepted VL3:
            // search 0 -> 1 -> 2 -> 3
            2'd3: begin

                if (eligible[0]) begin
                    candidate_valid  = 1'b1;
                    candidate_vl     = 2'd0;
                    candidate_onehot = 4'b0001;
                end
                else if (eligible[1]) begin
                    candidate_valid  = 1'b1;
                    candidate_vl     = 2'd1;
                    candidate_onehot = 4'b0010;
                end
                else if (eligible[2]) begin
                    candidate_valid  = 1'b1;
                    candidate_vl     = 2'd2;
                    candidate_onehot = 4'b0100;
                end
                else if (eligible[3]) begin
                    candidate_valid  = 1'b1;
                    candidate_vl     = 2'd3;
                    candidate_onehot = 4'b1000;
                end

            end


            default: begin

                candidate_valid  = 1'b0;
                candidate_vl     = 2'd0;
                candidate_onehot = 4'b0000;

            end

        endcase

    end


    // ========================================================
    // Scheduler output
    // ========================================================

    always @* begin

        schedule_valid   = 1'b0;
        selected_vl      = 2'd0;
        selected_onehot  = 4'b0000;


        // ----------------------------------------------------
        // Held request has priority over a new arbitration.
        // ----------------------------------------------------

        if (hold_valid) begin

            // A held VL is only valid while it remains eligible.
            if (eligible[hold_vl]) begin

                schedule_valid = 1'b1;
                selected_vl    = hold_vl;

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
        // Otherwise expose current RR candidate.
        // ----------------------------------------------------

        else if (candidate_valid) begin

            schedule_valid  = candidate_valid;
            selected_vl     = candidate_vl;
            selected_onehot = candidate_onehot;

        end

    end


    // ========================================================
    // Actual successful arbitration event
    // ========================================================

    assign schedule_fire =
        schedule_valid &&
        grant_accept;


    // ========================================================
    // Sequential scheduler state
    // ========================================================

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            // Reset to VL3 so the first RR search starts at VL0.
            last_grant <= 2'd3;

            hold_valid <= 1'b0;
            hold_vl    <= 2'd0;

        end
        else begin

            // ------------------------------------------------
            // Existing held request
            // ------------------------------------------------

            if (hold_valid) begin

                // If configuration / eligibility changes and
                // the VL becomes illegal, cancel the hold.
                if (!eligible[hold_vl]) begin

                    hold_valid <= 1'b0;

                end

                // Advance RR state only after real acceptance.
                else if (schedule_fire) begin

                    last_grant <= hold_vl;
                    hold_valid <= 1'b0;

                end

            end

            // ------------------------------------------------
            // No held request
            // ------------------------------------------------

            else begin

                if (candidate_valid) begin

                    // Accepted immediately.
                    if (schedule_fire) begin

                        last_grant <= candidate_vl;

                    end

                    // Not accepted yet:
                    // lock current arbitration result.
                    else begin

                        hold_valid <= 1'b1;
                        hold_vl    <= candidate_vl;

                    end

                end

            end

        end

    end


    assign last_grant_dbg = last_grant;


endmodule
