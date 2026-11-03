`timescale 1ns / 1ps
// LEGACY (M4 TX path): not instantiated by AFDX_competition_top or the
// competition AFDX_top; retained only for legacy ModelSim regression
// coverage. Do not use for new work.

module m4_payload_adapter (
    input  wire [7:0]  descriptor_data,
    input  wire [15:0] descriptor_len,

    output wire [31:0] payload_data,
    output wire        length_ok
);


    // ========================================================
    // Existing M2 Frame Builder supports exactly 4 payload
    // bytes.
    //
    // M4-E1 currently stores one 8-bit descriptor data field.
    // For M4-E2 integration this byte is zero-extended.
    //
    // Example:
    //
    // descriptor_data = A5
    //
    // payload_data =
    //
    //     00 00 00 A5
    //
    // ========================================================

    assign payload_data =
        {24'h000000, descriptor_data};


    assign length_ok =
        (descriptor_len == 16'd4);


endmodule
