// ============================================================
// LEGACY (M4 TX path): not instantiated by AFDX_competition_top or the
// competition AFDX_top; retained only for legacy ModelSim regression
// coverage. Do not use for new work.
// vl_config.v
//
// M4-A : Per-VL Configuration Table
//
// Holds the per-Virtual-Link configuration consumed by the M4
// scheduler. Each VL stores:
//
//   enable      : is the VL active
//   BAG         : bandwidth allocation gap
//   LMAX        : maximum frame length
//   priority    : scheduling priority
//   destination : destination port / VL info
//
// A configuration write on cfg_we also sets that VL's enable
// bit. After reset every VL is disabled and all fields are 0.
//
// The scheduler reads a whole VL row combinationaly through
// query_vl_id.
// ============================================================

`include "vl_config_pkg.v"

module vl_config #(
    parameter VL_NUM = `VL_NUM
)(
    input  wire clk,
    input  wire rst_n,


    // ========================================================
    // Configuration write interface
    // ========================================================

    input  wire cfg_we,
    input  wire [1:0] cfg_vl_id,

    input  wire [`BAG_WIDTH-1:0]      cfg_bag,
    input  wire [`LMAX_WIDTH-1:0]     cfg_lmax,
    input  wire [`PRIORITY_WIDTH-1:0] cfg_priority,
    input  wire [`DEST_WIDTH-1:0]     cfg_destination,


    // ========================================================
    // Scheduler read interface
    // ========================================================

    input  wire [1:0] query_vl_id,

    output reg [`BAG_WIDTH-1:0]      vl_bag,
    output reg [`LMAX_WIDTH-1:0]     vl_lmax,
    output reg [`PRIORITY_WIDTH-1:0] vl_priority,
    output reg [`DEST_WIDTH-1:0]     vl_destination,
    output reg                       vl_enable,


    // ========================================================
    // Parallel read view (read-only, combinational)
    //
    // M4-C needs all 4 BAG values simultaneously and M4-D2/D3
    // need all 4 priority values simultaneously. These are
    // combinational copies of the configuration tables, not
    // separate storage.
    // ========================================================

    output wire [`BAG_WIDTH-1:0]      bag0,
    output wire [`BAG_WIDTH-1:0]      bag1,
    output wire [`BAG_WIDTH-1:0]      bag2,
    output wire [`BAG_WIDTH-1:0]      bag3,

    output wire [`PRIORITY_WIDTH-1:0] priority0,
    output wire [`PRIORITY_WIDTH-1:0] priority1,
    output wire [`PRIORITY_WIDTH-1:0] priority2,
    output wire [`PRIORITY_WIDTH-1:0] priority3,

    output wire [3:0]                 enable_all
);


// ============================================================
// Configuration tables
// ============================================================

reg [`BAG_WIDTH-1:0]      bag_table         [0:VL_NUM-1];
reg [`LMAX_WIDTH-1:0]     lmax_table        [0:VL_NUM-1];
reg [`PRIORITY_WIDTH-1:0] priority_table    [0:VL_NUM-1];
reg [`DEST_WIDTH-1:0]     destination_table [0:VL_NUM-1];
reg                       enable_table      [0:VL_NUM-1];

integer i;


// ============================================================
// Configuration write
//
// cfg_we writes a full row and enables that VL.
// ============================================================

always @(posedge clk or negedge rst_n) begin

    if (!rst_n) begin

        for (i = 0; i < VL_NUM; i = i + 1) begin

            bag_table[i]         <= `BAG_WIDTH'd0;
            lmax_table[i]        <= `LMAX_WIDTH'd0;
            priority_table[i]    <= `PRIORITY_WIDTH'd0;
            destination_table[i] <= `DEST_WIDTH'd0;
            enable_table[i]      <= 1'b0;

        end

    end
    else begin

        if (cfg_we) begin

            bag_table[cfg_vl_id]         <= cfg_bag;
            lmax_table[cfg_vl_id]        <= cfg_lmax;
            priority_table[cfg_vl_id]    <= cfg_priority;
            destination_table[cfg_vl_id] <= cfg_destination;
            enable_table[cfg_vl_id]      <= 1'b1;

        end

    end

end


// ============================================================
// Configuration read
// ============================================================

always @(*) begin

    vl_bag         = bag_table[query_vl_id];
    vl_lmax        = lmax_table[query_vl_id];
    vl_priority    = priority_table[query_vl_id];
    vl_destination = destination_table[query_vl_id];
    vl_enable      = enable_table[query_vl_id];

end


// ============================================================
// Parallel read view
// ============================================================

assign bag0 = bag_table[0];
assign bag1 = bag_table[1];
assign bag2 = bag_table[2];
assign bag3 = bag_table[3];

assign priority0 = priority_table[0];
assign priority1 = priority_table[1];
assign priority2 = priority_table[2];
assign priority3 = priority_table[3];

assign enable_all[0] = enable_table[0];
assign enable_all[1] = enable_table[1];
assign enable_all[2] = enable_table[2];
assign enable_all[3] = enable_table[3];


endmodule
