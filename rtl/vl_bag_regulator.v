`timescale 1ns / 1ps
// LEGACY (M4 TX path): not instantiated by AFDX_competition_top or the
// competition AFDX_top; retained only for legacy ModelSim regression
// coverage. Do not use for new work.


module vl_bag_regulator
(
    input  wire        clk,
    input  wire        rst_n,

    // VL configuration
    input  wire        vl_enable,
    input  wire [31:0] bag_cycles,

    // Assert for one clock when this VL is
    // actually accepted for transmission.
    input  wire        tx_commit,

    // BAG state
    output wire        bag_ready,
    output reg  [31:0] bag_counter
);


// ------------------------------------------------------------
// BAG semantics
//
// After reset:
//     bag_ready = 1
//
// After tx_commit:
//     block the VL for bag_cycles clocks.
//
// bag_counter represents remaining blocked clocks.
//
// bag_cycles == 0:
//     BAG disabled / always ready.
//
// Disabled VL:
//     counter cleared.
// ------------------------------------------------------------

assign bag_ready =
        vl_enable &&
        (bag_counter == 32'd0);


always @(posedge clk or negedge rst_n)
begin
    if (!rst_n)
    begin
        bag_counter <= 32'd0;
    end
    else
    begin

        // Disabled VL has no active BAG state.
        if (!vl_enable)
        begin
            bag_counter <= 32'd0;
        end

        // A successful transmission starts a new BAG interval.
        else if (tx_commit)
        begin
            if (bag_cycles == 32'd0)
                bag_counter <= 32'd0;
            else
                bag_counter <= bag_cycles;
        end

        // Count toward eligibility.
        else if (bag_counter != 32'd0)
        begin
            bag_counter <= bag_counter - 32'd1;
        end

        else
        begin
            bag_counter <= 32'd0;
        end

    end
end


endmodule
