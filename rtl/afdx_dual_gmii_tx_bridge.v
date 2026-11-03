`timescale 1ns / 1ps
// LEGACY (M4 TX path): not instantiated by AFDX_competition_top or the
// competition AFDX_top; retained only for legacy ModelSim regression
// coverage. Do not use for new work.

module afdx_dual_gmii_tx_bridge (
    input  wire       clk,
    input  wire       rst_n,

    // ========================================================
    // Logical 60-byte body stream from Frame Builder
    // ========================================================

    input  wire [7:0] s_data,
    input  wire       s_valid,
    output wire       s_ready,

    // ========================================================
    // Network A GMII
    // ========================================================

    output wire [7:0] gmii_a_txd,
    output wire       gmii_a_tx_en,
    output wire       gmii_a_tx_er,

    output wire       gmii_a_frame_done,
    output wire       gmii_a_underrun,

    // ========================================================
    // Network B GMII
    // ========================================================

    output wire [7:0] gmii_b_txd,
    output wire       gmii_b_tx_en,
    output wire       gmii_b_tx_er,

    output wire       gmii_b_frame_done,
    output wire       gmii_b_underrun,

    // ========================================================
    // Fork debug
    // ========================================================

    output wire       fork_fire_dbg,

    output wire [7:0] a_stream_data_dbg,
    output wire       a_stream_valid_dbg,
    output wire       a_stream_ready_dbg,

    output wire [7:0] b_stream_data_dbg,
    output wire       b_stream_valid_dbg,
    output wire       b_stream_ready_dbg,

    output wire       redundant_frame_done_dbg
);


    // ========================================================
    // Fork branch streams
    // ========================================================

    wire [7:0] a_stream_data;
    wire       a_stream_valid;
    wire       a_stream_ready;

    wire [7:0] b_stream_data;
    wire       b_stream_valid;
    wire       b_stream_ready;

    wire       fork_fire;


    // ========================================================
    // Stateful multicast fork
    //
    // - valid does not depend on ready
    // - each branch consumes every byte exactly once
    // - source advances only after BOTH branches complete
    // ========================================================

    afdx_redundant_tx_fork u_redundant_fork (
        .clk       (clk),
        .rst_n     (rst_n),

        .s_data    (s_data),
        .s_valid   (s_valid),
        .s_ready   (s_ready),

        .a_data    (a_stream_data),
        .a_valid   (a_stream_valid),
        .a_ready   (a_stream_ready),

        .b_data    (b_stream_data),
        .b_valid   (b_stream_valid),
        .b_ready   (b_stream_ready),

        .fork_fire (fork_fire)
    );


    // ========================================================
    // Network A GMII adapter
    // ========================================================

    gmii_tx_adapter_60 u_gmii_a (
        .clk        (clk),
        .rst        (~rst_n),

        .s_data     (a_stream_data),
        .s_valid    (a_stream_valid),
        .s_ready    (a_stream_ready),

        .gmii_txd   (gmii_a_txd),
        .gmii_tx_en (gmii_a_tx_en),
        .gmii_tx_er (gmii_a_tx_er),

        .frame_done (gmii_a_frame_done),
        .underrun   (gmii_a_underrun)
    );


    // ========================================================
    // Network B GMII adapter
    // ========================================================

    gmii_tx_adapter_60 u_gmii_b (
        .clk        (clk),
        .rst        (~rst_n),

        .s_data     (b_stream_data),
        .s_valid    (b_stream_valid),
        .s_ready    (b_stream_ready),

        .gmii_txd   (gmii_b_txd),
        .gmii_tx_en (gmii_b_tx_en),
        .gmii_tx_er (gmii_b_tx_er),

        .frame_done (gmii_b_frame_done),
        .underrun   (gmii_b_underrun)
    );


    // ========================================================
    // Debug
    // ========================================================

    assign fork_fire_dbg =
        fork_fire;


    assign a_stream_data_dbg =
        a_stream_data;

    assign a_stream_valid_dbg =
        a_stream_valid;

    assign a_stream_ready_dbg =
        a_stream_ready;


    assign b_stream_data_dbg =
        b_stream_data;

    assign b_stream_valid_dbg =
        b_stream_valid;

    assign b_stream_ready_dbg =
        b_stream_ready;


    // Normal synchronized redundant operation should make
    // both physical adapters complete together.
    assign redundant_frame_done_dbg =
        gmii_a_frame_done &&
        gmii_b_frame_done;


endmodule
