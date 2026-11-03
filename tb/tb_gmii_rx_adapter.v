`timescale 1ns / 1ps

module tb_gmii_rx_adapter;


// ============================================================
// Clock / reset
// ============================================================

reg clk;
reg rst;

initial begin

    clk = 1'b0;

    forever #5
        clk = ~clk;

end


// ============================================================
// GMII input
// ============================================================

reg [7:0] gmii_rxd;
reg       gmii_rx_dv;
reg       gmii_rx_er;


// ============================================================
// Validated output
// ============================================================

wire [7:0]  m_data;
wire        m_valid;

reg         m_ready;

wire        m_sof;
wire        m_eof;

wire [10:0] m_frame_length;


// ============================================================
// Status
// ============================================================

wire good_frame;
wire output_frame_done;

wire crc_error;
wire format_error;
wire length_error;
wire rx_error;
wire overflow_error;


// ============================================================
// DUT
// ============================================================

gmii_rx_adapter dut (

    .clk               (clk),
    .rst               (rst),

    .gmii_rxd          (gmii_rxd),
    .gmii_rx_dv        (gmii_rx_dv),
    .gmii_rx_er        (gmii_rx_er),

    .m_data            (m_data),
    .m_valid           (m_valid),
    .m_ready           (m_ready),

    .m_sof             (m_sof),
    .m_eof             (m_eof),

    .m_frame_length    (m_frame_length),

    .good_frame        (good_frame),
    .output_frame_done (output_frame_done),

    .crc_error         (crc_error),
    .format_error      (format_error),
    .length_error      (length_error),
    .rx_error          (rx_error),
    .overflow_error    (overflow_error)
);


// ============================================================
// Counters
// ============================================================

integer good_count;
integer crc_error_count;
integer format_error_count;
integer rx_error_count;

integer output_byte_count;
integer output_frame_count;

integer error_count;


// ============================================================
// Body pattern
//
// body[index] = index
//
// 60-byte body:
//
// 00 01 02 ... 3B
//
// Independent expected CRC:
// B0EC7FEE
//
// FCS on GMII:
// EE 7F EC B0
// ============================================================

function [7:0] body_byte;

    input integer index;

    begin

        body_byte = index[7:0];

    end

endfunction


// ============================================================
// Status monitor
// ============================================================

always @(posedge clk) begin

    if (rst) begin

        good_count         = 0;
        crc_error_count    = 0;
        format_error_count = 0;
        rx_error_count     = 0;

    end
    else begin

        if (good_frame)
            good_count = good_count + 1;

        if (crc_error)
            crc_error_count =
                crc_error_count + 1;

        if (format_error)
            format_error_count =
                format_error_count + 1;

        if (rx_error)
            rx_error_count =
                rx_error_count + 1;

    end

end


// ============================================================
// Output scoreboard
// ============================================================

always @(posedge clk) begin

    if (rst) begin

        output_byte_count  = 0;
        output_frame_count = 0;

    end
    else begin

        if (m_valid && m_ready) begin

            // ------------------------------------------------
            // Data content
            // ------------------------------------------------

            if (
                m_data
                !==
                body_byte(output_byte_count)
            ) begin

                $display(
                    "ERROR: OUTPUT BYTE %0d = %02X, EXPECTED %02X",
                    output_byte_count,
                    m_data,
                    body_byte(output_byte_count)
                );

                error_count = error_count + 1;

            end


            // ------------------------------------------------
            // SOF
            // ------------------------------------------------

            if (
                (output_byte_count == 0) &&
                !m_sof
            ) begin

                $display(
                    "ERROR: SOF MISSING"
                );

                error_count = error_count + 1;

            end


            if (
                (output_byte_count != 0) &&
                m_sof
            ) begin

                $display(
                    "ERROR: UNEXPECTED SOF"
                );

                error_count = error_count + 1;

            end


            // ------------------------------------------------
            // EOF
            // ------------------------------------------------

            if (
                (output_byte_count == 59) &&
                !m_eof
            ) begin

                $display(
                    "ERROR: EOF MISSING"
                );

                error_count = error_count + 1;

            end


            if (
                (output_byte_count != 59) &&
                m_eof
            ) begin

                $display(
                    "ERROR: UNEXPECTED EOF"
                );

                error_count = error_count + 1;

            end


            // ------------------------------------------------
            // Frame length
            // ------------------------------------------------

            if (
                m_frame_length
                !=
                11'd60
            ) begin

                $display(
                    "ERROR: FRAME LENGTH = %0d, EXPECTED 60",
                    m_frame_length
                );

                error_count = error_count + 1;

            end


            // ------------------------------------------------
            // Advance scoreboard
            // ------------------------------------------------

            if (output_byte_count == 59) begin

                output_byte_count = 0;

                output_frame_count =
                    output_frame_count + 1;

            end
            else begin

                output_byte_count =
                    output_byte_count + 1;

            end

        end

    end

end


// ============================================================
// Drive one GMII byte
// ============================================================

task drive_byte;

    input [7:0] data;
    input       error;

    begin

        @(negedge clk);

        gmii_rxd   = data;
        gmii_rx_dv = 1'b1;
        gmii_rx_er = error;

    end

endtask


// ============================================================
// End current frame
// ============================================================

task end_frame;

    begin

        @(negedge clk);

        gmii_rxd   = 8'd0;
        gmii_rx_dv = 1'b0;
        gmii_rx_er = 1'b0;

    end

endtask


// ============================================================
// Send valid minimum Ethernet frame
//
// 7 x 55
// D5
// 60 body bytes
// EE 7F EC B0
// ============================================================

task send_valid_frame;

    integer i;

    begin

        for (i = 0; i < 7; i = i + 1)
            drive_byte(
                8'h55,
                1'b0
            );

        drive_byte(
            8'hD5,
            1'b0
        );

        for (i = 0; i < 60; i = i + 1)
            drive_byte(
                body_byte(i),
                1'b0
            );

        // CRC32 B0EC7FEE
        // Ethernet byte order:
        // EE 7F EC B0

        drive_byte(8'hEE, 1'b0);
        drive_byte(8'h7F, 1'b0);
        drive_byte(8'hEC, 1'b0);
        drive_byte(8'hB0, 1'b0);

        end_frame;

    end

endtask


// ============================================================
// Send frame with bad FCS
// ============================================================

task send_bad_fcs_frame;

    integer i;

    begin

        for (i = 0; i < 7; i = i + 1)
            drive_byte(
                8'h55,
                1'b0
            );

        drive_byte(
            8'hD5,
            1'b0
        );

        for (i = 0; i < 60; i = i + 1)
            drive_byte(
                body_byte(i),
                1'b0
            );

        // Corrupt first FCS byte.

        drive_byte(8'hEF, 1'b0);
        drive_byte(8'h7F, 1'b0);
        drive_byte(8'hEC, 1'b0);
        drive_byte(8'hB0, 1'b0);

        end_frame;

    end

endtask


// ============================================================
// Main test
// ============================================================

initial begin

    gmii_rxd   = 8'd0;
    gmii_rx_dv = 1'b0;
    gmii_rx_er = 1'b0;

    m_ready = 1'b1;

    rst = 1'b1;

    error_count = 0;


    repeat (10)
        @(posedge clk);

    @(negedge clk);

    rst = 1'b0;


    // ========================================================
    // TEST 1
    // Valid minimum Ethernet frame
    // ========================================================

    send_valid_frame;

    wait (good_count == 1);

    wait (output_frame_count == 1);

    $display(
        "TEST 1 VALID FRAME PASS"
    );


    repeat (20)
        @(posedge clk);


    // ========================================================
    // TEST 2
    // Bad FCS
    // ========================================================

    send_bad_fcs_frame;

    wait (crc_error_count == 1);

    repeat (20)
        @(posedge clk);


    if (output_frame_count != 1) begin

        $display(
            "ERROR: BAD FCS FRAME WAS OUTPUT"
        );

        error_count =
            error_count + 1;

    end
    else begin

        $display(
            "TEST 2 BAD FCS DROP PASS"
        );

    end


    // ========================================================
    // TEST 3
    // Bad preamble
    // ========================================================

    drive_byte(8'h55, 1'b0);
    drive_byte(8'h55, 1'b0);
    drive_byte(8'h54, 1'b0);

    end_frame;

    wait (format_error_count == 1);

    $display(
        "TEST 3 BAD PREAMBLE DROP PASS"
    );


    repeat (20)
        @(posedge clk);


    // ========================================================
    // TEST 4
    // Bad SFD
    // ========================================================

    begin : TEST_BAD_SFD

        integer j;

        for (
            j = 0;
            j < 7;
            j = j + 1
        )
            drive_byte(
                8'h55,
                1'b0
            );

        drive_byte(
            8'hD4,
            1'b0
        );

        end_frame;

    end


    wait (format_error_count == 2);

    $display(
        "TEST 4 BAD SFD DROP PASS"
    );


    repeat (20)
        @(posedge clk);


    // ========================================================
    // TEST 5
    // GMII RX error
    // ========================================================

    begin : TEST_RX_ERROR

        integer k;

        for (
            k = 0;
            k < 7;
            k = k + 1
        )
            drive_byte(
                8'h55,
                1'b0
            );

        drive_byte(
            8'hD5,
            1'b0
        );

        for (
            k = 0;
            k < 10;
            k = k + 1
        )
            drive_byte(
                body_byte(k),
                1'b0
            );

        drive_byte(
            8'hAA,
            1'b1
        );

        end_frame;

    end


    wait (rx_error_count == 1);

    $display(
        "TEST 5 GMII RX ERROR DROP PASS"
    );


    repeat (30)
        @(posedge clk);


    // ========================================================
    // FINAL RESULT
    // ========================================================

    if (error_count == 0) begin

        $display("");
        $display("==============================================");
        $display("M3-A GMII RX BASIC TEST PASS");
        $display("VALID FRAME VERIFIED");
        $display("60-BYTE BODY VERIFIED");
        $display("SOF / EOF VERIFIED");
        $display("FCS CHECK VERIFIED");
        $display("BAD FCS DROP VERIFIED");
        $display("BAD PREAMBLE DROP VERIFIED");
        $display("BAD SFD DROP VERIFIED");
        $display("GMII RX ERROR DROP VERIFIED");
        $display("INVALID FRAME NON-DELIVERY VERIFIED");
        $display("==============================================");
        $display("");

    end
    else begin

        $fatal(
            1,
            "M3-A BASIC TEST FAIL: %0d ERRORS",
            error_count
        );

    end


    $finish;

end


// ============================================================
// Timeout
// ============================================================

initial begin

    #200000;

    $fatal(
        1,
        "M3-A FAIL: SIMULATION TIMEOUT"
    );

end


endmodule
