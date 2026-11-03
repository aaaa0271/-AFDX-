module afdx_gmii_tx_top #(
// LEGACY (M4 TX path): not instantiated by AFDX_competition_top or the
// competition AFDX_top; retained only for legacy ModelSim regression
// coverage. Do not use for new work.
    parameter BAG_CYCLES = 400000
)(
    input  wire        clk,
    input  wire        rst,

    input  wire        tx_request,

    // Configurable frame fields
    input  wire [47:0] cfg_dst_mac,
    input  wire [47:0] cfg_src_mac,

    input  wire [31:0] cfg_src_ip,
    input  wire [31:0] cfg_dst_ip,

    input  wire [15:0] cfg_src_port,
    input  wire [15:0] cfg_dst_port,

    input  wire [31:0] payload_data,

    // GMII output
    output wire [7:0]  gmii_txd,
    output wire        gmii_tx_en,
    output wire        gmii_tx_er,

    // Status
    output wire        tx_busy,
    output wire        core_frame_done,
    output wire        gmii_frame_done,
    output wire        gmii_underrun
);


// ====================================================
// Internal ready/valid byte stream
// ====================================================

wire [7:0] s_data;
wire       s_valid;
wire       s_ready;


// ====================================================
// Existing M2-C AFDX TX engine
// ====================================================

afdx_tx_engine_cfg #(
    .BAG_CYCLES(BAG_CYCLES)
) u_engine (

    .clk          (clk),
    .rst          (rst),

    .tx_request   (tx_request),

    .cfg_dst_mac  (cfg_dst_mac),
    .cfg_src_mac  (cfg_src_mac),

    .cfg_src_ip   (cfg_src_ip),
    .cfg_dst_ip   (cfg_dst_ip),

    .cfg_src_port (cfg_src_port),
    .cfg_dst_port (cfg_dst_port),

    .payload_data (payload_data),

    .tx_data      (s_data),
    .tx_valid     (s_valid),
    .tx_ready     (s_ready),

    .busy         (tx_busy),
    .frame_done   (core_frame_done)

);


// ====================================================
// New GMII TX adapter
// ====================================================

gmii_tx_adapter_60 u_adapter (

    .clk          (clk),
    .rst          (rst),

    .s_data       (s_data),
    .s_valid      (s_valid),
    .s_ready      (s_ready),

    .gmii_txd     (gmii_txd),
    .gmii_tx_en   (gmii_tx_en),
    .gmii_tx_er   (gmii_tx_er),

    .frame_done   (gmii_frame_done),
    .underrun     (gmii_underrun)

);

endmodule
