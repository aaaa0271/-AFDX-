`timescale 1ns / 1ps

module tb_afdx_rx_frontend;


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
// Raw GMII
// ============================================================

reg [7:0] gmii_rxd;
reg       gmii_rx_dv;
reg       gmii_rx_er;


// ============================================================
// Metadata
// ============================================================

wire [47:0] dst_mac;
wire [47:0] src_mac;
wire [15:0] ether_type;

wire [15:0] ip_total_length;
wire [7:0]  ip_ttl;
wire [7:0]  ip_protocol;
wire [15:0] ip_header_checksum;

wire [31:0] src_ip;
wire [31:0] dst_ip;

wire [15:0] udp_src_port;
wire [15:0] udp_dst_port;
wire [15:0] udp_length;
wire [15:0] udp_checksum;

wire [10:0] payload_length;
wire [4:0]  padding_length;

wire [7:0] afdx_sequence;

wire meta_valid;


// ============================================================
// Payload
// ============================================================

wire [7:0] payload_data;
wire       payload_valid;

reg        payload_ready;

wire       payload_sof;
wire       payload_eof;


// ============================================================
// Frame result
// ============================================================

wire frame_done;
wire frame_valid;


// ============================================================
// Layer-2 status
// ============================================================

wire l2_good_frame;
wire l2_output_frame_done;

wire l2_crc_error;
wire l2_format_error;
wire l2_length_error;
wire l2_rx_error;
wire l2_overflow_error;


// ============================================================
// Parser errors
// ============================================================

wire ether_type_error;
wire ip_version_error;
wire ip_ihl_error;
wire ip_checksum_error;
wire ip_protocol_error;
wire ip_length_error;
wire udp_length_error;
wire structure_error;


// ============================================================
// DUT
// ============================================================

afdx_rx_frontend dut (

    .clk                (clk),
    .rst                (rst),


    .gmii_rxd           (gmii_rxd),
    .gmii_rx_dv         (gmii_rx_dv),
    .gmii_rx_er         (gmii_rx_er),


    .dst_mac            (dst_mac),
    .src_mac            (src_mac),
    .ether_type         (ether_type),


    .ip_total_length    (ip_total_length),
    .ip_ttl             (ip_ttl),
    .ip_protocol        (ip_protocol),
    .ip_header_checksum (ip_header_checksum),

    .src_ip             (src_ip),
    .dst_ip             (dst_ip),


    .udp_src_port       (udp_src_port),
    .udp_dst_port       (udp_dst_port),
    .udp_length         (udp_length),
    .udp_checksum       (udp_checksum),

    .payload_length     (payload_length),
    .padding_length     (padding_length),


    .afdx_sequence      (afdx_sequence),

    .meta_valid         (meta_valid),


    .payload_data       (payload_data),
    .payload_valid      (payload_valid),
    .payload_ready      (payload_ready),

    .payload_sof        (payload_sof),
    .payload_eof        (payload_eof),


    .frame_done         (frame_done),
    .frame_valid        (frame_valid),


    .l2_good_frame      (l2_good_frame),

    .l2_output_frame_done(
        l2_output_frame_done
    ),

    .l2_crc_error       (l2_crc_error),
    .l2_format_error    (l2_format_error),
    .l2_length_error    (l2_length_error),
    .l2_rx_error        (l2_rx_error),
    .l2_overflow_error  (l2_overflow_error),


    .ether_type_error   (ether_type_error),
    .ip_version_error   (ip_version_error),
    .ip_ihl_error       (ip_ihl_error),
    .ip_checksum_error  (ip_checksum_error),
    .ip_protocol_error  (ip_protocol_error),
    .ip_length_error    (ip_length_error),
    .udp_length_error   (udp_length_error),
    .structure_error    (structure_error)
);


// ============================================================
// Counters
// ============================================================

integer l2_good_count;
integer l2_output_done_count;
integer l2_crc_error_count;
integer l2_overflow_count;

integer meta_count;
integer frame_done_count;
integer frame_valid_count;

integer ip_checksum_error_count;

integer payload_frame_count;
integer payload_byte_count;

integer expected_payload_frames;

integer error_count;
integer test_error_base;


// ============================================================
// Event monitor
// ============================================================

always @(posedge clk) begin

    if (rst) begin

        l2_good_count = 0;
        l2_output_done_count = 0;
        l2_crc_error_count = 0;
        l2_overflow_count = 0;

        meta_count = 0;
        frame_done_count = 0;
        frame_valid_count = 0;

        ip_checksum_error_count = 0;

    end
    else begin

        if (l2_good_frame)
            l2_good_count =
                l2_good_count + 1;

        if (l2_output_frame_done)
            l2_output_done_count =
                l2_output_done_count + 1;

        if (l2_crc_error)
            l2_crc_error_count =
                l2_crc_error_count + 1;

        if (l2_overflow_error)
            l2_overflow_count =
                l2_overflow_count + 1;


        if (meta_valid)
            meta_count =
                meta_count + 1;

        if (frame_done)
            frame_done_count =
                frame_done_count + 1;

        if (frame_valid)
            frame_valid_count =
                frame_valid_count + 1;


        if (ip_checksum_error)
            ip_checksum_error_count =
                ip_checksum_error_count + 1;

    end

end


// ============================================================
// Expected payload
// ============================================================

function [7:0] expected_payload_byte;

    input integer frame_no;
    input integer byte_no;

    begin

        if (frame_no == 0) begin

            case (byte_no)

                0:
                    expected_payload_byte = 8'hDE;

                1:
                    expected_payload_byte = 8'hAD;

                2:
                    expected_payload_byte = 8'hBE;

                3:
                    expected_payload_byte = 8'hEF;

                default:
                    expected_payload_byte = 8'hXX;

            endcase

        end
        else begin

            case (byte_no)

                0:
                    expected_payload_byte = 8'h12;

                1:
                    expected_payload_byte = 8'h34;

                2:
                    expected_payload_byte = 8'h56;

                3:
                    expected_payload_byte = 8'h78;

                default:
                    expected_payload_byte = 8'hXX;

            endcase

        end

    end

endfunction


// ============================================================
// Payload scoreboard
// ============================================================

always @(posedge clk) begin

    if (rst) begin

        payload_frame_count = 0;
        payload_byte_count = 0;

    end
    else begin

        if (
            payload_valid
            &&
            payload_ready
        ) begin

            if (
                payload_frame_count
                >=
                expected_payload_frames
            ) begin

                $display(
                    "ERROR: UNEXPECTED PAYLOAD OUTPUT"
                );

                error_count =
                    error_count + 1;

            end
            else begin

                if (
                    payload_data
                    !==
                    expected_payload_byte(
                        payload_frame_count,
                        payload_byte_count
                    )
                ) begin

                    $display(
                        "ERROR: PAYLOAD FRAME %0d BYTE %0d = %02X EXPECTED %02X",
                        payload_frame_count,
                        payload_byte_count,
                        payload_data,
                        expected_payload_byte(
                            payload_frame_count,
                            payload_byte_count
                        )
                    );

                    error_count =
                        error_count + 1;

                end


                if (
                    (payload_byte_count == 0)
                    &&
                    !payload_sof
                ) begin

                    $display(
                        "ERROR: PAYLOAD SOF MISSING"
                    );

                    error_count =
                        error_count + 1;

                end


                if (
                    (payload_byte_count == 3)
                    &&
                    !payload_eof
                ) begin

                    $display(
                        "ERROR: PAYLOAD EOF MISSING"
                    );

                    error_count =
                        error_count + 1;

                end


                if (
                    (payload_byte_count != 3)
                    &&
                    payload_eof
                ) begin

                    $display(
                        "ERROR: UNEXPECTED PAYLOAD EOF"
                    );

                    error_count =
                        error_count + 1;

                end


                if (payload_byte_count == 3) begin

                    payload_byte_count = 0;

                    payload_frame_count =
                        payload_frame_count + 1;

                end
                else begin

                    payload_byte_count =
                        payload_byte_count + 1;

                end

            end

        end

    end

end


// ============================================================
// Internal M3-A -> M3-B backpressure stability
//
// Observe wrapper internal validated-body stream.
//
// When body_valid=1 and body_ready=0:
//
// data / sof / eof / length must remain stable.
// ============================================================

reg        hold_active;

reg [7:0]  hold_body_data;
reg        hold_body_sof;
reg        hold_body_eof;
reg [10:0] hold_body_length;


always @(posedge clk) begin

    if (rst) begin

        hold_active = 1'b0;

    end
    else begin

        if (
            dut.body_valid
            &&
            !dut.body_ready
        ) begin

            if (!hold_active) begin

                hold_active =
                    1'b1;

                hold_body_data =
                    dut.body_data;

                hold_body_sof =
                    dut.body_sof;

                hold_body_eof =
                    dut.body_eof;

                hold_body_length =
                    dut.body_frame_length;

            end
            else begin

                if (
                    (dut.body_data
                     !== hold_body_data)
                    ||
                    (dut.body_sof
                     !== hold_body_sof)
                    ||
                    (dut.body_eof
                     !== hold_body_eof)
                    ||
                    (
                        dut.body_frame_length
                        !==
                        hold_body_length
                    )
                ) begin

                    $display(
                        "ERROR: M3-A BODY STREAM CHANGED DURING BACKPRESSURE"
                    );

                    error_count =
                        error_count + 1;

                end

            end

        end
        else begin

            hold_active =
                1'b0;

        end

    end

end


// ============================================================
// Frame body byte
//
// variant:
//
// 0 = valid
// 1 = invalid IPv4 checksum
// ============================================================

function [7:0] frame_body_byte;

    input integer frame_id;
    input integer variant;
    input integer index;

    begin

        frame_body_byte =
            8'h00;


        if (frame_id == 0) begin

            case (index)

                // Destination MAC

                0:  frame_body_byte = 8'h02;
                1:  frame_body_byte = 8'h00;
                2:  frame_body_byte = 8'h00;
                3:  frame_body_byte = 8'h00;
                4:  frame_body_byte = 8'h00;
                5:  frame_body_byte = 8'h02;


                // Source MAC

                6:  frame_body_byte = 8'h02;
                7:  frame_body_byte = 8'h00;
                8:  frame_body_byte = 8'h00;
                9:  frame_body_byte = 8'h00;
                10: frame_body_byte = 8'h00;
                11: frame_body_byte = 8'h01;


                // EtherType

                12: frame_body_byte = 8'h08;
                13: frame_body_byte = 8'h00;


                // IPv4

                14: frame_body_byte = 8'h45;
                15: frame_body_byte = 8'h00;

                16: frame_body_byte = 8'h00;
                17: frame_body_byte = 8'h20;

                18: frame_body_byte = 8'h00;
                19: frame_body_byte = 8'h00;

                20: frame_body_byte = 8'h00;
                21: frame_body_byte = 8'h00;

                22: frame_body_byte = 8'h40;
                23: frame_body_byte = 8'h11;

                // Valid checksum = 66CB.
                //
                // Variant 1 deliberately changes it to
                // 67CB while recomputing Ethernet FCS.

                24:
                    if (variant == 1)
                        frame_body_byte = 8'h67;
                    else
                        frame_body_byte = 8'h66;

                25:
                    frame_body_byte = 8'hCB;


                // Source IP

                26: frame_body_byte = 8'h0A;
                27: frame_body_byte = 8'h00;
                28: frame_body_byte = 8'h00;
                29: frame_body_byte = 8'h01;


                // Destination IP

                30: frame_body_byte = 8'h0A;
                31: frame_body_byte = 8'h00;
                32: frame_body_byte = 8'h00;
                33: frame_body_byte = 8'h02;


                // UDP

                34: frame_body_byte = 8'h27;
                35: frame_body_byte = 8'h10;

                36: frame_body_byte = 8'h27;
                37: frame_body_byte = 8'h11;

                38: frame_body_byte = 8'h00;
                39: frame_body_byte = 8'h0C;

                40: frame_body_byte = 8'h00;
                41: frame_body_byte = 8'h00;


                // Payload

                42: frame_body_byte = 8'hDE;
                43: frame_body_byte = 8'hAD;
                44: frame_body_byte = 8'hBE;
                45: frame_body_byte = 8'hEF;


                // Sequence

                59: frame_body_byte = 8'h00;


                default:
                    frame_body_byte = 8'h00;

            endcase

        end
        else begin

            case (index)

                // Destination MAC

                0:  frame_body_byte = 8'h02;
                1:  frame_body_byte = 8'h00;
                2:  frame_body_byte = 8'h00;
                3:  frame_body_byte = 8'h00;
                4:  frame_body_byte = 8'h00;
                5:  frame_body_byte = 8'h03;


                // Source MAC

                6:  frame_body_byte = 8'h02;
                7:  frame_body_byte = 8'h00;
                8:  frame_body_byte = 8'h00;
                9:  frame_body_byte = 8'h00;
                10: frame_body_byte = 8'h00;
                11: frame_body_byte = 8'h01;


                // EtherType

                12: frame_body_byte = 8'h08;
                13: frame_body_byte = 8'h00;


                // IPv4

                14: frame_body_byte = 8'h45;
                15: frame_body_byte = 8'h00;

                16: frame_body_byte = 8'h00;
                17: frame_body_byte = 8'h20;

                18: frame_body_byte = 8'h00;
                19: frame_body_byte = 8'h00;

                20: frame_body_byte = 8'h00;
                21: frame_body_byte = 8'h00;

                22: frame_body_byte = 8'h40;
                23: frame_body_byte = 8'h11;

                24: frame_body_byte = 8'h66;
                25: frame_body_byte = 8'hCA;


                // Source IP

                26: frame_body_byte = 8'h0A;
                27: frame_body_byte = 8'h00;
                28: frame_body_byte = 8'h00;
                29: frame_body_byte = 8'h01;


                // Destination IP

                30: frame_body_byte = 8'h0A;
                31: frame_body_byte = 8'h00;
                32: frame_body_byte = 8'h00;
                33: frame_body_byte = 8'h03;


                // UDP

                34: frame_body_byte = 8'h27;
                35: frame_body_byte = 8'h10;

                36: frame_body_byte = 8'h4E;
                37: frame_body_byte = 8'h21;

                38: frame_body_byte = 8'h00;
                39: frame_body_byte = 8'h0C;

                40: frame_body_byte = 8'h00;
                41: frame_body_byte = 8'h00;


                // Payload

                42: frame_body_byte = 8'h12;
                43: frame_body_byte = 8'h34;
                44: frame_body_byte = 8'h56;
                45: frame_body_byte = 8'h78;


                // Sequence

                59: frame_body_byte = 8'h01;


                default:
                    frame_body_byte = 8'h00;

            endcase

        end

    end

endfunction


// ============================================================
// Drive one raw GMII byte
// ============================================================

task drive_gmii_byte;

    input [7:0] data;

    begin

        @(negedge clk);

        gmii_rxd   = data;
        gmii_rx_dv = 1'b1;
        gmii_rx_er = 1'b0;

    end

endtask


// ============================================================
// End raw Ethernet frame
//
// 12 idle byte-times are provided.
// ============================================================

task end_gmii_frame;

    integer i;

    begin

        @(negedge clk);

        gmii_rxd   = 8'h00;
        gmii_rx_dv = 1'b0;
        gmii_rx_er = 1'b0;


        for (i = 0; i < 12; i = i + 1)
            @(negedge clk);

    end

endtask


// ============================================================
// Raw GMII frame transmitter
//
// variant:
//
// 0 = valid
// 1 = corrupted Ethernet FCS
// 2 = bad IPv4 checksum but CORRECT Ethernet FCS
// ============================================================

task send_raw_frame;

    input integer frame_id;
    input integer variant;

    integer i;

    begin

        // ----------------------------------------------------
        // Preamble
        // ----------------------------------------------------

        for (i = 0; i < 7; i = i + 1)
            drive_gmii_byte(
                8'h55
            );


        // ----------------------------------------------------
        // SFD
        // ----------------------------------------------------

        drive_gmii_byte(
            8'hD5
        );


        // ----------------------------------------------------
        // 60-byte Ethernet body
        // ----------------------------------------------------

        for (i = 0; i < 60; i = i + 1)
            drive_gmii_byte(
                frame_body_byte(
                    frame_id,
                    (variant == 2),
                    i
                )
            );


        // ----------------------------------------------------
        // FCS
        // ----------------------------------------------------

        if (frame_id == 0) begin

            if (variant == 2) begin

                // Body contains bad IPv4 checksum 67CB.
                //
                // Correct Ethernet CRC32:
                //
                // E82CEE23
                //
                // GMII byte order:
                //
                // 23 EE 2C E8

                drive_gmii_byte(8'h23);
                drive_gmii_byte(8'hEE);
                drive_gmii_byte(8'h2C);
                drive_gmii_byte(8'hE8);

            end
            else begin

                // Valid Frame 0:
                //
                // CRC32 = 7D5C3AB6
                //
                // GMII:
                // B6 3A 5C 7D

                if (variant == 1)
                    drive_gmii_byte(8'hB7);
                else
                    drive_gmii_byte(8'hB6);

                drive_gmii_byte(8'h3A);
                drive_gmii_byte(8'h5C);
                drive_gmii_byte(8'h7D);

            end

        end
        else begin

            // Valid Frame 1:
            //
            // CRC32 = 42C0C44A
            //
            // GMII:
            // 4A C4 C0 42

            drive_gmii_byte(8'h4A);
            drive_gmii_byte(8'hC4);
            drive_gmii_byte(8'hC0);
            drive_gmii_byte(8'h42);

        end


        end_gmii_frame;

    end

endtask


// ============================================================
// Reset complete RX chain
// ============================================================

task reset_system;

    begin

        @(negedge clk);

        rst = 1'b1;

        gmii_rxd   = 8'd0;
        gmii_rx_dv = 1'b0;
        gmii_rx_er = 1'b0;

        payload_ready = 1'b1;

        expected_payload_frames = 0;


        repeat (8)
            @(posedge clk);


        @(negedge clk);

        rst = 1'b0;


        repeat (3)
            @(posedge clk);

    end

endtask


// ============================================================
// Metadata checks
// ============================================================

task check_frame0_metadata;

    begin

        if (dst_mac !== 48'h020000000002)
            error_count = error_count + 1;

        if (src_mac !== 48'h020000000001)
            error_count = error_count + 1;

        if (ether_type !== 16'h0800)
            error_count = error_count + 1;


        if (ip_total_length !== 16'h0020)
            error_count = error_count + 1;

        if (ip_protocol !== 8'h11)
            error_count = error_count + 1;

        if (ip_header_checksum !== 16'h66CB)
            error_count = error_count + 1;

        if (src_ip !== 32'h0A000001)
            error_count = error_count + 1;

        if (dst_ip !== 32'h0A000002)
            error_count = error_count + 1;


        if (udp_src_port !== 16'h2710)
            error_count = error_count + 1;

        if (udp_dst_port !== 16'h2711)
            error_count = error_count + 1;

        if (udp_length !== 16'h000C)
            error_count = error_count + 1;


        if (payload_length !== 11'd4)
            error_count = error_count + 1;

        if (padding_length !== 5'd13)
            error_count = error_count + 1;

        if (afdx_sequence !== 8'h00)
            error_count = error_count + 1;

    end

endtask


task check_frame1_metadata;

    begin

        if (dst_mac !== 48'h020000000003)
            error_count = error_count + 1;

        if (dst_ip !== 32'h0A000003)
            error_count = error_count + 1;

        if (ip_header_checksum !== 16'h66CA)
            error_count = error_count + 1;

        if (udp_dst_port !== 16'h4E21)
            error_count = error_count + 1;

        if (payload_length !== 11'd4)
            error_count = error_count + 1;

        if (padding_length !== 5'd13)
            error_count = error_count + 1;

        if (afdx_sequence !== 8'h01)
            error_count = error_count + 1;

    end

endtask


// ============================================================
// Main integration regression
// ============================================================

initial begin

    gmii_rxd   = 8'd0;
    gmii_rx_dv = 1'b0;
    gmii_rx_er = 1'b0;

    payload_ready = 1'b1;

    expected_payload_frames = 0;

    error_count = 0;

    rst = 1'b1;


    repeat (10)
        @(posedge clk);


    // ========================================================
    // TEST 1
    //
    // Valid raw GMII Frame 0.
    // ========================================================

    reset_system;

    test_error_base =
        error_count;

    expected_payload_frames = 1;


    send_raw_frame(
        0,
        0
    );


    wait (
        frame_valid_count == 1
    );

    wait (
        payload_frame_count == 1
    );


    repeat (5)
        @(posedge clk);


    if (l2_good_count != 1)
        error_count =
            error_count + 1;

    if (l2_crc_error_count != 0)
        error_count =
            error_count + 1;

    if (frame_done_count != 1)
        error_count =
            error_count + 1;

    if (meta_count != 1)
        error_count =
            error_count + 1;


    check_frame0_metadata;


    if (
        error_count
        ==
        test_error_base
    )
        $display(
            "TEST 1 RAW GMII -> ETH/IP/UDP PASS"
        );
    else
        $display(
            "TEST 1 RAW GMII -> ETH/IP/UDP FAIL"
        );


    // ========================================================
    // TEST 2
    //
    // Bad Ethernet FCS.
    //
    // Must be blocked by M3-A.
    // Parser must see nothing.
    // ========================================================

    reset_system;

    test_error_base =
        error_count;

    expected_payload_frames = 0;


    send_raw_frame(
        0,
        1
    );


    wait (
        l2_crc_error_count == 1
    );


    repeat (30)
        @(posedge clk);


    if (l2_good_count != 0)
        error_count =
            error_count + 1;

    if (meta_count != 0)
        error_count =
            error_count + 1;

    if (frame_done_count != 0)
        error_count =
            error_count + 1;

    if (frame_valid_count != 0)
        error_count =
            error_count + 1;

    if (payload_frame_count != 0)
        error_count =
            error_count + 1;


    if (
        error_count
        ==
        test_error_base
    )
        $display(
            "TEST 2 BAD FCS BLOCKED AT M3-A PASS"
        );
    else
        $display(
            "TEST 2 BAD FCS BLOCKED AT M3-A FAIL"
        );


    // ========================================================
    // TEST 3
    //
    // Ethernet FCS is correct.
    //
    // IPv4 checksum is deliberately bad.
    //
    // Therefore:
    //
    // M3-A must ACCEPT.
    // M3-B must DROP.
    // ========================================================

    reset_system;

    test_error_base =
        error_count;

    expected_payload_frames = 0;


    send_raw_frame(
        0,
        2
    );


    wait (
        l2_good_count == 1
    );

    wait (
        ip_checksum_error_count == 1
    );

    wait (
        frame_done_count == 1
    );


    repeat (10)
        @(posedge clk);


    if (l2_crc_error_count != 0)
        error_count =
            error_count + 1;

    if (frame_valid_count != 0)
        error_count =
            error_count + 1;

    if (meta_count != 0)
        error_count =
            error_count + 1;

    if (payload_frame_count != 0)
        error_count =
            error_count + 1;


    if (
        error_count
        ==
        test_error_base
    )
        $display(
            "TEST 3 BAD IPV4 CHECKSUM BLOCKED AT M3-B PASS"
        );
    else
        $display(
            "TEST 3 BAD IPV4 CHECKSUM BLOCKED AT M3-B FAIL"
        );


    // ========================================================
    // TEST 4
    //
    // Full-pipeline backpressure through the M3-D commit
    // buffer.
    //
    // 1. Stop application payload consumption.
    // 2. Send a valid Frame 0 (VL0, SN=0 -> first frame).
    // 3. The frame is parsed, VL-resolved and sequence-accepted,
    //    so its payload is committed to the buffer.
    // 4. Replay must stall while payload_ready is low: no
    //    payload byte may escape.
    // 5. Resume payload and verify the full 4-byte payload
    //    replays in order.
    // ========================================================

    reset_system;

    test_error_base =
        error_count;

    expected_payload_frames = 1;


    @(negedge clk);

    payload_ready =
        1'b0;


    // Frame 0 is fully accepted, and its replay stalls.

    send_raw_frame(
        0,
        0
    );


    wait (
        l2_good_count == 1
    );

    wait (
        frame_valid_count == 1
    );


    // Replay must not start while the application is stalled.

    repeat (20)
        @(posedge clk);


    if (
        payload_frame_count
        !=
        0
    ) begin

        $display(
            "ERROR: PAYLOAD REPLAYED WHILE STALLED"
        );

        error_count =
            error_count + 1;

    end


    if (
        l2_overflow_count
        !=
        0
    ) begin

        $display(
            "ERROR: UNEXPECTED M3-A BUFFER OVERFLOW"
        );

        error_count =
            error_count + 1;

    end


    // Resume downstream.

    @(negedge clk);

    payload_ready =
        1'b1;


    wait (
        payload_frame_count == 1
    );


    repeat (10)
        @(posedge clk);


    if (
        frame_done_count
        !=
        1
    )
        error_count =
            error_count + 1;


    if (
        meta_count
        !=
        1
    )
        error_count =
            error_count + 1;


    if (
        l2_overflow_count
        !=
        0
    )
        error_count =
            error_count + 1;


    // The final visible metadata belongs to Frame 0.

    check_frame0_metadata;


    if (
        error_count
        ==
        test_error_base
    )
        $display(
            "TEST 4 COMMIT BUFFER BACKPRESSURE PASS"
        );
    else
        $display(
            "TEST 4 COMMIT BUFFER BACKPRESSURE FAIL"
        );


    // ========================================================
    // Final result
    // ========================================================

    if (error_count == 0) begin

        $display("");
        $display("==============================================");
        $display("M3-A -> M3-B RX INTEGRATION TEST PASS");
        $display("RAW GMII FRAME VERIFIED");
        $display("M3-A FCS GATE VERIFIED");
        $display("M3-B ETH/IP/UDP PARSE VERIFIED");
        $display("UDP PAYLOAD VERIFIED");
        $display("RAW AFDX SEQUENCE VERIFIED");
        $display("BAD FCS BLOCKED AT M3-A");
        $display("BAD IPV4 CHECKSUM BLOCKED AT M3-B");
        $display("COMMIT BUFFER BACKPRESSURE VERIFIED");
        $display("==============================================");
        $display("");

    end
    else begin

        $fatal(
            1,
            "M3 RX INTEGRATION FAIL: %0d ERRORS",
            error_count
        );

    end


    $finish;

end


// ============================================================
// Timeout
// ============================================================

initial begin

    #500000;

    $fatal(
        1,
        "M3 RX INTEGRATION TIMEOUT"
    );

end


endmodule
