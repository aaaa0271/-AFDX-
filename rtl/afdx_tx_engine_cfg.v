module afdx_tx_engine_cfg #(
// LEGACY (M4 TX path): not instantiated by AFDX_competition_top or the
// competition AFDX_top; retained only for legacy ModelSim regression
// coverage. Do not use for new work.
    parameter BAG_CYCLES = 400000
)(
    input  wire        clk,
    input  wire        rst,

    // Traffic pending
    input  wire        tx_request,

    // ----------------------------------------------
    // Frame configuration
    // ----------------------------------------------

    input  wire [47:0] cfg_dst_mac,
    input  wire [47:0] cfg_src_mac,

    input  wire [31:0] cfg_src_ip,
    input  wire [31:0] cfg_dst_ip,

    input  wire [15:0] cfg_src_port,
    input  wire [15:0] cfg_dst_port,

    input  wire [31:0] payload_data,


    // ----------------------------------------------
    // Output stream
    // ----------------------------------------------

    output wire [7:0]  tx_data,
    output wire        tx_valid,
    input  wire        tx_ready,

    output wire        busy,
    output wire        frame_done
);


wire frame_start;
wire [7:0] frame_seq_num;

wire builder_busy;


// ----------------------------------------------------
// BAG + Sequence Control
// ----------------------------------------------------

afdx_tx_ctrl #(
    .BAG_CYCLES(BAG_CYCLES)
) u_tx_ctrl (

    .clk           (clk),
    .rst           (rst),

    .tx_request    (tx_request),

    .frame_ready   (~builder_busy),

    .frame_start   (frame_start),
    .frame_seq_num (frame_seq_num)

);


// ----------------------------------------------------
// Configurable AFDX Frame Builder
// ----------------------------------------------------

afdx_frame_builder_cfg u_frame_builder (

    .clk          (clk),
    .rst          (rst),

    .start        (frame_start),
    .seq_num      (frame_seq_num),

    .cfg_dst_mac  (cfg_dst_mac),
    .cfg_src_mac  (cfg_src_mac),

    .cfg_src_ip   (cfg_src_ip),
    .cfg_dst_ip   (cfg_dst_ip),

    .cfg_src_port (cfg_src_port),
    .cfg_dst_port (cfg_dst_port),

    .payload_data (payload_data),

    .tx_data      (tx_data),
    .tx_valid     (tx_valid),
    .tx_ready     (tx_ready),

    .busy         (builder_busy),
    .done         (frame_done)

);


assign busy = builder_busy;


endmodule
