`timescale 1ns / 1ps

module afdx_redundant_tx_fork (
    input  wire       clk,
    input  wire       rst_n,

    input  wire [7:0] s_data,
    input  wire       s_valid,
    output wire       s_ready,

    output wire [7:0] a_data,
    output wire       a_valid,
    input  wire       a_ready,

    output wire [7:0] b_data,
    output wire       b_valid,
    input  wire       b_ready,

    output wire       fork_fire
);


    // Current source byte has already been accepted
    // by the corresponding branch.
    reg a_done;
    reg b_done;


    wire a_take;
    wire b_take;

    wire a_complete;
    wire b_complete;


    // Same source byte is presented to both networks.
    assign a_data = s_data;
    assign b_data = s_data;


    // Valid does NOT depend on ready.
    //
    // Once one branch has consumed the current byte,
    // valid is suppressed only for that branch.
    assign a_valid =
        s_valid && !a_done;

    assign b_valid =
        s_valid && !b_done;


    assign a_take =
        a_valid && a_ready;

    assign b_take =
        b_valid && b_ready;


    // Has each branch consumed the current source byte,
    // either previously or on this clock?
    assign a_complete =
        a_done || a_take;

    assign b_complete =
        b_done || b_take;


    // Source may advance only when BOTH redundant paths
    // have consumed this exact byte.
    assign s_ready =
        a_complete &&
        b_complete;


    // One logical redundant-byte transaction is complete.
    assign fork_fire =
        s_valid &&
        s_ready;


    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            a_done <= 1'b0;
            b_done <= 1'b0;

        end

        else begin

            // Current source byte completed on both paths.
            // Prepare state for the next source byte.
            if (fork_fire) begin

                a_done <= 1'b0;
                b_done <= 1'b0;

            end

            else begin

                if (a_take)
                    a_done <= 1'b1;

                if (b_take)
                    b_done <= 1'b1;

            end

        end

    end


endmodule
