`timescale 1ns / 1ps
// LEGACY (M4 TX path): not instantiated by AFDX_competition_top or the
// competition AFDX_top; retained only for legacy ModelSim regression
// coverage. Do not use for new work.

module m4_vl_net_mapper #(

    parameter [47:0] SRC_MAC =
        48'h020000000001,

    parameter [31:0] SRC_IP =
        32'h0A000001,

    parameter [15:0] SRC_PORT =
        16'h2710,

    parameter [39:0] DST_MAC_PREFIX =
        40'h0200000000,

    parameter [23:0] DST_IP_PREFIX =
        24'h0A0000,

    parameter [15:0] DST_PORT_BASE =
        16'h4E20

)(
    input  wire [7:0] destination_code,

    output wire [47:0] cfg_dst_mac,
    output wire [47:0] cfg_src_mac,

    output wire [31:0] cfg_src_ip,
    output wire [31:0] cfg_dst_ip,

    output wire [15:0] cfg_src_port,
    output wire [15:0] cfg_dst_port
);


    // ========================================================
    // Destination mapping
    //
    // destination_code = N:
    //
    // MAC:
    //   02:00:00:00:00:N
    //
    // IP:
    //   10.0.0.N
    //
    // UDP destination:
    //   20000 + N
    // ========================================================

    assign cfg_dst_mac =
        {DST_MAC_PREFIX, destination_code};

    assign cfg_src_mac =
        SRC_MAC;


    assign cfg_src_ip =
        SRC_IP;

    assign cfg_dst_ip =
        {DST_IP_PREFIX, destination_code};


    assign cfg_src_port =
        SRC_PORT;

    assign cfg_dst_port =
        DST_PORT_BASE +
        {8'd0, destination_code};


endmodule
