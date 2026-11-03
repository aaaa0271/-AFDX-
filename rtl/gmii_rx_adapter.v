module gmii_rx_adapter #(
    parameter integer MAX_RAW_BYTES = 1518
)(
    input  wire        clk,
    input  wire        rst,

    // ========================================================
    // Raw GMII receive interface
    // ========================================================

    input  wire [7:0]  gmii_rxd,
    input  wire        gmii_rx_dv,
    input  wire        gmii_rx_er,

    // ========================================================
    // Validated Ethernet frame body output
    //
    // Output range:
    // Destination MAC through final byte before FCS.
    //
    // FCS is checked and removed.
    // Preamble / SFD are checked and removed.
    // ========================================================

    output wire [7:0]  m_data,
    output wire        m_valid,
    input  wire        m_ready,

    output wire        m_sof,
    output wire        m_eof,

    output wire [10:0] m_frame_length,

    // ========================================================
    // Status pulses
    // ========================================================

    output reg         good_frame,
    output reg         output_frame_done,

    output reg         crc_error,
    output reg         format_error,
    output reg         length_error,
    output reg         rx_error,
    output reg         overflow_error,
    input wire [63:0] gmii_timestamp,
    output wire [63:0] m_timestamp
);


// ============================================================
// State definitions
// ============================================================

localparam [2:0]
    ST_IDLE     = 3'd0,
    ST_PREAMBLE = 3'd1,
    ST_SFD      = 3'd2,
    ST_DATA     = 3'd3,
    ST_DROP     = 3'd4;

reg [2:0] state;


// ============================================================
// Two receive buffers
//
// Each buffer stores DA ... FCS.
//
// Maximum Ethernet frame length:
// 1518 bytes.
//
// After FCS verification only DA ... byte-before-FCS
// is replayed downstream.
// ============================================================

reg [7:0] frame_mem0 [0:MAX_RAW_BYTES-1];
reg [7:0] frame_mem1 [0:MAX_RAW_BYTES-1];

reg       full0;
reg       full1;

reg       next_capture_sel;
reg       capture_sel;

reg       next_output_sel;


// Body lengths exclude 4-byte FCS.

reg [10:0] frame_len0;
reg [10:0] frame_len1;
reg [63:0] input_timestamp,frame_timestamp0,frame_timestamp1;


// ============================================================
// Receive counters
// ============================================================

reg [2:0]  pre_count;
reg [10:0] rx_count;


// ============================================================
// Ethernet CRC32
//
// Polynomial:
// 0xEDB88320
//
// Initial:
// 0xFFFFFFFF
//
// Final:
// bitwise inversion
//
// Ethernet FCS transmitted least-significant byte first.
// ============================================================

reg [31:0] crc_reg;


// Last four bytes are held back from CRC calculation.
//
// At end of frame:
//
// fcs_d0 = first FCS byte
// fcs_d1 = second FCS byte
// fcs_d2 = third FCS byte
// fcs_d3 = fourth FCS byte
//
// Received numerical CRC:
//
// {fcs_d3, fcs_d2, fcs_d1, fcs_d0}
// ============================================================

reg [7:0] fcs_d0;
reg [7:0] fcs_d1;
reg [7:0] fcs_d2;
reg [7:0] fcs_d3;


// ============================================================
// CRC function
// ============================================================

function [31:0] crc32_byte;

    input [31:0] crc_in;
    input [7:0]  data_in;

    reg [31:0] crc_tmp;

    integer i;

    begin

        crc_tmp = crc_in ^ {24'd0, data_in};

        for (i = 0; i < 8; i = i + 1) begin

            if (crc_tmp[0])
                crc_tmp =
                    (crc_tmp >> 1) ^ 32'hEDB88320;
            else
                crc_tmp =
                    crc_tmp >> 1;

        end

        crc32_byte = crc_tmp;

    end

endfunction


// ============================================================
// Output replay side
// ============================================================

reg        output_active;
reg        output_sel;
assign m_timestamp=output_sel?frame_timestamp1:frame_timestamp0;

reg [10:0] output_index;
reg [10:0] output_length;


assign m_valid = output_active;

assign m_data =
    output_sel
    ? frame_mem1[output_index]
    : frame_mem0[output_index];


assign m_sof =
    output_active &&
    (output_index == 11'd0);


assign m_eof =
    output_active &&
    (output_index == output_length - 11'd1);


assign m_frame_length =
    output_length;


// ============================================================
// Main sequential logic
// ============================================================

always @(posedge clk) begin

    if (rst) begin

        state <= ST_IDLE;
        input_timestamp<=0;frame_timestamp0<=0;frame_timestamp1<=0;

        pre_count <= 3'd0;
        rx_count  <= 11'd0;

        crc_reg <= 32'hFFFFFFFF;

        fcs_d0 <= 8'd0;
        fcs_d1 <= 8'd0;
        fcs_d2 <= 8'd0;
        fcs_d3 <= 8'd0;

        full0 <= 1'b0;
        full1 <= 1'b0;

        next_capture_sel <= 1'b0;
        capture_sel      <= 1'b0;

        next_output_sel <= 1'b0;

        frame_len0 <= 11'd0;
        frame_len1 <= 11'd0;

        output_active <= 1'b0;
        output_sel    <= 1'b0;

        output_index  <= 11'd0;
        output_length <= 11'd0;

        good_frame       <= 1'b0;
        output_frame_done <= 1'b0;

        crc_error      <= 1'b0;
        format_error   <= 1'b0;
        length_error   <= 1'b0;
        rx_error       <= 1'b0;
        overflow_error <= 1'b0;

    end
    else begin

        // ====================================================
        // Status signals are one-clock pulses.
        // ====================================================

        good_frame        <= 1'b0;
        output_frame_done <= 1'b0;

        crc_error      <= 1'b0;
        format_error   <= 1'b0;
        length_error   <= 1'b0;
        rx_error       <= 1'b0;
        overflow_error <= 1'b0;


        // ====================================================
        // Output replay engine
        // ====================================================

        if (!output_active) begin

            if (
                (next_output_sel == 1'b0) &&
                full0
            ) begin

                output_active <= 1'b1;

                output_sel    <= 1'b0;
                output_index  <= 11'd0;
                output_length <= frame_len0;

            end
            else if (
                (next_output_sel == 1'b1) &&
                full1
            ) begin

                output_active <= 1'b1;

                output_sel    <= 1'b1;
                output_index  <= 11'd0;
                output_length <= frame_len1;

            end

        end
        else begin

            if (m_ready) begin

                if (
                    output_index
                    ==
                    output_length - 11'd1
                ) begin

                    output_active <= 1'b0;

                    output_frame_done <= 1'b1;

                    if (output_sel == 1'b0)
                        full0 <= 1'b0;
                    else
                        full1 <= 1'b0;

                    next_output_sel <=
                        ~next_output_sel;

                end
                else begin

                    output_index <=
                        output_index + 11'd1;

                end

            end

        end


        // ====================================================
        // GMII receive state machine
        // ====================================================

        case (state)


            // =================================================
            // IDLE
            //
            // Wait for first 0x55 preamble byte.
            // =================================================

            ST_IDLE: begin

                pre_count <= 3'd0;

                if (gmii_rx_dv) begin
                    input_timestamp<=gmii_timestamp;

                    if (gmii_rx_er) begin

                        rx_error <= 1'b1;

                        state <= ST_DROP;

                    end
                    else if (gmii_rxd == 8'h55) begin

                        pre_count <= 3'd1;

                        state <= ST_PREAMBLE;

                    end
                    else begin

                        format_error <= 1'b1;

                        state <= ST_DROP;

                    end

                end

            end


            // =================================================
            // PREAMBLE
            //
            // Exactly seven 0x55 bytes required.
            // =================================================

            ST_PREAMBLE: begin

                if (!gmii_rx_dv) begin

                    format_error <= 1'b1;

                    state <= ST_IDLE;

                end
                else if (gmii_rx_er) begin

                    rx_error <= 1'b1;

                    state <= ST_DROP;

                end
                else if (gmii_rxd != 8'h55) begin

                    format_error <= 1'b1;

                    state <= ST_DROP;

                end
                else begin

                    // First 0x55 was already counted
                    // in ST_IDLE.
                    //
                    // pre_count == 6 means current byte
                    // is the seventh 0x55.

                    if (pre_count == 3'd6) begin

                        state <= ST_SFD;

                    end
                    else begin

                        pre_count <=
                            pre_count + 3'd1;

                    end

                end

            end


            // =================================================
            // SFD
            // =================================================

            ST_SFD: begin

                if (!gmii_rx_dv) begin

                    format_error <= 1'b1;

                    state <= ST_IDLE;

                end
                else if (gmii_rx_er) begin

                    rx_error <= 1'b1;

                    state <= ST_DROP;

                end
                else if (gmii_rxd != 8'hD5) begin

                    format_error <= 1'b1;

                    state <= ST_DROP;

                end
                else begin

                    // -----------------------------------------
                    // Select next ping-pong buffer.
                    // -----------------------------------------

                    if (
                        (next_capture_sel == 1'b0) &&
                        !full0
                    ) begin

                        capture_sel <= 1'b0;
                        frame_timestamp0<=input_timestamp;

                        rx_count <= 11'd0;

                        crc_reg <= 32'hFFFFFFFF;

                        fcs_d0 <= 8'd0;
                        fcs_d1 <= 8'd0;
                        fcs_d2 <= 8'd0;
                        fcs_d3 <= 8'd0;

                        state <= ST_DATA;

                    end
                    else if (
                        (next_capture_sel == 1'b1) &&
                        !full1
                    ) begin

                        capture_sel <= 1'b1;
                        frame_timestamp1<=input_timestamp;

                        rx_count <= 11'd0;

                        crc_reg <= 32'hFFFFFFFF;

                        fcs_d0 <= 8'd0;
                        fcs_d1 <= 8'd0;
                        fcs_d2 <= 8'd0;
                        fcs_d3 <= 8'd0;

                        state <= ST_DATA;

                    end
                    else begin

                        // Raw GMII cannot be backpressured.
                        // No free buffer means current frame
                        // must be dropped.

                        overflow_error <= 1'b1;

                        state <= ST_DROP;

                    end

                end

            end


            // =================================================
            // DATA
            //
            // Receive entire Ethernet frame including FCS.
            //
            // Last 4 bytes are delayed so CRC is calculated
            // over DA ... last byte before FCS only.
            // =================================================

            ST_DATA: begin

                if (gmii_rx_er) begin

                    rx_error <= 1'b1;

                    state <= ST_DROP;

                end
                else if (gmii_rx_dv) begin

                    // -----------------------------------------
                    // Ethernet maximum frame size reached.
                    //
                    // rx_count == MAX_RAW_BYTES means
                    // 1518 bytes have already been stored.
                    // Another byte is invalid.
                    // -----------------------------------------

                    if (rx_count >= MAX_RAW_BYTES) begin

                        length_error <= 1'b1;

                        state <= ST_DROP;

                    end
                    else begin

                        // -------------------------------------
                        // Store received byte.
                        // -------------------------------------

                        if (capture_sel == 1'b0)
                            frame_mem0[rx_count] <=
                                gmii_rxd;
                        else
                            frame_mem1[rx_count] <=
                                gmii_rxd;


                        // -------------------------------------
                        // Four-byte FCS delay pipeline.
                        // -------------------------------------

                        if (rx_count == 11'd0) begin

                            fcs_d0 <= gmii_rxd;

                        end
                        else if (rx_count == 11'd1) begin

                            fcs_d1 <= gmii_rxd;

                        end
                        else if (rx_count == 11'd2) begin

                            fcs_d2 <= gmii_rxd;

                        end
                        else if (rx_count == 11'd3) begin

                            fcs_d3 <= gmii_rxd;

                        end
                        else begin

                            // Oldest delayed byte is now
                            // guaranteed not to be FCS.

                            crc_reg <=
                                crc32_byte(
                                    crc_reg,
                                    fcs_d0
                                );

                            fcs_d0 <= fcs_d1;
                            fcs_d1 <= fcs_d2;
                            fcs_d2 <= fcs_d3;
                            fcs_d3 <= gmii_rxd;

                        end


                        rx_count <=
                            rx_count + 11'd1;

                    end

                end
                else begin

                    // =========================================
                    // gmii_rx_dv dropped:
                    // entire Ethernet frame received.
                    // =========================================

                    // Ethernet frame DA...FCS:
                    // minimum 64 bytes
                    // maximum 1518 bytes.

                    if (
                        (rx_count < 11'd64) ||
                        (rx_count > MAX_RAW_BYTES)
                    ) begin

                        length_error <= 1'b1;

                    end
                    else if (
                        {fcs_d3,
                         fcs_d2,
                         fcs_d1,
                         fcs_d0}
                        !=
                        ~crc_reg
                    ) begin

                        crc_error <= 1'b1;

                    end
                    else begin

                        // -------------------------------------
                        // Valid frame.
                        //
                        // Remove 4-byte FCS from downstream
                        // length.
                        // -------------------------------------

                        if (capture_sel == 1'b0) begin

                            frame_len0 <=
                                rx_count - 11'd4;

                            full0 <= 1'b1;

                        end
                        else begin

                            frame_len1 <=
                                rx_count - 11'd4;

                            full1 <= 1'b1;

                        end


                        next_capture_sel <=
                            ~next_capture_sel;

                        good_frame <= 1'b1;

                    end


                    state <= ST_IDLE;

                end

            end


            // =================================================
            // DROP
            //
            // Ignore everything until gmii_rx_dv is released.
            // =================================================

            ST_DROP: begin

                if (!gmii_rx_dv)
                    state <= ST_IDLE;

            end


            default: begin

                state <= ST_IDLE;

            end

        endcase

    end

end


endmodule
