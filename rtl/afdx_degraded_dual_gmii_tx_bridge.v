`timescale 1ns / 1ps
// LEGACY (M4 TX path): not instantiated by AFDX_competition_top or the
// competition AFDX_top; retained only for legacy ModelSim regression
// coverage. Do not use for new work.

module afdx_degraded_dual_gmii_tx_bridge (
    input  wire       clk,
    input  wire       rst_n,

    input  wire       network_a_enable,
    input  wire       network_b_enable,

    // Logical body stream
    input  wire [7:0] s_data,
    input  wire       s_valid,
    output wire       s_ready,

    // Network A
    output wire [7:0] gmii_a_txd,
    output wire       gmii_a_tx_en,
    output wire       gmii_a_tx_er,

    output wire       gmii_a_frame_done,
    output wire       gmii_a_underrun,

    // Network B
    output wire [7:0] gmii_b_txd,
    output wire       gmii_b_tx_en,
    output wire       gmii_b_tx_er,

    output wire       gmii_b_frame_done,
    output wire       gmii_b_underrun,

    // Debug
    output wire       fork_fire_dbg,
    output wire       any_network_enabled_dbg,
    output wire       degraded_mode_dbg
);


    wire [7:0] a_stream_data;
    wire       a_stream_valid;
    wire       a_stream_ready;

    wire [7:0] b_stream_data;
    wire       b_stream_valid;
    wire       b_stream_ready;


    wire fork_fire;
    wire any_network_enabled;
    wire degraded_mode;


    wire [7:0] gmii_a_txd_int;
    wire       gmii_a_tx_en_int;
    wire       gmii_a_tx_er_int;
    wire       gmii_a_frame_done_int;
    wire       gmii_a_underrun_int;


    wire [7:0] gmii_b_txd_int;
    wire       gmii_b_tx_en_int;
    wire       gmii_b_tx_er_int;
    wire       gmii_b_frame_done_int;
    wire       gmii_b_underrun_int;


    // ========================================================
    // Degraded-capable multicast fork
    // ========================================================

    afdx_redundant_tx_fork_degraded u_fork (
        .clk                 (clk),
        .rst_n               (rst_n),

        .network_a_enable    (network_a_enable),
        .network_b_enable    (network_b_enable),

        .s_data              (s_data),
        .s_valid             (s_valid),
        .s_ready             (s_ready),

        .a_data              (a_stream_data),
        .a_valid             (a_stream_valid),
        .a_ready             (a_stream_ready),

        .b_data              (b_stream_data),
        .b_valid             (b_stream_valid),
        .b_ready             (b_stream_ready),

        .fork_fire           (fork_fire),

        .any_network_enabled (any_network_enabled),

        .degraded_mode       (degraded_mode)
    );


    // ========================================================
    // Network A
    //
    // Disabled adapter is held in reset.
    // ========================================================

    gmii_tx_adapter_60 u_gmii_a (
        .clk        (clk),

        .rst        (
            (~rst_n) ||
            (!network_a_enable)
        ),

        .s_data     (a_stream_data),
        .s_valid    (a_stream_valid),
        .s_ready    (a_stream_ready),

        .gmii_txd   (gmii_a_txd_int),
        .gmii_tx_en (gmii_a_tx_en_int),
        .gmii_tx_er (gmii_a_tx_er_int),

        .frame_done (gmii_a_frame_done_int),
        .underrun   (gmii_a_underrun_int)
    );


    // ========================================================
    // Network B
    // ========================================================

    gmii_tx_adapter_60 u_gmii_b (
        .clk        (clk),

        .rst        (
            (~rst_n) ||
            (!network_b_enable)
        ),

        .s_data     (b_stream_data),
        .s_valid    (b_stream_valid),
        .s_ready    (b_stream_ready),

        .gmii_txd   (gmii_b_txd_int),
        .gmii_tx_en (gmii_b_tx_en_int),
        .gmii_tx_er (gmii_b_tx_er_int),

        .frame_done (gmii_b_frame_done_int),
        .underrun   (gmii_b_underrun_int)
    );


    // ========================================================
    // Disabled physical output is forced quiescent.
    // ========================================================

    assign gmii_a_txd =
        network_a_enable
        ? gmii_a_txd_int
        : 8'h00;

    assign gmii_a_tx_en =
        network_a_enable
        ? gmii_a_tx_en_int
        : 1'b0;

    assign gmii_a_tx_er =
        network_a_enable
        ? gmii_a_tx_er_int
        : 1'b0;

    assign gmii_a_frame_done =
        network_a_enable
        ? gmii_a_frame_done_int
        : 1'b0;

    assign gmii_a_underrun =
        network_a_enable
        ? gmii_a_underrun_int
        : 1'b0;


    assign gmii_b_txd =
        network_b_enable
        ? gmii_b_txd_int
        : 8'h00;

    assign gmii_b_tx_en =
        network_b_enable
        ? gmii_b_tx_en_int
        : 1'b0;

    assign gmii_b_tx_er =
        network_b_enable
        ? gmii_b_tx_er_int
        : 1'b0;

    assign gmii_b_frame_done =
        network_b_enable
        ? gmii_b_frame_done_int
        : 1'b0;

    assign gmii_b_underrun =
        network_b_enable
        ? gmii_b_underrun_int
        : 1'b0;


    assign fork_fire_dbg =
        fork_fire;


    assign any_network_enabled_dbg =
        any_network_enabled;


    assign degraded_mode_dbg =
        degraded_mode;


endmodule
