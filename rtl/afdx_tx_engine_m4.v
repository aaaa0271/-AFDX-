`timescale 1ns / 1ps
// LEGACY (M4 TX path): not instantiated by AFDX_competition_top or the
// competition AFDX_top; retained only for legacy ModelSim regression
// coverage. Do not use for new work.

module afdx_tx_engine_m4 (
    input  wire        clk,
    input  wire        rst_n,

    // --------------------------------------------------------
    // Scheduler -> TX handshake
    // --------------------------------------------------------

    input  wire        frame_request,

    // Builder can accept one new frame.
    output wire        frame_ready,

    // --------------------------------------------------------
    // Per-VL sequence supplied by M4
    // --------------------------------------------------------

    input  wire [7:0]  seq_num,

    // --------------------------------------------------------
    // Selected VL network configuration
    // --------------------------------------------------------

    input  wire [47:0] cfg_dst_mac,
    input  wire [47:0] cfg_src_mac,

    input  wire [31:0] cfg_src_ip,
    input  wire [31:0] cfg_dst_ip,

    input  wire [15:0] cfg_src_port,
    input  wire [15:0] cfg_dst_port,

    // --------------------------------------------------------
    // Existing fixed 4-byte payload
    // --------------------------------------------------------

    input  wire [31:0] payload_data,

    // --------------------------------------------------------
    // Existing 60-byte body stream
    // --------------------------------------------------------

    output wire [7:0]  tx_data,
    output wire        tx_valid,
    input  wire        tx_ready,

    // --------------------------------------------------------
    // Status
    // --------------------------------------------------------

    output wire        busy,
    output wire        frame_done,

    output wire        frame_start_dbg
);


    wire builder_busy;

    wire frame_start;


    // ========================================================
    // REAL TX ACCEPTANCE
    //
    // No BAG here.
    // No sequence generator here.
    //
    // The builder is the acceptance authority.
    // ========================================================

    assign frame_ready =
        !builder_busy;


    assign frame_start =
        frame_request &&
        frame_ready;


    // ========================================================
    // Existing verified Frame Builder
    // ========================================================

    afdx_frame_builder_cfg u_frame_builder (
        .clk          (clk),
        .rst          (~rst_n),

        .start        (frame_start),

        .seq_num      (seq_num),

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


    assign busy =
        builder_busy;


    assign frame_start_dbg =
        frame_start;


endmodule
