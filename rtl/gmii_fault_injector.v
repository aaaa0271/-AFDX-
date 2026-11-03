`timescale 1ns / 1ps

module gmii_fault_injector (
    input  wire        clk,
    input  wire        rst_n,

    // ========================================================
    // Raw GMII
    // ========================================================

    input  wire [7:0]  in_txd,
    input  wire        in_tx_en,
    input  wire        in_tx_er,

    input  wire        in_frame_done,
    input  wire        in_underrun,

    // ========================================================
    // Master fault enable
    // ========================================================

    input  wire        fault_enable,

    // ========================================================
    // Corrupt exactly one active GMII byte
    // ========================================================

    input  wire        corrupt_byte_enable,
    input  wire [15:0] corrupt_byte_index,
    input  wire [7:0]  corrupt_xor_mask,

    // ========================================================
    // Drop tx_en for exactly one active GMII byte
    // ========================================================

    input  wire        drop_byte_enable,
    input  wire [15:0] drop_byte_index,

    // ========================================================
    // Assert tx_er on one active byte
    // ========================================================

    input  wire        tx_error_byte_enable,
    input  wire [15:0] tx_error_byte_index,

    // ========================================================
    // Suppress physical frame_done
    // ========================================================

    input  wire        drop_frame_done_enable,

    // ========================================================
    // Simulate permanent external link loss
    //
    // This is intentionally AFTER the real TX adapter.
    // Internal logical TX may continue, but the observed
    // physical link becomes silent.
    // ========================================================

    input  wire        mute_link,

    // ========================================================
    // Faulted GMII
    // ========================================================

    output wire [7:0]  out_txd,
    output wire        out_tx_en,
    output wire        out_tx_er,

    output wire        out_frame_done,
    output wire        out_underrun,

    // ========================================================
    // Debug
    // ========================================================

    output wire [15:0] active_byte_index_dbg,
    output wire        fault_applied_dbg
);


    reg [15:0] active_byte_index;


    wire corrupt_now;
    wire drop_byte_now;
    wire tx_error_now;
    wire drop_done_now;


    // ========================================================
    // Active GMII byte index
    //
    // First gmii_tx_en cycle has index 0.
    // ========================================================

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            active_byte_index <= 16'd0;

        end

        else begin

            if (!in_tx_en)
                active_byte_index <= 16'd0;
            else
                active_byte_index <=
                    active_byte_index + 16'd1;

        end

    end


    assign corrupt_now =
        fault_enable &&
        corrupt_byte_enable &&
        in_tx_en &&
        (active_byte_index ==
         corrupt_byte_index);


    assign drop_byte_now =
        fault_enable &&
        drop_byte_enable &&
        in_tx_en &&
        (active_byte_index ==
         drop_byte_index);


    assign tx_error_now =
        fault_enable &&
        tx_error_byte_enable &&
        in_tx_en &&
        (active_byte_index ==
         tx_error_byte_index);


    assign drop_done_now =
        fault_enable &&
        drop_frame_done_enable &&
        in_frame_done;


    // ========================================================
    // Fault transformation
    // ========================================================

    assign out_txd =
        corrupt_now
        ? (in_txd ^ corrupt_xor_mask)
        : in_txd;


    assign out_tx_en =
        mute_link
        ? 1'b0
        :
        (
            drop_byte_now
            ? 1'b0
            : in_tx_en
        );


    assign out_tx_er =
        mute_link
        ? 1'b0
        :
        (
            in_tx_er ||
            tx_error_now
        );


    assign out_frame_done =
        mute_link
        ? 1'b0
        :
        (
            drop_done_now
            ? 1'b0
            : in_frame_done
        );


    assign out_underrun =
        mute_link
        ? 1'b0
        : in_underrun;


    assign active_byte_index_dbg =
        active_byte_index;


    assign fault_applied_dbg =
        corrupt_now    ||
        drop_byte_now  ||
        tx_error_now   ||
        drop_done_now  ||
        (
            mute_link &&
            (in_tx_en ||
             in_frame_done)
        );


endmodule
