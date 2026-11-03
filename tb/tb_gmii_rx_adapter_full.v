`timescale 1ns / 1ps

module tb_gmii_rx_adapter_full;


// ============================================================
// Clock / reset
// ============================================================

reg clk;
reg rst;

initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
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
// Global counters
// ============================================================

integer good_count;
integer length_error_count;
integer overflow_error_count;
integer output_frame_count;
integer output_done_count;

integer error_count;


// ============================================================
// Expected output queue
//
// Each valid frame is described by:
//
//   expected length
//   starting byte value
//
// Pattern:
//   data[i] = seed + i
// ============================================================

integer exp_len  [0:31];
integer exp_seed [0:31];

integer exp_wr;
integer exp_rd;
integer exp_byte_index;


// ============================================================
// Pattern byte
// ============================================================

function [7:0] pattern_byte;

    input integer seed;
    input integer index;

    integer value;

    begin

        value = seed + index;

        pattern_byte = value[7:0];

    end

endfunction


// ============================================================
// Queue expected output frame
// ============================================================

task expect_frame;

    input integer body_length;
    input integer seed;

    begin

        exp_len[exp_wr]  = body_length;
        exp_seed[exp_wr] = seed;

        exp_wr = exp_wr + 1;

    end

endtask


// ============================================================
// Status monitor
// ============================================================

always @(posedge clk) begin

    if (rst) begin

        good_count          = 0;
        length_error_count  = 0;
        overflow_error_count = 0;
        output_done_count   = 0;

    end
    else begin

        if (good_frame)
            good_count = good_count + 1;

        if (length_error)
            length_error_count =
                length_error_count + 1;

        if (overflow_error)
            overflow_error_count =
                overflow_error_count + 1;

        if (output_frame_done)
            output_done_count =
                output_done_count + 1;

    end

end


// ============================================================
// Output scoreboard
// ============================================================

always @(posedge clk) begin

    if (rst) begin

        exp_rd          = 0;
        exp_byte_index  = 0;
        output_frame_count = 0;

    end
    else if (m_valid && m_ready) begin

        if (exp_rd >= exp_wr) begin

            $display(
                "ERROR: UNEXPECTED OUTPUT FRAME"
            );

            error_count =
                error_count + 1;

        end
        else begin

            // ------------------------------------------------
            // Data
            // ------------------------------------------------

            if (
                m_data !==
                pattern_byte(
                    exp_seed[exp_rd],
                    exp_byte_index
                )
            ) begin

                $display(
                    "ERROR: FRAME %0d BYTE %0d = %02X EXPECTED %02X",
                    exp_rd,
                    exp_byte_index,
                    m_data,
                    pattern_byte(
                        exp_seed[exp_rd],
                        exp_byte_index
                    )
                );

                error_count =
                    error_count + 1;

            end


            // ------------------------------------------------
            // Frame length
            // ------------------------------------------------

            if (
                m_frame_length
                !=
                exp_len[exp_rd]
            ) begin

                $display(
                    "ERROR: FRAME %0d LENGTH = %0d EXPECTED %0d",
                    exp_rd,
                    m_frame_length,
                    exp_len[exp_rd]
                );

                error_count =
                    error_count + 1;

            end


            // ------------------------------------------------
            // SOF
            // ------------------------------------------------

            if (
                (exp_byte_index == 0) &&
                !m_sof
            ) begin

                $display(
                    "ERROR: FRAME %0d SOF MISSING",
                    exp_rd
                );

                error_count =
                    error_count + 1;

            end

            if (
                (exp_byte_index != 0) &&
                m_sof
            ) begin

                $display(
                    "ERROR: FRAME %0d UNEXPECTED SOF",
                    exp_rd
                );

                error_count =
                    error_count + 1;

            end


            // ------------------------------------------------
            // EOF
            // ------------------------------------------------

            if (
                (exp_byte_index ==
                 exp_len[exp_rd] - 1) &&
                !m_eof
            ) begin

                $display(
                    "ERROR: FRAME %0d EOF MISSING",
                    exp_rd
                );

                error_count =
                    error_count + 1;

            end

            if (
                (exp_byte_index !=
                 exp_len[exp_rd] - 1) &&
                m_eof
            ) begin

                $display(
                    "ERROR: FRAME %0d UNEXPECTED EOF",
                    exp_rd
                );

                error_count =
                    error_count + 1;

            end


            // ------------------------------------------------
            // Advance
            // ------------------------------------------------

            if (
                exp_byte_index ==
                exp_len[exp_rd] - 1
            ) begin

                exp_byte_index = 0;

                exp_rd =
                    exp_rd + 1;

                output_frame_count =
                    output_frame_count + 1;

            end
            else begin

                exp_byte_index =
                    exp_byte_index + 1;

            end

        end

    end

end


// ============================================================
// Backpressure stability checker
//
// When VALID=1 and READY=0:
//
// DATA / SOF / EOF / LENGTH must remain stable.
// ============================================================

reg        hold_active;

reg [7:0]  hold_data;
reg        hold_sof;
reg        hold_eof;
reg [10:0] hold_length;


always @(posedge clk) begin

    if (rst) begin

        hold_active = 1'b0;

    end
    else begin

        if (m_valid && !m_ready) begin

            if (!hold_active) begin

                hold_active = 1'b1;

                hold_data   = m_data;
                hold_sof    = m_sof;
                hold_eof    = m_eof;
                hold_length = m_frame_length;

            end
            else begin

                if (
                    (m_data !== hold_data) ||
                    (m_sof  !== hold_sof)  ||
                    (m_eof  !== hold_eof)  ||
                    (m_frame_length !== hold_length)
                ) begin

                    $display(
                        "ERROR: OUTPUT CHANGED DURING BACKPRESSURE"
                    );

                    error_count =
                        error_count + 1;

                end

            end

        end
        else begin

            hold_active = 1'b0;

        end

    end

end


// ============================================================
// Drive one GMII byte
// ============================================================

task drive_byte;

    input [7:0] data;

    begin

        @(negedge clk);

        gmii_rxd   = data;
        gmii_rx_dv = 1'b1;
        gmii_rx_er = 1'b0;

    end

endtask


// ============================================================
// End frame + realistic IFG
// ============================================================

task end_frame;

    integer i;

    begin

        @(negedge clk);

        gmii_rxd   = 8'd0;
        gmii_rx_dv = 1'b0;
        gmii_rx_er = 1'b0;

        // 12 idle byte-times

        for (i = 0; i < 12; i = i + 1)
            @(negedge clk);

    end

endtask


// ============================================================
// Send one valid frame
//
// body_length excludes FCS.
//
// FCS bytes are supplied explicitly.
// ============================================================

task send_valid_frame;

    input integer body_length;
    input integer seed;

    input [7:0] fcs0;
    input [7:0] fcs1;
    input [7:0] fcs2;
    input [7:0] fcs3;

    integer i;

    begin

        // 7-byte preamble

        for (i = 0; i < 7; i = i + 1)
            drive_byte(8'h55);

        // SFD

        drive_byte(8'hD5);


        // Body

        for (
            i = 0;
            i < body_length;
            i = i + 1
        )
            drive_byte(
                pattern_byte(seed, i)
            );


        // FCS

        drive_byte(fcs0);
        drive_byte(fcs1);
        drive_byte(fcs2);
        drive_byte(fcs3);

        end_frame;

    end

endtask


// ============================================================
// Send oversize raw Ethernet frame
//
// 1519 bytes DA...FCS-equivalent payload.
// The DUT must drop once byte 1519 arrives.
// ============================================================

task send_oversize_frame;

    integer i;

    begin

        for (i = 0; i < 7; i = i + 1)
            drive_byte(8'h55);

        drive_byte(8'hD5);


        for (i = 0; i < 1519; i = i + 1)
            drive_byte(
                pattern_byte(0, i)
            );


        end_frame;

    end

endtask


// ============================================================
// Main regression
// ============================================================

integer base_good;
integer base_length;
integer base_overflow;
integer base_output;


initial begin

    gmii_rxd   = 8'd0;
    gmii_rx_dv = 1'b0;
    gmii_rx_er = 1'b0;

    m_ready = 1'b1;

    rst = 1'b1;

    error_count = 0;

    exp_wr = 0;


    repeat (10)
        @(posedge clk);

    @(negedge clk);
    rst = 1'b0;


    // ========================================================
    // TEST 6
    // Variable 100-byte body
    //
    // Pattern:
    // 20 21 22 ...
    //
    // Independent CRC32:
    // F2675A31
    //
    // GMII FCS:
    // 31 5A 67 F2
    // ========================================================

    base_good   = good_count;
    base_output = output_frame_count;

    expect_frame(
        100,
        32
    );

    send_valid_frame(
        100,
        32,
        8'h31,
        8'h5A,
        8'h67,
        8'hF2
    );

    wait (
        good_count
        ==
        base_good + 1
    );

    wait (
        output_frame_count
        ==
        base_output + 1
    );

    $display(
        "TEST 6 VARIABLE LENGTH 100B PASS"
    );


    // ========================================================
    // TEST 7
    // Undersize Ethernet frame
    //
    // 40 body + 4 FCS = 44 raw bytes.
    //
    // CRC32:
    // 0DA62E3C
    //
    // FCS:
    // 3C 2E A6 0D
    // ========================================================

    base_length = length_error_count;
    base_output = output_frame_count;

    send_valid_frame(
        40,
        0,
        8'h3C,
        8'h2E,
        8'hA6,
        8'h0D
    );

    wait (
        length_error_count
        ==
        base_length + 1
    );

    repeat (20)
        @(posedge clk);


    if (
        output_frame_count
        !=
        base_output
    ) begin

        $display(
            "ERROR: UNDERSIZE FRAME WAS OUTPUT"
        );

        error_count =
            error_count + 1;

    end
    else begin

        $display(
            "TEST 7 UNDERSIZE DROP PASS"
        );

    end


    // ========================================================
    // TEST 8
    // Maximum legal Ethernet frame
    //
    // Body:
    // 1514 bytes
    //
    // + FCS:
    // 4 bytes
    //
    // Raw Ethernet frame:
    // 1518 bytes
    //
    // Pattern:
    // 00 01 ... FF 00 ...
    //
    // Independent CRC32:
    // E7870705
    //
    // FCS:
    // 05 07 87 E7
    // ========================================================

    base_good   = good_count;
    base_output = output_frame_count;

    expect_frame(
        1514,
        0
    );

    send_valid_frame(
        1514,
        0,
        8'h05,
        8'h07,
        8'h87,
        8'hE7
    );

    wait (
        good_count
        ==
        base_good + 1
    );

    wait (
        output_frame_count
        ==
        base_output + 1
    );

    $display(
        "TEST 8 MAXIMUM 1518B FRAME PASS"
    );


    // ========================================================
    // TEST 9
    // Oversize frame
    // ========================================================

    base_length = length_error_count;
    base_output = output_frame_count;

    send_oversize_frame;

    wait (
        length_error_count
        ==
        base_length + 1
    );

    repeat (20)
        @(posedge clk);


    if (
        output_frame_count
        !=
        base_output
    ) begin

        $display(
            "ERROR: OVERSIZE FRAME WAS OUTPUT"
        );

        error_count =
            error_count + 1;

    end
    else begin

        $display(
            "TEST 9 OVERSIZE DROP PASS"
        );

    end


    // ========================================================
    // TEST 10
    // Ping-pong buffering + backpressure
    //
    // Hold downstream.
    //
    // Frame A:
    // seed = 60
    //
    // CRC = 7B9FA49E
    // FCS = 9E A4 9F 7B
    //
    // Frame B:
    // seed = 64
    //
    // CRC = EE00E53A
    // FCS = 3A E5 00 EE
    // ========================================================

    @(negedge clk);
    m_ready = 1'b0;

    base_good   = good_count;
    base_output = output_frame_count;


    expect_frame(
        60,
        60
    );

    expect_frame(
        60,
        64
    );


    send_valid_frame(
        60,
        60,
        8'h9E,
        8'hA4,
        8'h9F,
        8'h7B
    );


    send_valid_frame(
        60,
        64,
        8'h3A,
        8'hE5,
        8'h00,
        8'hEE
    );


    wait (
        good_count
        ==
        base_good + 2
    );


    repeat (30)
        @(posedge clk);


    if (!m_valid) begin

        $display(
            "ERROR: BUFFERED OUTPUT NOT VALID DURING BACKPRESSURE"
        );

        error_count =
            error_count + 1;

    end


    if (
        output_frame_count
        !=
        base_output
    ) begin

        $display(
            "ERROR: DATA ADVANCED WHILE READY=0"
        );

        error_count =
            error_count + 1;

    end


    @(negedge clk);
    m_ready = 1'b1;


    wait (
        output_frame_count
        ==
        base_output + 2
    );


    $display(
        "TEST 10 PING-PONG / BACKPRESSURE PASS"
    );


    repeat (20)
        @(posedge clk);


    // ========================================================
    // TEST 11
    // Both buffers full -> third frame must be dropped.
    // ========================================================

    @(negedge clk);
    m_ready = 1'b0;


    base_good     = good_count;
    base_overflow = overflow_error_count;
    base_output   = output_frame_count;


    // Buffer 0

    expect_frame(
        60,
        0
    );

    send_valid_frame(
        60,
        0,
        8'hEE,
        8'h7F,
        8'hEC,
        8'hB0
    );


    // Buffer 1

    expect_frame(
        100,
        32
    );

    send_valid_frame(
        100,
        32,
        8'h31,
        8'h5A,
        8'h67,
        8'hF2
    );


    // Third frame should hit no-free-buffer condition.

    send_valid_frame(
        60,
        60,
        8'h9E,
        8'hA4,
        8'h9F,
        8'h7B
    );


    wait (
        good_count
        ==
        base_good + 2
    );


    wait (
        overflow_error_count
        ==
        base_overflow + 1
    );


    repeat (20)
        @(posedge clk);


    if (
        output_frame_count
        !=
        base_output
    ) begin

        $display(
            "ERROR: OUTPUT ADVANCED WHILE READY=0"
        );

        error_count =
            error_count + 1;

    end


    @(negedge clk);
    m_ready = 1'b1;


    wait (
        output_frame_count
        ==
        base_output + 2
    );


    $display(
        "TEST 11 BUFFER OVERFLOW DROP PASS"
    );


    repeat (30)
        @(posedge clk);


    // ========================================================
    // Final consistency checks
    // ========================================================

    if (exp_rd != exp_wr) begin

        $display(
            "ERROR: EXPECTED QUEUE NOT EMPTY: RD=%0d WR=%0d",
            exp_rd,
            exp_wr
        );

        error_count =
            error_count + 1;

    end


    if (
        output_done_count
        !=
        output_frame_count
    ) begin

        $display(
            "ERROR: OUTPUT_DONE COUNT %0d != OUTPUT FRAME COUNT %0d",
            output_done_count,
            output_frame_count
        );

        error_count =
            error_count + 1;

    end


    // ========================================================
    // Final result
    // ========================================================

    if (error_count == 0) begin

        $display("");
        $display("==============================================");
        $display("M3-A GMII RX EXTENDED TEST PASS");
        $display("VARIABLE LENGTH VERIFIED");
        $display("UNDERSIZE DROP VERIFIED");
        $display("MAXIMUM 1518-BYTE FRAME VERIFIED");
        $display("OVERSIZE DROP VERIFIED");
        $display("PING-PONG BUFFER VERIFIED");
        $display("BACKPRESSURE HOLD VERIFIED");
        $display("BUFFER OVERFLOW DROP VERIFIED");
        $display("OUTPUT ORDER VERIFIED");
        $display("==============================================");
        $display("");

    end
    else begin

        $fatal(
            1,
            "M3-A EXTENDED TEST FAIL: %0d ERRORS",
            error_count
        );

    end


    $finish;

end


// ============================================================
// Timeout protection
// ============================================================

initial begin

    #1000000;

    $fatal(
        1,
        "M3-A EXTENDED FAIL: SIMULATION TIMEOUT"
    );

end


endmodule
