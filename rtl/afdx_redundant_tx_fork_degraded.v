`timescale 1ns / 1ps

module afdx_redundant_tx_fork_degraded (
    input  wire       clk,
    input  wire       rst_n,

    // ========================================================
    // Active physical networks
    //
    // Enable changes are expected only while logical TX
    // is quiescent.
    // ========================================================

    input  wire       network_a_enable,
    input  wire       network_b_enable,

    // ========================================================
    // Logical source stream
    // ========================================================

    input  wire [7:0] s_data,
    input  wire       s_valid,
    output wire       s_ready,

    // ========================================================
    // Network A
    // ========================================================

    output wire [7:0] a_data,
    output wire       a_valid,
    input  wire       a_ready,

    // ========================================================
    // Network B
    // ========================================================

    output wire [7:0] b_data,
    output wire       b_valid,
    input  wire       b_ready,

    // ========================================================
    // Debug
    // ========================================================

    output wire       fork_fire,
    output wire       any_network_enabled,
    output wire       degraded_mode
);


    reg a_done;
    reg b_done;


    wire a_take;
    wire b_take;

    wire a_complete;
    wire b_complete;


    // ========================================================
    // Network mode
    // ========================================================

    assign any_network_enabled =
        network_a_enable ||
        network_b_enable;


    assign degraded_mode =
        any_network_enabled &&
        !(network_a_enable &&
          network_b_enable);


    // ========================================================
    // Data duplication
    // ========================================================

    assign a_data = s_data;
    assign b_data = s_data;


    // ========================================================
    // A disabled branch is not a required participant.
    // ========================================================

    assign a_valid =
        s_valid &&
        network_a_enable &&
        !a_done;


    assign b_valid =
        s_valid &&
        network_b_enable &&
        !b_done;


    assign a_take =
        a_valid &&
        a_ready;


    assign b_take =
        b_valid &&
        b_ready;


    // ========================================================
    // Completion for current logical byte
    //
    // Disabled branch is treated as already complete.
    // ========================================================

    assign a_complete =
        (!network_a_enable) ||
        a_done ||
        a_take;


    assign b_complete =
        (!network_b_enable) ||
        b_done ||
        b_take;


    // ========================================================
    // Source can advance only after every ENABLED network
    // has consumed the current logical byte.
    //
    // If both networks are disabled, source stays blocked.
    // ========================================================

    assign s_ready =
        any_network_enabled &&
        a_complete &&
        b_complete;


    assign fork_fire =
        s_valid &&
        s_ready;


    // ========================================================
    // Per-byte consumption state
    // ========================================================

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            a_done <= 1'b0;
            b_done <= 1'b0;

        end

        else begin

            // Current logical source byte is fully complete.
            if (fork_fire) begin

                a_done <= 1'b0;
                b_done <= 1'b0;

            end

            else begin

                if (!network_a_enable)
                    a_done <= 1'b0;
                else if (a_take)
                    a_done <= 1'b1;


                if (!network_b_enable)
                    b_done <= 1'b0;
                else if (b_take)
                    b_done <= 1'b1;

            end

        end

    end


endmodule
