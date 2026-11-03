`timescale 1ns / 1ps

module tb_afdx_eth_ipv4_udp_parser;


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
// Parser input
// ============================================================

reg  [7:0]  s_data;
reg         s_valid;
wire        s_ready;

reg         s_sof;
reg         s_eof;

reg  [10:0] s_frame_length;


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
// Results / errors
// ============================================================

wire frame_done;
wire frame_valid;

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

afdx_eth_ipv4_udp_parser dut (

    .clk                (clk),
    .rst                (rst),

    .s_data             (s_data),
    .s_valid            (s_valid),
    .s_ready            (s_ready),

    .s_sof              (s_sof),
    .s_eof              (s_eof),

    .s_frame_length     (s_frame_length),


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


    .ether_type_error   (ether_type_error),
    .ip_version_error   (ip_version_error),
    .ip_ihl_error       (ip_ihl_error),
    .ip_checksum_error  (ip_checksum_error),
    .ip_protocol_error  (ip_protocol_error),
    .ip_length_error    (ip_length_error),
    .udp_length_error   (udp_length_error), .udp_checksum_error(),
    .structure_error    (structure_error)
);


// ============================================================
// Counters
// ============================================================

integer meta_count;
integer frame_done_count;
integer frame_valid_count;

integer eth_error_count;
integer version_error_count;
integer ihl_error_count;
integer checksum_error_count;
integer protocol_error_count;
integer ip_length_error_count;
integer udp_length_error_count;
integer structure_error_count;

integer payload_frame_count;
integer payload_byte_count;

integer error_count;
integer test_error_base;


// ============================================================
// Status monitor
// ============================================================

always @(posedge clk) begin

    if (rst) begin

        meta_count = 0;

        frame_done_count = 0;
        frame_valid_count = 0;

        eth_error_count = 0;
        version_error_count = 0;
        ihl_error_count = 0;
        checksum_error_count = 0;
        protocol_error_count = 0;
        ip_length_error_count = 0;
        udp_length_error_count = 0;
        structure_error_count = 0;

    end
    else begin

        if (meta_valid)
            meta_count = meta_count + 1;

        if (frame_done)
            frame_done_count =
                frame_done_count + 1;

        if (frame_valid)
            frame_valid_count =
                frame_valid_count + 1;


        if (ether_type_error)
            eth_error_count =
                eth_error_count + 1;

        if (ip_version_error)
            version_error_count =
                version_error_count + 1;

        if (ip_ihl_error)
            ihl_error_count =
                ihl_error_count + 1;

        if (ip_checksum_error)
            checksum_error_count =
                checksum_error_count + 1;

        if (ip_protocol_error)
            protocol_error_count =
                protocol_error_count + 1;

        if (ip_length_error)
            ip_length_error_count =
                ip_length_error_count + 1;

        if (udp_length_error)
            udp_length_error_count =
                udp_length_error_count + 1;

        if (structure_error)
            structure_error_count =
                structure_error_count + 1;

    end

end


// ============================================================
// Expected payload
//
// Frame 0:
// DE AD BE EF
//
// Frame 1:
// 12 34 56 78
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
                (payload_byte_count != 0)
                &&
                payload_sof
            ) begin

                $display(
                    "ERROR: UNEXPECTED PAYLOAD SOF"
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


// ============================================================
// Payload backpressure stability monitor
// ============================================================

reg hold_active;

reg [7:0] hold_data;
reg       hold_sof;
reg       hold_eof;


always @(posedge clk) begin

    if (rst) begin

        hold_active = 1'b0;

    end
    else begin

        if (
            payload_valid
            &&
            !payload_ready
        ) begin

            if (!hold_active) begin

                hold_active = 1'b1;

                hold_data = payload_data;
                hold_sof  = payload_sof;
                hold_eof  = payload_eof;

            end
            else begin

                if (
                    (payload_data !== hold_data)
                    ||
                    (payload_sof !== hold_sof)
                    ||
                    (payload_eof !== hold_eof)
                ) begin

                    $display(
                        "ERROR: PAYLOAD CHANGED DURING BACKPRESSURE"
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
// Valid frame byte generator
//
// frame_id = 0:
//
// Dst MAC  = 02:00:00:00:00:02
// Src MAC  = 02:00:00:00:00:01
// Src IP   = 10.0.0.1
// Dst IP   = 10.0.0.2
// Src Port = 10000
// Dst Port = 10001
// Payload  = DEADBEEF
// Sequence = 00
// Checksum = 66CB
//
// frame_id = 1:
//
// Dst MAC  = 02:00:00:00:00:03
// Src MAC  = 02:00:00:00:00:01
// Src IP   = 10.0.0.1
// Dst IP   = 10.0.0.3
// Src Port = 10000
// Dst Port = 20001
// Payload  = 12345678
// Sequence = 01
// Checksum = 66CA
// ============================================================

function [7:0] valid_frame_byte;

    input integer frame_id;
    input integer index;

    begin

        valid_frame_byte = 8'h00;


        if (frame_id == 0) begin

            case (index)

                0:  valid_frame_byte = 8'h02;
                1:  valid_frame_byte = 8'h00;
                2:  valid_frame_byte = 8'h00;
                3:  valid_frame_byte = 8'h00;
                4:  valid_frame_byte = 8'h00;
                5:  valid_frame_byte = 8'h02;

                6:  valid_frame_byte = 8'h02;
                7:  valid_frame_byte = 8'h00;
                8:  valid_frame_byte = 8'h00;
                9:  valid_frame_byte = 8'h00;
                10: valid_frame_byte = 8'h00;
                11: valid_frame_byte = 8'h01;

                12: valid_frame_byte = 8'h08;
                13: valid_frame_byte = 8'h00;

                14: valid_frame_byte = 8'h45;
                15: valid_frame_byte = 8'h00;

                16: valid_frame_byte = 8'h00;
                17: valid_frame_byte = 8'h20;

                18: valid_frame_byte = 8'h00;
                19: valid_frame_byte = 8'h00;

                20: valid_frame_byte = 8'h00;
                21: valid_frame_byte = 8'h00;

                22: valid_frame_byte = 8'h40;
                23: valid_frame_byte = 8'h11;

                24: valid_frame_byte = 8'h66;
                25: valid_frame_byte = 8'hCB;

                26: valid_frame_byte = 8'h0A;
                27: valid_frame_byte = 8'h00;
                28: valid_frame_byte = 8'h00;
                29: valid_frame_byte = 8'h01;

                30: valid_frame_byte = 8'h0A;
                31: valid_frame_byte = 8'h00;
                32: valid_frame_byte = 8'h00;
                33: valid_frame_byte = 8'h02;

                34: valid_frame_byte = 8'h27;
                35: valid_frame_byte = 8'h10;

                36: valid_frame_byte = 8'h27;
                37: valid_frame_byte = 8'h11;

                38: valid_frame_byte = 8'h00;
                39: valid_frame_byte = 8'h0C;

                40: valid_frame_byte = 8'h00;
                41: valid_frame_byte = 8'h00;

                42: valid_frame_byte = 8'hDE;
                43: valid_frame_byte = 8'hAD;
                44: valid_frame_byte = 8'hBE;
                45: valid_frame_byte = 8'hEF;

                59: valid_frame_byte = 8'h00;

                default:
                    valid_frame_byte = 8'h00;

            endcase

        end
        else begin

            case (index)

                0:  valid_frame_byte = 8'h02;
                1:  valid_frame_byte = 8'h00;
                2:  valid_frame_byte = 8'h00;
                3:  valid_frame_byte = 8'h00;
                4:  valid_frame_byte = 8'h00;
                5:  valid_frame_byte = 8'h03;

                6:  valid_frame_byte = 8'h02;
                7:  valid_frame_byte = 8'h00;
                8:  valid_frame_byte = 8'h00;
                9:  valid_frame_byte = 8'h00;
                10: valid_frame_byte = 8'h00;
                11: valid_frame_byte = 8'h01;

                12: valid_frame_byte = 8'h08;
                13: valid_frame_byte = 8'h00;

                14: valid_frame_byte = 8'h45;
                15: valid_frame_byte = 8'h00;

                16: valid_frame_byte = 8'h00;
                17: valid_frame_byte = 8'h20;

                18: valid_frame_byte = 8'h00;
                19: valid_frame_byte = 8'h00;

                20: valid_frame_byte = 8'h00;
                21: valid_frame_byte = 8'h00;

                22: valid_frame_byte = 8'h40;
                23: valid_frame_byte = 8'h11;

                24: valid_frame_byte = 8'h66;
                25: valid_frame_byte = 8'hCA;

                26: valid_frame_byte = 8'h0A;
                27: valid_frame_byte = 8'h00;
                28: valid_frame_byte = 8'h00;
                29: valid_frame_byte = 8'h01;

                30: valid_frame_byte = 8'h0A;
                31: valid_frame_byte = 8'h00;
                32: valid_frame_byte = 8'h00;
                33: valid_frame_byte = 8'h03;

                34: valid_frame_byte = 8'h27;
                35: valid_frame_byte = 8'h10;

                36: valid_frame_byte = 8'h4E;
                37: valid_frame_byte = 8'h21;

                38: valid_frame_byte = 8'h00;
                39: valid_frame_byte = 8'h0C;

                40: valid_frame_byte = 8'h00;
                41: valid_frame_byte = 8'h00;

                42: valid_frame_byte = 8'h12;
                43: valid_frame_byte = 8'h34;
                44: valid_frame_byte = 8'h56;
                45: valid_frame_byte = 8'h78;

                59: valid_frame_byte = 8'h01;

                default:
                    valid_frame_byte = 8'h00;

            endcase

        end

    end

endfunction


// ============================================================
// Drive one validated body byte
//
// The byte is presented before a rising edge.
//
// A transfer occurs on exactly one rising edge where:
//
//     s_valid == 1
//     s_ready == 1
//
// Important:
// Do NOT wait for READY on negedge and then wait for another
// posedge. That can cause one byte to be accepted twice when
// READY changes during backpressure release.
// ============================================================

task drive_stream_byte;

    input [7:0]  data;
    input        sof;
    input        eof;
    input [10:0] length;

    begin

        // ----------------------------------------------------
        // Present byte before the sampling edge.
        // ----------------------------------------------------

        @(negedge clk);

        s_data = data;
        s_valid = 1'b1;

        s_sof = sof;
        s_eof = eof;

        s_frame_length = length;


        // ----------------------------------------------------
        // Wait for the FIRST rising edge on which READY is 1.
        //
        // DUT consumes the byte on that exact edge.
        // ----------------------------------------------------

        @(posedge clk);

        while (s_ready !== 1'b1) begin

            @(posedge clk);

        end


        // ----------------------------------------------------
        // Transfer has completed exactly once.
        //
        // Remove VALID before another rising edge can consume
        // the same byte again.
        // ----------------------------------------------------

        @(negedge clk);

        s_valid = 1'b0;
        s_sof = 1'b0;
        s_eof = 1'b0;

    end

endtask


// ============================================================
// Send frame
//
// variant:
//
// 0 = valid
// 1 = bad EtherType
// 2 = bad IPv4 checksum
// 3 = bad IPv4 version, checksum adjusted
// 4 = unsupported IHL, checksum adjusted
// 5 = wrong IP protocol, checksum adjusted
// 6 = inconsistent UDP length
// ============================================================

task send_frame;

    input integer frame_id;
    input integer variant;

    integer i;

    reg [7:0] value;

    begin

        for (i = 0; i < 60; i = i + 1) begin

            value =
                valid_frame_byte(
                    frame_id,
                    i
                );


            // -----------------------------------------
            // Bad EtherType:
            // 0800 -> 0806
            // -----------------------------------------

            if (
                (variant == 1)
                &&
                (i == 13)
            )
                value = 8'h06;


            // -----------------------------------------
            // Bad IPv4 checksum
            // -----------------------------------------

            if (
                (variant == 2)
                &&
                (i == 24)
            )
                value = 8'h67;


            // -----------------------------------------
            // Version 6 instead of 4.
            //
            // 45 -> 65
            //
            // Recomputed checksum:
            // 46CB
            // -----------------------------------------

            if (variant == 3) begin

                if (i == 14)
                    value = 8'h65;

                if (i == 24)
                    value = 8'h46;

                if (i == 25)
                    value = 8'hCB;

            end


            // -----------------------------------------
            // IHL = 6 instead of 5.
            //
            // 45 -> 46
            //
            // Recomputed checksum:
            // 65CB
            // -----------------------------------------

            if (variant == 4) begin

                if (i == 14)
                    value = 8'h46;

                if (i == 24)
                    value = 8'h65;

                if (i == 25)
                    value = 8'hCB;

            end


            // -----------------------------------------
            // Protocol TCP(6) instead of UDP(17).
            //
            // Recomputed checksum:
            // 66D6
            // -----------------------------------------

            if (variant == 5) begin

                if (i == 23)
                    value = 8'h06;

                if (i == 24)
                    value = 8'h66;

                if (i == 25)
                    value = 8'hD6;

            end


            // -----------------------------------------
            // UDP length:
            //
            // 12 -> 13
            //
            // IP total length remains 32,
            // therefore IP/UDP lengths disagree.
            // -----------------------------------------

            if (
                (variant == 6)
                &&
                (i == 39)
            )
                value = 8'h0D;


            drive_stream_byte(
                value,
                (i == 0),
                (i == 59),
                11'd60
            );

        end

    end

endtask


// ============================================================
// Metadata checking tasks
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

        if (ip_ttl !== 8'h40)
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

        if (udp_checksum !== 16'h0000)
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

        if (src_mac !== 48'h020000000001)
            error_count = error_count + 1;

        if (ether_type !== 16'h0800)
            error_count = error_count + 1;


        if (ip_total_length !== 16'h0020)
            error_count = error_count + 1;

        if (ip_header_checksum !== 16'h66CA)
            error_count = error_count + 1;

        if (src_ip !== 32'h0A000001)
            error_count = error_count + 1;

        if (dst_ip !== 32'h0A000003)
            error_count = error_count + 1;


        if (udp_src_port !== 16'h2710)
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
// Main test
// ============================================================

integer base_meta;
integer base_valid;
integer base_payload;

integer base_error;


initial begin

    s_data = 8'd0;
    s_valid = 1'b0;

    s_sof = 1'b0;
    s_eof = 1'b0;

    s_frame_length = 11'd0;


    payload_ready = 1'b1;


    error_count = 0;


    rst = 1'b1;

    repeat (10)
        @(posedge clk);

    @(negedge clk);

    rst = 1'b0;


    // ========================================================
    // TEST 1
    // Valid frame 0
    // ========================================================

    test_error_base =
        error_count;

    send_frame(
        0,
        0
    );


    repeat (5)
        @(posedge clk);


    if (frame_valid_count != 1) begin

        $display(
            "ERROR: FRAME 0 NOT ACCEPTED"
        );

        error_count =
            error_count + 1;

    end


    if (meta_count != 1) begin

        $display(
            "ERROR: FRAME 0 META MISSING"
        );

        error_count =
            error_count + 1;

    end


    if (payload_frame_count != 1) begin

        $display(
            "ERROR: FRAME 0 PAYLOAD MISSING"
        );

        error_count =
            error_count + 1;

    end


    check_frame0_metadata;


    if (
        error_count
        ==
        test_error_base
    ) begin

        $display(
            "TEST 1 VALID FRAME 0 PARSE PASS"
        );

    end
    else begin

        $display(
            "TEST 1 VALID FRAME 0 PARSE FAIL"
        );

    end


    // ========================================================
    // TEST 2
    // Valid frame 1 with payload backpressure
    // ========================================================

    test_error_base =
        error_count;

    payload_ready = 1'b0;


    fork

        begin

            send_frame(
                1,
                0
            );

        end


        begin

            wait (payload_valid);

            repeat (5)
                @(posedge clk);

            @(negedge clk);

            payload_ready = 1'b1;

        end

    join


    repeat (10)
        @(posedge clk);


    if (frame_valid_count != 2) begin

        $display(
            "ERROR: FRAME 1 NOT ACCEPTED"
        );

        error_count =
            error_count + 1;

    end


    if (meta_count != 2) begin

        $display(
            "ERROR: FRAME 1 META MISSING"
        );

        error_count =
            error_count + 1;

    end


    if (payload_frame_count != 2) begin

        $display(
            "ERROR: FRAME 1 PAYLOAD MISSING"
        );

        error_count =
            error_count + 1;

    end


    check_frame1_metadata;


    if (
        error_count
        ==
        test_error_base
    ) begin

        $display(
            "TEST 2 FRAME 1 / BACKPRESSURE PASS"
        );

    end
    else begin

        $display(
            "TEST 2 FRAME 1 / BACKPRESSURE FAIL"
        );

    end


    // ========================================================
    // TEST 3
    // Bad EtherType
    // ========================================================

    test_error_base =
        error_count;

    base_meta =
        meta_count;

    base_valid =
        frame_valid_count;

    base_payload =
        payload_frame_count;

    base_error =
        eth_error_count;


    send_frame(
        0,
        1
    );


    repeat (5)
        @(posedge clk);


    if (
        eth_error_count
        !=
        base_error + 1
    )
        error_count =
            error_count + 1;


    if (
        (meta_count != base_meta)
        ||
        (frame_valid_count != base_valid)
        ||
        (payload_frame_count != base_payload)
    )
        error_count =
            error_count + 1;


    if (
        error_count
        ==
        test_error_base
    ) begin

        $display(
            "TEST 3 BAD ETHERTYPE DROP PASS"
        );

    end
    else begin

        $display(
            "TEST 3 BAD ETHERTYPE DROP FAIL"
        );

    end


    // ========================================================
    // TEST 4
    // Bad IPv4 checksum
    // ========================================================

    test_error_base =
        error_count;

    base_valid =
        frame_valid_count;

    base_payload =
        payload_frame_count;

    base_error =
        checksum_error_count;


    send_frame(
        0,
        2
    );


    repeat (5)
        @(posedge clk);


    if (
        checksum_error_count
        !=
        base_error + 1
    )
        error_count =
            error_count + 1;


    if (
        (frame_valid_count != base_valid)
        ||
        (payload_frame_count != base_payload)
    )
        error_count =
            error_count + 1;


    if (
        error_count
        ==
        test_error_base
    ) begin

        $display(
            "TEST 4 BAD IPV4 CHECKSUM DROP PASS"
        );

    end
    else begin

        $display(
            "TEST 4 BAD IPV4 CHECKSUM DROP FAIL"
        );

    end


    // ========================================================
    // TEST 5
    // Wrong IPv4 version
    // ========================================================

    test_error_base =
        error_count;

    base_valid =
        frame_valid_count;

    base_error =
        version_error_count;


    send_frame(
        0,
        3
    );


    repeat (5)
        @(posedge clk);


    if (
        version_error_count
        !=
        base_error + 1
    )
        error_count =
            error_count + 1;


    if (
        frame_valid_count
        !=
        base_valid
    )
        error_count =
            error_count + 1;


    if (
        error_count
        ==
        test_error_base
    ) begin

        $display(
            "TEST 5 IPV4 VERSION DROP PASS"
        );

    end
    else begin

        $display(
            "TEST 5 IPV4 VERSION DROP FAIL"
        );

    end


    // ========================================================
    // TEST 6
    // Unsupported IHL
    // ========================================================

    test_error_base =
        error_count;

    base_valid =
        frame_valid_count;

    base_error =
        ihl_error_count;


    send_frame(
        0,
        4
    );


    repeat (5)
        @(posedge clk);


    if (
        ihl_error_count
        !=
        base_error + 1
    )
        error_count =
            error_count + 1;


    if (
        frame_valid_count
        !=
        base_valid
    )
        error_count =
            error_count + 1;


    if (
        error_count
        ==
        test_error_base
    ) begin

        $display(
            "TEST 6 IPV4 IHL DROP PASS"
        );

    end
    else begin

        $display(
            "TEST 6 IPV4 IHL DROP FAIL"
        );

    end


    // ========================================================
    // TEST 7
    // Wrong protocol
    // ========================================================

    test_error_base =
        error_count;

    base_valid =
        frame_valid_count;

    base_error =
        protocol_error_count;


    send_frame(
        0,
        5
    );


    repeat (5)
        @(posedge clk);


    if (
        protocol_error_count
        !=
        base_error + 1
    )
        error_count =
            error_count + 1;


    if (
        frame_valid_count
        !=
        base_valid
    )
        error_count =
            error_count + 1;


    if (
        error_count
        ==
        test_error_base
    ) begin

        $display(
            "TEST 7 NON-UDP PROTOCOL DROP PASS"
        );

    end
    else begin

        $display(
            "TEST 7 NON-UDP PROTOCOL DROP FAIL"
        );

    end


    // ========================================================
    // TEST 8
    // IP / UDP length mismatch
    // ========================================================

    test_error_base =
        error_count;

    base_valid =
        frame_valid_count;

    base_error =
        ip_length_error_count;


    send_frame(
        0,
        6
    );


    repeat (5)
        @(posedge clk);


    if (
        ip_length_error_count
        !=
        base_error + 1
    )
        error_count =
            error_count + 1;


    if (
        frame_valid_count
        !=
        base_valid
    )
        error_count =
            error_count + 1;


    if (
        error_count
        ==
        test_error_base
    ) begin

        $display(
            "TEST 8 IP / UDP LENGTH DROP PASS"
        );

    end
    else begin

        $display(
            "TEST 8 IP / UDP LENGTH DROP FAIL"
        );

    end


    // ========================================================
    // Final checks
    // ========================================================

    if (frame_done_count != 8) begin

        $display(
            "ERROR: FRAME DONE COUNT = %0d EXPECTED 8",
            frame_done_count
        );

        error_count =
            error_count + 1;

    end


    if (frame_valid_count != 2) begin

        $display(
            "ERROR: VALID FRAME COUNT = %0d EXPECTED 2",
            frame_valid_count
        );

        error_count =
            error_count + 1;

    end


    if (payload_frame_count != 2) begin

        $display(
            "ERROR: PAYLOAD FRAME COUNT = %0d EXPECTED 2",
            payload_frame_count
        );

        error_count =
            error_count + 1;

    end


    // ========================================================
    // Result
    // ========================================================

    if (error_count == 0) begin

        $display("");
        $display("==============================================");
        $display("M3-B ETH/IP/UDP PARSER BASIC TEST PASS");
        $display("ETHERNET FIELD PARSE VERIFIED");
        $display("IPV4 FIELD PARSE VERIFIED");
        $display("IPV4 CHECKSUM VERIFIED");
        $display("UDP FIELD PARSE VERIFIED");
        $display("UDP PAYLOAD STREAM VERIFIED");
        $display("PAYLOAD BACKPRESSURE VERIFIED");
        $display("PADDING LENGTH VERIFIED");
        $display("RAW AFDX SEQUENCE EXTRACTION VERIFIED");
        $display("BAD ETHERTYPE DROP VERIFIED");
        $display("BAD IPV4 VERSION DROP VERIFIED");
        $display("BAD IPV4 IHL DROP VERIFIED");
        $display("BAD IPV4 CHECKSUM DROP VERIFIED");
        $display("NON-UDP PROTOCOL DROP VERIFIED");
        $display("IP / UDP LENGTH CHECK VERIFIED");
        $display("==============================================");
        $display("");

    end
    else begin

        $fatal(
            1,
            "M3-B BASIC TEST FAIL: %0d ERRORS",
            error_count
        );

    end


    $finish;

end


// ============================================================
// Timeout
// ============================================================

initial begin

    #300000;

    $fatal(
        1,
        "M3-B FAIL: SIMULATION TIMEOUT"
    );

end


endmodule
