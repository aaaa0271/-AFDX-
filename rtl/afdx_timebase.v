`timescale 1ns/1ps
// LEGACY (M4 shared time base): not instantiated by AFDX_competition_top or
// AFDX_top; retained for legacy ModelSim regression coverage. Do not use for
// new work.
module afdx_timebase #(
    parameter integer CLK_HZ = 100000000
)(
    input  wire        clk,
    input  wire        rst,

    output reg         tick_1us,
    output reg         tick_1ms,
    output reg [63:0]  time_us
);

// ============================================================
// Project common time base
//
// Default:
//   CLK_HZ = 100 MHz
//
// Output:
//   tick_1us : one-clock pulse every 1 us
//   tick_1ms : one-clock pulse every 1 ms
//   time_us  : monotonic 64-bit microsecond counter
//
// Bresenham-style fractional divider. The previous implementation truncated
// CLK_HZ/1_000_000, which made "1 us" 0.96 us at 12.5 MHz (-4.2%) and stopped
// advancing entirely for CLK_HZ below 1 MHz. The phase accumulator spreads
// the fractional cycle across boundaries (12/13 cycle alternation at
// 12.5 MHz -> zero average error), and the resolution loop also supports
// clock rates below 1 MHz (multiple us per clock: time_us jumps by the full
// amount while tick_1us stays a single-width pulse).
// ============================================================

localparam [63:0] US_NUMER = 64'd1_000_000;

reg [63:0] us_phase;
reg [9:0]  us_in_ms;

// Synthesis temporaries (blocking, resolved within one clock edge).
reg [63:0] phase;
integer    us_inc;
reg [9:0]  ms_run;
reg        ms_pulse;
integer    j;

always @(posedge clk) begin

    if (rst) begin

        us_phase    <= 64'd0;
        us_in_ms    <= 10'd0;
        tick_1us    <= 1'b0;
        tick_1ms    <= 1'b0;
        time_us     <= 64'd0;

    end
    else begin

        // Pulses are low by default.
        tick_1us <= 1'b0;
        tick_1ms <= 1'b0;

        // Resolve every whole microsecond gained on this clock.
        phase  = us_phase + US_NUMER;
        us_inc = 0;
        while (phase >= CLK_HZ) begin
            phase  = phase - CLK_HZ;
            us_inc = us_inc + 1;
        end
        us_phase <= phase;

        if (us_inc > 0) begin

            tick_1us <= 1'b1;
            time_us  <= time_us + us_inc;

            // 1000 us = 1 ms
            ms_run   = us_in_ms;
            ms_pulse = 1'b0;
            for (j = 0; j < us_inc; j = j + 1) begin
                if (ms_run == 10'd999) begin
                    ms_run   = 10'd0;
                    ms_pulse = 1'b1;
                end
                else begin
                    ms_run = ms_run + 10'd1;
                end
            end
            us_in_ms <= ms_run;
            tick_1ms <= ms_pulse;

        end

    end

end

endmodule
