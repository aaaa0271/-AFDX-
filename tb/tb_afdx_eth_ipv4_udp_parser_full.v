`timescale 1ns / 1ps

module tb_afdx_eth_ipv4_udp_parser_full;


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
// Parser input
// ============================================================

reg  [7:0]  s_data;
reg         s_valid;
wire        s_ready;

reg         s_sof;
reg         s_eof;

reg  [10:0] s_frame_length;


// ============================================================
// Parser outputs
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


wire [7:0] payload_data;
wire       payload_valid;
reg        payload_ready;

wire payload_sof;
wire payload_eof;


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

integer frame_done_count;
integer frame_valid_count;

integer udp_length_error_count;
integer structure_error_count;

integer error_count;
integer test_error_base;


// ============================================================
// Expected payload
// ============================================================

integer expected_payload_length;
integer expected_payload_seed;

integer payload_count;
integer payload_frame_count;


// ============================================================
// Status monitor
// ============================================================

always @(posedge clk) begin

    if (rst) begin

        frame_done_count = 0;
        frame_valid_count = 0;

        udp_length_error_count = 0;
        structure_error_count = 0;

    end
    else begin

        if (frame_done)
            frame_done_count =
                frame_done_count + 1;

        if (frame_valid)
            frame_valid_count =
                frame_valid_count + 1;

        if (udp_length_error)
            udp_length_error_count =
                udp_length_error_count + 1;

        if (structure_error)
            structure_error_count =
                structure_error_count + 1;

    end

end


// ============================================================
// Payload byte pattern
//
// payload[i] = seed + i
// ============================================================

function [7:0] payload_pattern;

    input integer seed;
    input integer index;

    integer value;

    begin

        value = seed + index;

        payload_pattern =
            value[7:0];

    end

endfunction


// ============================================================
// Payload scoreboard
// ============================================================

always @(posedge clk) begin

    if (rst) begin

        payload_count = 0;
        payload_frame_count = 0;

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
                payload_pattern(
                    expected_payload_seed,
                    payload_count
                )
            ) begin

                $display(
                    "ERROR: PAYLOAD BYTE %0d = %02X EXPECTED %02X",
                    payload_count,
                    payload_data,
                    payload_pattern(
                        expected_payload_seed,
                        payload_count
                    )
                );

                error_count =
                    error_count + 1;

            end


            if (
                (payload_count == 0)
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
                (
                    payload_count
                    ==
                    expected_payload_length - 1
                )
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
                payload_count
                ==
                expected_payload_length - 1
            ) begin

                payload_count = 0;

                payload_frame_count =
                    payload_frame_count + 1;

            end
            else begin

                payload_count =
                    payload_count + 1;

            end

        end

    end

end


// ============================================================
// Stream byte driver
//
// Same corrected handshake discipline as M3-B Basic.
// ============================================================

task drive_stream_byte;

    input [7:0]  data;
    input        sof;
    input        eof;
    input [10:0] length;

    begin

        @(negedge clk);

        s_data = data;
        s_valid = 1'b1;

        s_sof = sof;
        s_eof = eof;

        s_frame_length = length;


        @(posedge clk);

        while (s_ready !== 1'b1)
            @(posedge clk);


        @(negedge clk);

        s_valid = 1'b0;
        s_sof = 1'b0;
        s_eof = 1'b0;

    end

endtask


// ============================================================
// Common header-byte generator
//
// Inputs:
//
// total_length:
//   complete IPv4 length
//
// udp_len:
//   complete UDP datagram length
//
// checksum:
//   precomputed IPv4 checksum
//
// payload_len:
//   number of UDP payload bytes
//
// frame_len:
//   Ethernet body length after M3-A FCS removal
//
// seed:
//   payload pattern seed
//
// sequence:
//   final AFDX sequence byte
// ============================================================

task send_profile_frame;

    input integer payload_len;

    input [15:0] total_length;
    input [15:0] udp_len;
    input [15:0] checksum;

    input integer frame_len;
    input integer seed;

    input [7:0] sequence;

    integer i;
    integer payload_index;
    integer payload_end;

    reg [7:0] value;

    begin

        payload_end =
            42 + payload_len;


        for (
            i = 0;
            i < frame_len;
            i = i + 1
        ) begin

            value = 8'h00;


            case (i)

                // =============================================
                // Ethernet
                // =============================================

                0:  value = 8'h02;
                1:  value = 8'h00;
                2:  value = 8'h00;
                3:  value = 8'h00;
                4:  value = 8'h00;
                5:  value = 8'h02;

                6:  value = 8'h02;
                7:  value = 8'h00;
                8:  value = 8'h00;
                9:  value = 8'h00;
                10: value = 8'h00;
                11: value = 8'h01;

                12: value = 8'h08;
                13: value = 8'h00;


                // =============================================
                // IPv4
                // =============================================

                14: value = 8'h45;
                15: value = 8'h00;

                16:
                    value =
                        total_length[15:8];

                17:
                    value =
                        total_length[7:0];

                18: value = 8'h00;
                19: value = 8'h00;

                20: value = 8'h00;
                21: value = 8'h00;

                22: value = 8'h40;
                23: value = 8'h11;

                24:
                    value =
                        checksum[15:8];

                25:
                    value =
                        checksum[7:0];

                26: value = 8'h0A;
                27: value = 8'h00;
                28: value = 8'h00;
                29: value = 8'h01;

                30: value = 8'h0A;
                31: value = 8'h00;
                32: value = 8'h00;
                33: value = 8'h02;


                // =============================================
                // UDP
                // =============================================

                34: value = 8'h27;
                35: value = 8'h10;

                36: value = 8'h27;
                37: value = 8'h11;

                38:
                    value =
                        udp_len[15:8];

                39:
                    value =
                        udp_len[7:0];

                40: value = 8'h00;
                41: value = 8'h00;


                default: begin

                    // -----------------------------------------
                    // UDP payload
                    // -----------------------------------------

                    if (
                        (i >= 42)
                        &&
                        (i < payload_end)
                    ) begin

                        payload_index =
                            i - 42;

                        value =
                            payload_pattern(
                                seed,
                                payload_index
                            );

                    end

                    // -----------------------------------------
                    // Final body byte = AFDX sequence.
                    //
                    // Everything between payload and this byte
                    // remains zero padding.
                    // -----------------------------------------

                    if (
                        i
                        ==
                        frame_len - 1
                    )
                        value = sequence;

                end

            endcase


            drive_stream_byte(
                value,
                (i == 0),
                (i == frame_len - 1),
                frame_len[10:0]
            );

        end

    end

endtask


// ============================================================
// Truncated frame
//
// Sends only bytes 0..last_index but claims full length 60.
// ============================================================

task send_truncated_frame;

    input integer last_index;

    integer i;

    reg [7:0] value;

    begin

        for (
            i = 0;
            i <= last_index;
            i = i + 1
        ) begin

            value = 8'h00;


            case (i)

                0:  value = 8'h02;

                5:  value = 8'h02;

                6:  value = 8'h02;

                11: value = 8'h01;

                12: value = 8'h08;
                13: value = 8'h00;

                14: value = 8'h45;

                16: value = 8'h00;
                17: value = 8'h20;

                22: value = 8'h40;
                23: value = 8'h11;

                24: value = 8'h66;
                25: value = 8'hCB;

                26: value = 8'h0A;
                29: value = 8'h01;

                30: value = 8'h0A;
                33: value = 8'h02;

                34: value = 8'h27;
                35: value = 8'h10;

                36: value = 8'h27;
                37: value = 8'h11;

                38: value = 8'h00;
                39: value = 8'h0C;

                default:
                    value = 8'h00;

            endcase


            drive_stream_byte(
                value,
                (i == 0),
                (i == last_index),
                11'd60
            );

        end

    end

endtask


// ============================================================
// Main test
// ============================================================

integer base_valid;
integer base_done;
integer base_udp_error;
integer base_structure;

integer base_payload_frames;


initial begin

    s_data = 8'd0;
    s_valid = 1'b0;

    s_sof = 1'b0;
    s_eof = 1'b0;

    s_frame_length = 11'd0;


    payload_ready = 1'b1;


    expected_payload_length = 1;
    expected_payload_seed = 0;


    error_count = 0;


    rst = 1'b1;

    repeat (10)
        @(posedge clk);

    @(negedge clk);

    rst = 1'b0;


    // ========================================================
    // TEST 9
    // Minimum AFDX payload:
    //
    // Payload    = 1
    // UDP length = 9
    // IP length  = 29
    // Padding    = 16
    // Body       = 60
    // Checksum   = 66CE
    // ========================================================

    test_error_base =
        error_count;

    expected_payload_length = 1;
    expected_payload_seed = 8'hA0;

    base_valid =
        frame_valid_count;

    base_payload_frames =
        payload_frame_count;


    send_profile_frame(
        1,
        16'h001D,
        16'h0009,
        16'h66CE,
        60,
        8'hA0,
        8'h10
    );


    repeat (5)
        @(posedge clk);


    if (
        frame_valid_count
        !=
        base_valid + 1
    ) begin

        $display(
            "ERROR: 1-BYTE PAYLOAD FRAME NOT ACCEPTED"
        );

        error_count =
            error_count + 1;

    end


    if (
        payload_frame_count
        !=
        base_payload_frames + 1
    )
        error_count =
            error_count + 1;


    if (
        payload_length != 11'd1
    )
        error_count =
            error_count + 1;


    if (
        padding_length != 5'd16
    )
        error_count =
            error_count + 1;


    if (
        afdx_sequence != 8'h10
    )
        error_count =
            error_count + 1;


    if (
        error_count
        ==
        test_error_base
    ) begin

        $display(
            "TEST 9 MIN PAYLOAD / MAX PADDING PASS"
        );

    end
    else begin

        $display(
            "TEST 9 MIN PAYLOAD / MAX PADDING FAIL"
        );

    end


    // ========================================================
    // TEST 10
    //
    // Payload    = 17
    // UDP length = 25
    // IP length  = 45
    // Padding    = 0
    // Body       = 60
    // Checksum   = 66BE
    // ========================================================

    test_error_base =
        error_count;

    expected_payload_length = 17;
    expected_payload_seed = 8'h20;

    base_valid =
        frame_valid_count;

    base_payload_frames =
        payload_frame_count;


    send_profile_frame(
        17,
        16'h002D,
        16'h0019,
        16'h66BE,
        60,
        8'h20,
        8'h11
    );


    repeat (5)
        @(posedge clk);


    if (
        frame_valid_count
        !=
        base_valid + 1
    )
        error_count =
            error_count + 1;


    if (
        payload_frame_count
        !=
        base_payload_frames + 1
    )
        error_count =
            error_count + 1;


    if (
        payload_length != 11'd17
    )
        error_count =
            error_count + 1;


    if (
        padding_length != 5'd0
    )
        error_count =
            error_count + 1;


    if (
        afdx_sequence != 8'h11
    )
        error_count =
            error_count + 1;


    if (
        error_count
        ==
        test_error_base
    ) begin

        $display(
            "TEST 10 ZERO PADDING PROFILE PASS"
        );

    end
    else begin

        $display(
            "TEST 10 ZERO PADDING PROFILE FAIL"
        );

    end


    // ========================================================
    // TEST 11
    // Maximum AFDX payload:
    //
    // Payload    = 1471
    // UDP length = 1479 = 05C7
    // IP length  = 1499 = 05DB
    // Padding    = 0
    // Body       = 1514
    // Checksum   = 6110
    // ========================================================

    test_error_base =
        error_count;

    expected_payload_length = 1471;
    expected_payload_seed = 8'h40;

    base_valid =
        frame_valid_count;

    base_payload_frames =
        payload_frame_count;


    send_profile_frame(
        1471,
        16'h05DB,
        16'h05C7,
        16'h6110,
        1514,
        8'h40,
        8'h12
    );


    repeat (10)
        @(posedge clk);


    if (
        frame_valid_count
        !=
        base_valid + 1
    ) begin

        $display(
            "ERROR: MAXIMUM PAYLOAD FRAME NOT ACCEPTED"
        );

        error_count =
            error_count + 1;

    end


    if (
        payload_frame_count
        !=
        base_payload_frames + 1
    )
        error_count =
            error_count + 1;


    if (
        payload_length != 11'd1471
    )
        error_count =
            error_count + 1;


    if (
        padding_length != 5'd0
    )
        error_count =
            error_count + 1;


    if (
        afdx_sequence != 8'h12
    )
        error_count =
            error_count + 1;


    if (
        error_count
        ==
        test_error_base
    ) begin

        $display(
            "TEST 11 MAXIMUM 1471-BYTE PAYLOAD PASS"
        );

    end
    else begin

        $display(
            "TEST 11 MAXIMUM 1471-BYTE PAYLOAD FAIL"
        );

    end


    // ========================================================
    // TEST 12
    // Padding = 17 -> invalid.
    //
    // Valid 1-byte profile would need body=60.
    // Deliberately use body=61.
    // ========================================================

    test_error_base =
        error_count;

    expected_payload_length = 1;
    expected_payload_seed = 8'hA0;

    base_valid =
        frame_valid_count;

    base_structure =
        structure_error_count;


    send_profile_frame(
        1,
        16'h001D,
        16'h0009,
        16'h66CE,
        61,
        8'hA0,
        8'h20
    );


    repeat (5)
        @(posedge clk);


    if (
        structure_error_count
        !=
        base_structure + 1
    ) begin

        $display(
            "ERROR: PADDING >16 NOT DETECTED"
        );

        error_count =
            error_count + 1;

    end


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
            "TEST 12 EXCESSIVE PADDING DROP PASS"
        );

    end
    else begin

        $display(
            "TEST 12 EXCESSIVE PADDING DROP FAIL"
        );

    end


    // ========================================================
    // TEST 13
    // UDP length = 8.
    //
    // Minimum legal AFDX application payload requires:
    //
    // UDP length >= 9.
    //
    // IP header itself remains checksum-valid.
    // ========================================================

    test_error_base =
        error_count;

    base_valid =
        frame_valid_count;

    base_udp_error =
        udp_length_error_count;


    send_profile_frame(
        1,
        16'h001D,
        16'h0008,
        16'h66CE,
        60,
        8'hA0,
        8'h21
    );


    repeat (5)
        @(posedge clk);


    if (
        udp_length_error_count
        !=
        base_udp_error + 1
    ) begin

        $display(
            "ERROR: UDP LENGTH <9 NOT DETECTED"
        );

        error_count =
            error_count + 1;

    end


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
            "TEST 13 UDP LENGTH BELOW MIN DROP PASS"
        );

    end
    else begin

        $display(
            "TEST 13 UDP LENGTH BELOW MIN DROP FAIL"
        );

    end


    // ========================================================
    // TEST 14
    // UDP length = 1480 > supported maximum 1479.
    //
    // IP length remains valid maximum profile so its
    // checksum remains independently valid.
    // ========================================================

    test_error_base =
        error_count;

    base_valid =
        frame_valid_count;

    base_udp_error =
        udp_length_error_count;


    send_profile_frame(
        1471,
        16'h05DB,
        16'h05C8,
        16'h6110,
        1514,
        8'h40,
        8'h22
    );


    repeat (10)
        @(posedge clk);


    if (
        udp_length_error_count
        !=
        base_udp_error + 1
    ) begin

        $display(
            "ERROR: UDP LENGTH >1479 NOT DETECTED"
        );

        error_count =
            error_count + 1;

    end


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
            "TEST 14 UDP LENGTH ABOVE MAX DROP PASS"
        );

    end
    else begin

        $display(
            "TEST 14 UDP LENGTH ABOVE MAX DROP FAIL"
        );

    end


    // ========================================================
    // TEST 15
    // Truncated inside IPv4 header.
    // ========================================================

    test_error_base =
        error_count;

    base_valid =
        frame_valid_count;

    base_structure =
        structure_error_count;


    send_truncated_frame(
        25
    );


    repeat (5)
        @(posedge clk);


    if (
        structure_error_count
        !=
        base_structure + 1
    ) begin

        $display(
            "ERROR: TRUNCATED IPV4 NOT DETECTED"
        );

        error_count =
            error_count + 1;

    end


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
            "TEST 15 TRUNCATED IPV4 DROP PASS"
        );

    end
    else begin

        $display(
            "TEST 15 TRUNCATED IPV4 DROP FAIL"
        );

    end


    // ========================================================
    // TEST 16
    // Truncated inside UDP header.
    // ========================================================

    test_error_base =
        error_count;

    base_valid =
        frame_valid_count;

    base_structure =
        structure_error_count;


    send_truncated_frame(
        38
    );


    repeat (5)
        @(posedge clk);


    if (
        structure_error_count
        !=
        base_structure + 1
    ) begin

        $display(
            "ERROR: TRUNCATED UDP NOT DETECTED"
        );

        error_count =
            error_count + 1;

    end


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
            "TEST 16 TRUNCATED UDP DROP PASS"
        );

    end
    else begin

        $display(
            "TEST 16 TRUNCATED UDP DROP FAIL"
        );

    end


    // ========================================================
    // Final result
    // ========================================================

    if (error_count == 0) begin

        $display("");
        $display("==============================================");
        $display("M3-B ETH/IP/UDP PARSER EXTENDED TEST PASS");
        $display("1-BYTE MINIMUM PAYLOAD VERIFIED");
        $display("16-BYTE MAXIMUM PADDING VERIFIED");
        $display("ZERO-PADDING PROFILE VERIFIED");
        $display("1471-BYTE MAXIMUM PAYLOAD VERIFIED");
        $display("1514-BYTE MAXIMUM BODY VERIFIED");
        $display("EXCESSIVE PADDING REJECTION VERIFIED");
        $display("UDP MINIMUM LENGTH CHECK VERIFIED");
        $display("UDP MAXIMUM LENGTH CHECK VERIFIED");
        $display("TRUNCATED IPV4 REJECTION VERIFIED");
        $display("TRUNCATED UDP REJECTION VERIFIED");
        $display("==============================================");
        $display("");

    end
    else begin

        $fatal(
            1,
            "M3-B EXTENDED TEST FAIL: %0d ERRORS",
            error_count
        );

    end


    $finish;

end


// ============================================================
// Timeout
// ============================================================

initial begin

    #1000000;

    $fatal(
        1,
        "M3-B EXTENDED FAIL: SIMULATION TIMEOUT"
    );

end


endmodule
