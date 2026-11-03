`timescale 1ns / 1ps
// LEGACY (M4 TX path): not instantiated by AFDX_competition_top or the
// competition AFDX_top; retained only for legacy ModelSim regression
// coverage. Do not use for new work.


module per_vl_bag_regulator
(
    input  wire        clk,
    input  wire        rst_n,

    // --------------------------------------------------------
    // Per-VL configuration
    // --------------------------------------------------------

    input  wire [31:0] bag0,
    input  wire [31:0] bag1,
    input  wire [31:0] bag2,
    input  wire [31:0] bag3,

    input  wire [3:0]  vl_enable,

    // --------------------------------------------------------
    // FIFO state from M4-B
    //
    // bit 0 -> VL0
    // bit 1 -> VL1
    // bit 2 -> VL2
    // bit 3 -> VL3
    // --------------------------------------------------------

    input  wire [3:0]  fifo_empty,

    // --------------------------------------------------------
    // Transmission commit from future M4-D/M4-E
    //
    // One-hot:
    //
    // 0001 -> VL0 transmitted
    // 0010 -> VL1 transmitted
    // 0100 -> VL2 transmitted
    // 1000 -> VL3 transmitted
    // --------------------------------------------------------

    input  wire [3:0]  tx_commit,

    // --------------------------------------------------------
    // BAG outputs
    // --------------------------------------------------------

    output wire [3:0]  bag_ready,
    output wire [3:0]  eligible,

    // Debug / verification
    output wire [31:0] bag_counter0,
    output wire [31:0] bag_counter1,
    output wire [31:0] bag_counter2,
    output wire [31:0] bag_counter3
);


// ============================================================
// VL0
// ============================================================

vl_bag_regulator u_bag_vl0
(
    .clk         (clk),
    .rst_n       (rst_n),

    .vl_enable   (vl_enable[0]),
    .bag_cycles  (bag0),

    .tx_commit   (tx_commit[0]),

    .bag_ready   (bag_ready[0]),
    .bag_counter (bag_counter0)
);


// ============================================================
// VL1
// ============================================================

vl_bag_regulator u_bag_vl1
(
    .clk         (clk),
    .rst_n       (rst_n),

    .vl_enable   (vl_enable[1]),
    .bag_cycles  (bag1),

    .tx_commit   (tx_commit[1]),

    .bag_ready   (bag_ready[1]),
    .bag_counter (bag_counter1)
);


// ============================================================
// VL2
// ============================================================

vl_bag_regulator u_bag_vl2
(
    .clk         (clk),
    .rst_n       (rst_n),

    .vl_enable   (vl_enable[2]),
    .bag_cycles  (bag2),

    .tx_commit   (tx_commit[2]),

    .bag_ready   (bag_ready[2]),
    .bag_counter (bag_counter2)
);


// ============================================================
// VL3
// ============================================================

vl_bag_regulator u_bag_vl3
(
    .clk         (clk),
    .rst_n       (rst_n),

    .vl_enable   (vl_enable[3]),
    .bag_cycles  (bag3),

    .tx_commit   (tx_commit[3]),

    .bag_ready   (bag_ready[3]),
    .bag_counter (bag_counter3)
);


// ============================================================
// Eligibility
//
// A VL may participate in scheduling only when:
//
//     1. VL enabled
//     2. FIFO contains pending data
//     3. BAG interval expired
//
// vl_enable is already included in bag_ready, therefore:
// ============================================================

assign eligible[0] = (!fifo_empty[0]) && bag_ready[0];
assign eligible[1] = (!fifo_empty[1]) && bag_ready[1];
assign eligible[2] = (!fifo_empty[2]) && bag_ready[2];
assign eligible[3] = (!fifo_empty[3]) && bag_ready[3];


endmodule
