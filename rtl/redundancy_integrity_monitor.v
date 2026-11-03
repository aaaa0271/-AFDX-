`timescale 1ns / 1ps

module redundancy_integrity_monitor (
    input  wire        clk,
    input  wire        rst_n,

    // ========================================================
    // Monitor control
    // ========================================================

    input  wire        monitor_clear,
    input  wire        monitor_enable,

    // ========================================================
    // Network A GMII observation
    // ========================================================

    input  wire [7:0]  gmii_a_txd,
    input  wire        gmii_a_tx_en,
    input  wire        gmii_a_tx_er,

    input  wire        gmii_a_frame_done,
    input  wire        gmii_a_underrun,

    // ========================================================
    // Network B GMII observation
    // ========================================================

    input  wire [7:0]  gmii_b_txd,
    input  wire        gmii_b_tx_en,
    input  wire        gmii_b_tx_er,

    input  wire        gmii_b_frame_done,
    input  wire        gmii_b_underrun,

    // ========================================================
    // Health
    //
    // redundancy_ok is sticky.
    //
    // Once a fault is observed:
    //
    // redundancy_ok = 0
    //
    // until monitor_clear or reset.
    // ========================================================

    output reg         redundancy_ok,
    output wire        fault_event,

    // ========================================================
    // Physical accounting
    // ========================================================

    output reg  [31:0] a_frame_count,
    output reg  [31:0] b_frame_count,

    output reg  [31:0] a_active_byte_count,
    output reg  [31:0] b_active_byte_count,

    // ========================================================
    // Redundancy mismatch metrics
    // ========================================================

    output reg  [31:0] byte_mismatch_count,

    output reg  [31:0] frame_skew_cycle_count,
    output reg  [31:0] frame_done_skew_count,

    output reg  [31:0] tx_er_mismatch_count,

    // ========================================================
    // Per-network physical error metrics
    // ========================================================

    output reg  [31:0] a_tx_error_cycle_count,
    output reg  [31:0] b_tx_error_cycle_count,

    output reg  [31:0] a_underrun_count,
    output reg  [31:0] b_underrun_count,

    // ========================================================
    // Instantaneous summary
    // ========================================================

    output wire        frame_count_match,
    output wire        active_byte_count_match
);


    // ========================================================
    // Instantaneous mismatch conditions
    // ========================================================

    wire byte_mismatch_now;

    wire frame_skew_now;
    wire frame_done_skew_now;

    wire tx_er_mismatch_now;

    wire physical_error_now;


    // Compare data only while BOTH physical networks are
    // transmitting a valid GMII byte.
    assign byte_mismatch_now =
        gmii_a_tx_en &&
        gmii_b_tx_en &&
        (gmii_a_txd != gmii_b_txd);


    // A/B physical transmit windows are not aligned.
    assign frame_skew_now =
        gmii_a_tx_en != gmii_b_tx_en;


    // A/B completion pulses are not aligned.
    assign frame_done_skew_now =
        gmii_a_frame_done != gmii_b_frame_done;


    assign tx_er_mismatch_now =
        gmii_a_tx_er != gmii_b_tx_er;


    // Even if BOTH paths assert the same error together,
    // the redundant transmission is still unhealthy.
    assign physical_error_now =
        gmii_a_tx_er      ||
        gmii_b_tx_er      ||
        gmii_a_underrun   ||
        gmii_b_underrun;


    // One-cycle combinational indication.
    assign fault_event =
        monitor_enable &&
        (
            byte_mismatch_now   ||
            frame_skew_now      ||
            frame_done_skew_now ||
            tx_er_mismatch_now  ||
            physical_error_now
        );


    // ========================================================
    // Instantaneous count comparison
    // ========================================================

    assign frame_count_match =
        (a_frame_count == b_frame_count);


    assign active_byte_count_match =
        (a_active_byte_count ==
         b_active_byte_count);


    // ========================================================
    // Monitor registers
    // ========================================================

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            redundancy_ok <= 1'b1;


            a_frame_count <= 32'd0;
            b_frame_count <= 32'd0;


            a_active_byte_count <= 32'd0;
            b_active_byte_count <= 32'd0;


            byte_mismatch_count <= 32'd0;

            frame_skew_cycle_count <= 32'd0;
            frame_done_skew_count  <= 32'd0;

            tx_er_mismatch_count <= 32'd0;


            a_tx_error_cycle_count <= 32'd0;
            b_tx_error_cycle_count <= 32'd0;

            a_underrun_count <= 32'd0;
            b_underrun_count <= 32'd0;

        end

        else if (monitor_clear) begin

            redundancy_ok <= 1'b1;


            a_frame_count <= 32'd0;
            b_frame_count <= 32'd0;


            a_active_byte_count <= 32'd0;
            b_active_byte_count <= 32'd0;


            byte_mismatch_count <= 32'd0;

            frame_skew_cycle_count <= 32'd0;
            frame_done_skew_count  <= 32'd0;

            tx_er_mismatch_count <= 32'd0;


            a_tx_error_cycle_count <= 32'd0;
            b_tx_error_cycle_count <= 32'd0;

            a_underrun_count <= 32'd0;
            b_underrun_count <= 32'd0;

        end

        else if (monitor_enable) begin

            // =================================================
            // Physical frame accounting
            // =================================================

            if (gmii_a_frame_done)
                a_frame_count <=
                    a_frame_count + 32'd1;


            if (gmii_b_frame_done)
                b_frame_count <=
                    b_frame_count + 32'd1;


            // =================================================
            // Physical byte accounting
            // =================================================

            if (gmii_a_tx_en)
                a_active_byte_count <=
                    a_active_byte_count + 32'd1;


            if (gmii_b_tx_en)
                b_active_byte_count <=
                    b_active_byte_count + 32'd1;


            // =================================================
            // Data corruption
            // =================================================

            if (byte_mismatch_now)
                byte_mismatch_count <=
                    byte_mismatch_count + 32'd1;


            // =================================================
            // Frame-window skew
            //
            // Count every clock where one network is active
            // while the other is not.
            // =================================================

            if (frame_skew_now)
                frame_skew_cycle_count <=
                    frame_skew_cycle_count + 32'd1;


            // =================================================
            // Frame completion skew
            // =================================================

            if (frame_done_skew_now)
                frame_done_skew_count <=
                    frame_done_skew_count + 32'd1;


            // =================================================
            // TX error disagreement
            // =================================================

            if (tx_er_mismatch_now)
                tx_er_mismatch_count <=
                    tx_er_mismatch_count + 32'd1;


            // =================================================
            // Per-path physical errors
            // =================================================

            if (gmii_a_tx_er)
                a_tx_error_cycle_count <=
                    a_tx_error_cycle_count + 32'd1;


            if (gmii_b_tx_er)
                b_tx_error_cycle_count <=
                    b_tx_error_cycle_count + 32'd1;


            if (gmii_a_underrun)
                a_underrun_count <=
                    a_underrun_count + 32'd1;


            if (gmii_b_underrun)
                b_underrun_count <=
                    b_underrun_count + 32'd1;


            // =================================================
            // Sticky health
            // =================================================

            if (
                byte_mismatch_now   ||
                frame_skew_now      ||
                frame_done_skew_now ||
                tx_er_mismatch_now  ||
                physical_error_now
            ) begin

                redundancy_ok <= 1'b0;

            end

        end

    end


endmodule
