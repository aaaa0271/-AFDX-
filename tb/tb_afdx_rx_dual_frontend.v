`timescale 1ns / 1ps

module tb_afdx_rx_dual_frontend;


// ============================================================
// Frame variants
// ============================================================

localparam integer FRAME_VL0     = 0;
localparam integer FRAME_VL1     = 1;
localparam integer FRAME_UNKNOWN = 2;
localparam integer FRAME_BAD_FCS = 3;


// ============================================================
// Clock / reset
// ============================================================

reg clk;
reg rst;
reg clear;


initial begin

    clk = 1'b0;

    forever #5
        clk = ~clk;

end


// ============================================================
// GMII A
// ============================================================

reg [7:0] gmii_a_rxd;
reg       gmii_a_rx_dv;
reg       gmii_a_rx_er;


// ============================================================
// GMII B
// ============================================================

reg [7:0] gmii_b_rxd;
reg       gmii_b_rx_dv;
reg       gmii_b_rx_er;


// ============================================================
// Final payload
// ============================================================

wire [7:0] payload_data;
wire       payload_valid;
reg        payload_ready;

wire       payload_sof;
wire       payload_eof;
wire       payload_network;


// ============================================================
// D1 events
// ============================================================

wire accept_event;
wire duplicate_event;
wire stale_event;
wire gap_event;


// ============================================================
// Statistics
// ============================================================

wire [31:0] accepted_count;
wire [31:0] accepted_a_count;
wire [31:0] accepted_b_count;

wire [31:0] duplicate_count;

wire [31:0] cross_network_duplicate_count;
wire [31:0] same_network_repeat_count;

wire [31:0] stale_count;
wire [31:0] sequence_gap_count;


// ============================================================
// Debug
// ============================================================

wire a_candidate_valid;
wire a_candidate_outstanding;

wire b_candidate_valid;
wire b_candidate_outstanding;

wire a_l2_crc_error;
wire b_l2_crc_error;

wire a_unknown_vl_error;
wire b_unknown_vl_error;

wire a_commit_overflow_error;
wire b_commit_overflow_error;

wire decision_arb_valid;
wire decision_arb_network;

wire payload_frame_active;


// ============================================================
// DUT
// ============================================================

afdx_rx_dual_frontend dut (
    .rx_cfg_table(672'd0),

    .clk (
        clk
    ),

    .rst (
        rst
    ),

    .clear (
        clear
    ),


    // --------------------------------------------------------
    // GMII A
    // --------------------------------------------------------

    .gmii_a_rxd (
        gmii_a_rxd
    ),

    .gmii_a_rx_dv (
        gmii_a_rx_dv
    ),

    .gmii_a_rx_er (
        gmii_a_rx_er
    ),


    // --------------------------------------------------------
    // GMII B
    // --------------------------------------------------------

    .gmii_b_rxd (
        gmii_b_rxd
    ),

    .gmii_b_rx_dv (
        gmii_b_rx_dv
    ),

    .gmii_b_rx_er (
        gmii_b_rx_er
    ),


    // --------------------------------------------------------
    // Final payload
    // --------------------------------------------------------

    .payload_data (
        payload_data
    ),

    .payload_valid (
        payload_valid
    ),

    .payload_ready (
        payload_ready
    ),

    .payload_sof (
        payload_sof
    ),

    .payload_eof (
        payload_eof
    ),

    .payload_network (
        payload_network
    ),


    // --------------------------------------------------------
    // Events
    // --------------------------------------------------------

    .accept_event (
        accept_event
    ),

    .duplicate_event (
        duplicate_event
    ),

    .stale_event (
        stale_event
    ),

    .gap_event (
        gap_event
    ),


    // --------------------------------------------------------
    // Counters
    // --------------------------------------------------------

    .accepted_count (
        accepted_count
    ),

    .accepted_a_count (
        accepted_a_count
    ),

    .accepted_b_count (
        accepted_b_count
    ),

    .duplicate_count (
        duplicate_count
    ),

    .cross_network_duplicate_count (
        cross_network_duplicate_count
    ),

    .same_network_repeat_count (
        same_network_repeat_count
    ),

    .stale_count (
        stale_count
    ),

    .sequence_gap_count (
        sequence_gap_count
    ),


    // --------------------------------------------------------
    // Parser status
    // --------------------------------------------------------

    .a_candidate_valid (
        a_candidate_valid
    ),

    .a_candidate_outstanding (
        a_candidate_outstanding
    ),

    .b_candidate_valid (
        b_candidate_valid
    ),

    .b_candidate_outstanding (
        b_candidate_outstanding
    ),

    .a_l2_crc_error (
        a_l2_crc_error
    ),

    .b_l2_crc_error (
        b_l2_crc_error
    ),

    .a_unknown_vl_error (
        a_unknown_vl_error
    ),

    .b_unknown_vl_error (
        b_unknown_vl_error
    ),

    .a_commit_overflow_error (
        a_commit_overflow_error
    ),

    .b_commit_overflow_error (
        b_commit_overflow_error
    ),


    // --------------------------------------------------------
    // D2c debug
    // --------------------------------------------------------

    .decision_arb_valid (
        decision_arb_valid
    ),

    .decision_arb_network (
        decision_arb_network
    ),

    .payload_frame_active (
        payload_frame_active
    )

);


// ============================================================
// Test bookkeeping
// ============================================================

integer error_count;
integer tc_error;

integer timeout;
integer i;


// ============================================================
// Ethernet frame storage
// ============================================================

reg [7:0] frame_body [0:1517];

integer frame_body_len;

reg [31:0] built_fcs;


// ============================================================
// Output scoreboard
// ============================================================

integer output_count;

reg [7:0] captured_data [0:1023];

reg captured_sof [0:1023];
reg captured_eof [0:1023];
reg captured_net [0:1023];


// ============================================================
// Error pulse counters
// ============================================================

integer a_crc_error_count;
integer b_crc_error_count;

integer a_unknown_count;
integer b_unknown_count;


// ============================================================
// Final payload capture
// ============================================================

always @(posedge clk) begin

    if (rst) begin

        output_count =
            0;

    end
    else if (
        payload_valid
        &&
        payload_ready
    ) begin

        captured_data[output_count] =
            payload_data;

        captured_sof[output_count] =
            payload_sof;

        captured_eof[output_count] =
            payload_eof;

        captured_net[output_count] =
            payload_network;

        output_count =
            output_count + 1;

    end

end


// ============================================================
// Error pulse capture
// ============================================================

always @(posedge clk) begin

    if (rst) begin

        a_crc_error_count =
            0;

        b_crc_error_count =
            0;

        a_unknown_count =
            0;

        b_unknown_count =
            0;

    end
    else begin

        if (a_l2_crc_error)
            a_crc_error_count =
                a_crc_error_count + 1;

        if (b_l2_crc_error)
            b_crc_error_count =
                b_crc_error_count + 1;

        if (a_unknown_vl_error)
            a_unknown_count =
                a_unknown_count + 1;

        if (b_unknown_vl_error)
            b_unknown_count =
                b_unknown_count + 1;

    end

end


// ============================================================
// Ethernet CRC32
//
// Same reflected CRC used by the existing M5-D2a TB.
//
// Polynomial:
//     0xEDB88320
// ============================================================

function [31:0] crc32_update_byte;

    input [31:0] crc_in;
    input [7:0]  data_in;

    integer bit_index;

    reg [31:0] crc_temp;

    begin

        crc_temp =
            crc_in;


        for (
            bit_index = 0;
            bit_index < 8;
            bit_index = bit_index + 1
        ) begin

            if (
                crc_temp[0]
                ^
                data_in[bit_index]
            )
                crc_temp =
                    (crc_temp >> 1)
                    ^
                    32'hEDB88320;

            else
                crc_temp =
                    crc_temp >> 1;

        end


        crc32_update_byte =
            crc_temp;

    end

endfunction


// ============================================================
// Build one Ethernet/IPv4/UDP/AFDX frame
//
// Payload is exactly 4 bytes.
//
// Ethernet body:
//   Ethernet header
//   IPv4 header
//   UDP header
//   4-byte payload
//   Ethernet padding
//   1-byte AFDX sequence
//
// FCS follows body.
//
// VL0:
//   dst MAC ...:02
//   10.0.0.1 -> 10.0.0.2
//   UDP 10000 -> 10001
//
// VL1:
//   dst MAC ...:03
//   10.0.0.1 -> 10.0.0.3
//   UDP 10000 -> 20001
// ============================================================

task build_frame;

    input integer variant;

    input [7:0] seq;

    input [7:0] p0;
    input [7:0] p1;
    input [7:0] p2;
    input [7:0] p3;


    integer payload_len_local;
    integer padding_len_local;

    integer k;


    reg [7:0] dst_mac_last;

    reg [7:0] src_ip_last;
    reg [7:0] dst_ip_last;

    reg [15:0] udp_dst_local;

    reg [15:0] ip_len_local;
    reg [15:0] udp_len_local;

    reg [31:0] sum32;

    reg [15:0] built_ip_checksum;

    reg [31:0] crc_temp;


    begin

        payload_len_local =
            4;


        // ----------------------------------------------------
        // Default = valid VL0
        // ----------------------------------------------------

        dst_mac_last =
            8'h02;

        src_ip_last =
            8'h01;

        dst_ip_last =
            8'h02;

        udp_dst_local =
            16'd10001;


        // ----------------------------------------------------
        // Variant
        // ----------------------------------------------------

        case (variant)

            FRAME_VL0: begin

                dst_mac_last =
                    8'h02;

                dst_ip_last =
                    8'h02;

                udp_dst_local =
                    16'd10001;

            end


            FRAME_VL1: begin

                dst_mac_last =
                    8'h03;

                dst_ip_last =
                    8'h03;

                udp_dst_local =
                    16'd20001;

            end


            FRAME_UNKNOWN: begin

                dst_mac_last =
                    8'h99;

            end


            FRAME_BAD_FCS: begin

                // Otherwise valid VL0.

            end


            default: begin

                $fatal(
                    1,
                    "Illegal frame variant %0d",
                    variant
                );

            end

        endcase


        // ----------------------------------------------------
        // Lengths
        // ----------------------------------------------------

        udp_len_local =
            16'd8
            +
            payload_len_local;


        ip_len_local =
            16'd20
            +
            udp_len_local;


        // Ethernet minimum body length excluding FCS is 60.
        //
        // AFDX sequence occupies final body byte.

        if (
            (14 + ip_len_local + 1)
            <
            60
        )
            padding_len_local =
                60
                -
                (14 + ip_len_local + 1);

        else
            padding_len_local =
                0;


        frame_body_len =
            14
            +
            ip_len_local
            +
            padding_len_local
            +
            1;


        // ----------------------------------------------------
        // Clear body
        // ----------------------------------------------------

        for (
            k = 0;
            k < frame_body_len;
            k = k + 1
        )
            frame_body[k] =
                8'h00;


        // ====================================================
        // Ethernet
        // ====================================================

        frame_body[0] =
            8'h02;

        frame_body[1] =
            8'h00;

        frame_body[2] =
            8'h00;

        frame_body[3] =
            8'h00;

        frame_body[4] =
            8'h00;

        frame_body[5] =
            dst_mac_last;


        // Source MAC = 02:00:00:00:00:01

        frame_body[6] =
            8'h02;

        frame_body[7] =
            8'h00;

        frame_body[8] =
            8'h00;

        frame_body[9] =
            8'h00;

        frame_body[10] =
            8'h00;

        frame_body[11] =
            8'h01;


        // EtherType IPv4

        frame_body[12] =
            8'h08;

        frame_body[13] =
            8'h00;


        // ====================================================
        // IPv4
        // ====================================================

        // Version=4, IHL=5

        frame_body[14] =
            8'h45;


        frame_body[15] =
            8'h00;


        frame_body[16] =
            ip_len_local[15:8];

        frame_body[17] =
            ip_len_local[7:0];


        // Identification

        frame_body[18] =
            8'h00;

        frame_body[19] =
            8'h00;


        // Flags / fragment offset

        frame_body[20] =
            8'h00;

        frame_body[21] =
            8'h00;


        // TTL

        frame_body[22] =
            8'h40;


        // UDP

        frame_body[23] =
            8'h11;


        // Header checksum initially zero

        frame_body[24] =
            8'h00;

        frame_body[25] =
            8'h00;


        // Source IP 10.0.0.1

        frame_body[26] =
            8'h0A;

        frame_body[27] =
            8'h00;

        frame_body[28] =
            8'h00;

        frame_body[29] =
            src_ip_last;


        // Destination IP

        frame_body[30] =
            8'h0A;

        frame_body[31] =
            8'h00;

        frame_body[32] =
            8'h00;

        frame_body[33] =
            dst_ip_last;


        // ====================================================
        // UDP
        // ====================================================

        // Source port = 10000 = 0x2710

        frame_body[34] =
            8'h27;

        frame_body[35] =
            8'h10;


        frame_body[36] =
            udp_dst_local[15:8];

        frame_body[37] =
            udp_dst_local[7:0];


        frame_body[38] =
            udp_len_local[15:8];

        frame_body[39] =
            udp_len_local[7:0];


        // UDP checksum unused by current parser.

        frame_body[40] =
            8'h00;

        frame_body[41] =
            8'h00;


        // ====================================================
        // Payload
        // ====================================================

        frame_body[42] =
            p0;

        frame_body[43] =
            p1;

        frame_body[44] =
            p2;

        frame_body[45] =
            p3;


        // ====================================================
        // Padding
        // ====================================================

        for (
            k = 46;
            k < frame_body_len - 1;
            k = k + 1
        )
            frame_body[k] =
                8'h00;


        // ====================================================
        // AFDX sequence
        // ====================================================

        frame_body[frame_body_len - 1] =
            seq;


        // ====================================================
        // IPv4 checksum
        // ====================================================

        frame_body[24] =
            8'h00;

        frame_body[25] =
            8'h00;


        sum32 =
            32'd0;


        for (
            k = 14;
            k < 34;
            k = k + 2
        )
            sum32 =
                sum32
                +
                {
                    frame_body[k],
                    frame_body[k+1]
                };


        while (
            sum32[31:16]
            !=
            16'd0
        )
            sum32 =
                {
                    16'd0,
                    sum32[15:0]
                }
                +
                sum32[31:16];


        built_ip_checksum =
            ~sum32[15:0];


        frame_body[24] =
            built_ip_checksum[15:8];

        frame_body[25] =
            built_ip_checksum[7:0];


        // ====================================================
        // Ethernet CRC/FCS
        // ====================================================

        crc_temp =
            32'hFFFFFFFF;


        for (
            k = 0;
            k < frame_body_len;
            k = k + 1
        )
            crc_temp =
                crc32_update_byte(
                    crc_temp,
                    frame_body[k]
                );


        built_fcs =
            crc_temp
            ^
            32'hFFFFFFFF;


        if (
            variant
            ==
            FRAME_BAD_FCS
        )
            built_fcs =
                built_fcs
                ^
                32'h00000001;

    end

endtask


// ============================================================
// GMII A byte
// ============================================================

task send_a_byte;

    input [7:0] byte_value;

    begin

        @(negedge clk);

        gmii_a_rx_dv =
            1'b1;

        gmii_a_rx_er =
            1'b0;

        gmii_a_rxd =
            byte_value;

    end

endtask


// ============================================================
// GMII B byte
// ============================================================

task send_b_byte;

    input [7:0] byte_value;

    begin

        @(negedge clk);

        gmii_b_rx_dv =
            1'b1;

        gmii_b_rx_er =
            1'b0;

        gmii_b_rxd =
            byte_value;

    end

endtask


// ============================================================
// Send frame on network A
// ============================================================

task send_frame_a;

    input integer variant;

    input [7:0] seq;

    input [7:0] p0;
    input [7:0] p1;
    input [7:0] p2;
    input [7:0] p3;

    integer k;

    begin

        build_frame(
            variant,
            seq,
            p0,
            p1,
            p2,
            p3
        );


        // Preamble

        for (
            k = 0;
            k < 7;
            k = k + 1
        )
            send_a_byte(
                8'h55
            );


        // SFD

        send_a_byte(
            8'hD5
        );


        // Ethernet body

        for (
            k = 0;
            k < frame_body_len;
            k = k + 1
        )
            send_a_byte(
                frame_body[k]
            );


        // FCS little-endian on GMII

        send_a_byte(
            built_fcs[7:0]
        );

        send_a_byte(
            built_fcs[15:8]
        );

        send_a_byte(
            built_fcs[23:16]
        );

        send_a_byte(
            built_fcs[31:24]
        );


        @(negedge clk);

        gmii_a_rx_dv =
            1'b0;

        gmii_a_rx_er =
            1'b0;

        gmii_a_rxd =
            8'h00;


        // Give M3-A time to validate and release frame.

        repeat (20)
            @(posedge clk);

    end

endtask


// ============================================================
// Send frame on network B
// ============================================================

task send_frame_b;

    input integer variant;

    input [7:0] seq;

    input [7:0] p0;
    input [7:0] p1;
    input [7:0] p2;
    input [7:0] p3;

    integer k;

    begin

        build_frame(
            variant,
            seq,
            p0,
            p1,
            p2,
            p3
        );


        for (
            k = 0;
            k < 7;
            k = k + 1
        )
            send_b_byte(
                8'h55
            );


        send_b_byte(
            8'hD5
        );


        for (
            k = 0;
            k < frame_body_len;
            k = k + 1
        )
            send_b_byte(
                frame_body[k]
            );


        send_b_byte(
            built_fcs[7:0]
        );

        send_b_byte(
            built_fcs[15:8]
        );

        send_b_byte(
            built_fcs[23:16]
        );

        send_b_byte(
            built_fcs[31:24]
        );


        @(negedge clk);

        gmii_b_rx_dv =
            1'b0;

        gmii_b_rx_er =
            1'b0;

        gmii_b_rxd =
            8'h00;


        repeat (20)
            @(posedge clk);

    end

endtask


// ============================================================
// Reset entire RX path
// ============================================================

task reset_dut;

    begin

        @(negedge clk);


        rst =
            1'b1;

        clear =
            1'b0;


        gmii_a_rxd =
            8'h00;

        gmii_a_rx_dv =
            1'b0;

        gmii_a_rx_er =
            1'b0;


        gmii_b_rxd =
            8'h00;

        gmii_b_rx_dv =
            1'b0;

        gmii_b_rx_er =
            1'b0;


        payload_ready =
            1'b1;


        repeat (5)
            @(posedge clk);


        @(negedge clk);

        rst =
            1'b0;


        repeat (5)
            @(posedge clk);

        #1;

    end

endtask


// ============================================================
// Wait until output_count reaches expected
// ============================================================

task wait_output_count;

    input integer expected;

    integer wait_cycle;

    begin : WAIT_OUTPUT

        for (
            wait_cycle = 0;
            wait_cycle < 5000;
            wait_cycle = wait_cycle + 1
        ) begin

            @(posedge clk);

            #1;


            if (
                output_count
                >=
                expected
            )
                disable WAIT_OUTPUT;

        end


        $display(
            "ERROR: output timeout got=%0d expected=%0d",
            output_count,
            expected
        );

        error_count =
            error_count + 1;

        tc_error =
            tc_error + 1;

    end

endtask


// ============================================================
// Wait until accepted_count reaches expected
// ============================================================

task wait_accepted_count;

    input integer expected;

    integer wait_cycle;

    begin : WAIT_ACCEPT

        for (
            wait_cycle = 0;
            wait_cycle < 5000;
            wait_cycle = wait_cycle + 1
        ) begin

            @(posedge clk);

            #1;


            if (
                accepted_count
                >=
                expected
            )
                disable WAIT_ACCEPT;

        end


        $display(
            "ERROR: accepted_count timeout got=%0d expected=%0d",
            accepted_count,
            expected
        );

        error_count =
            error_count + 1;

        tc_error =
            tc_error + 1;

    end

endtask


// ============================================================
// Wait for all currently accepted payload replay to settle
// ============================================================

task settle;

    begin

        repeat (100)
            @(posedge clk);

        #1;

    end

endtask


// ============================================================
// Check one captured payload byte
// ============================================================

task expect_byte;

    input integer index;

    input expected_network;

    input [7:0] expected_data;

    input expected_sof;
    input expected_eof;

    begin

        if (
            captured_net[index]
            !==
            expected_network
        ) begin

            $display(
                "ERROR output[%0d]: network=%0d expected=%0d",
                index,
                captured_net[index],
                expected_network
            );

            error_count =
                error_count + 1;

            tc_error =
                tc_error + 1;

        end


        if (
            captured_data[index]
            !==
            expected_data
        ) begin

            $display(
                "ERROR output[%0d]: data=%02x expected=%02x",
                index,
                captured_data[index],
                expected_data
            );

            error_count =
                error_count + 1;

            tc_error =
                tc_error + 1;

        end


        if (
            captured_sof[index]
            !==
            expected_sof
        ) begin

            $display(
                "ERROR output[%0d]: SOF=%0d expected=%0d",
                index,
                captured_sof[index],
                expected_sof
            );

            error_count =
                error_count + 1;

            tc_error =
                tc_error + 1;

        end


        if (
            captured_eof[index]
            !==
            expected_eof
        ) begin

            $display(
                "ERROR output[%0d]: EOF=%0d expected=%0d",
                index,
                captured_eof[index],
                expected_eof
            );

            error_count =
                error_count + 1;

            tc_error =
                tc_error + 1;

        end

    end

endtask


// ============================================================
// Check a complete 4-byte payload frame
// ============================================================

task expect_frame4;

    input integer base;

    input expected_network;

    input [7:0] p0;
    input [7:0] p1;
    input [7:0] p2;
    input [7:0] p3;

    begin

        expect_byte(
            base + 0,
            expected_network,
            p0,
            1'b1,
            1'b0
        );


        expect_byte(
            base + 1,
            expected_network,
            p1,
            1'b0,
            1'b0
        );


        expect_byte(
            base + 2,
            expected_network,
            p2,
            1'b0,
            1'b0
        );


        expect_byte(
            base + 3,
            expected_network,
            p3,
            1'b0,
            1'b1
        );

    end

endtask


// ============================================================
// Assert no unexpected additional payload
// ============================================================

task expect_no_more_output;

    input integer expected_count;

    begin

        repeat (80)
            @(posedge clk);

        #1;


        if (
            output_count
            !=
            expected_count
        ) begin

            $display(
                "ERROR: unexpected payload output count=%0d expected=%0d",
                output_count,
                expected_count
            );

            error_count =
                error_count + 1;

            tc_error =
                tc_error + 1;

        end

    end

endtask


// ============================================================
// Main regression
// ============================================================

initial begin

    // --------------------------------------------------------
    // Initial values
    // --------------------------------------------------------

    rst =
        1'b1;

    clear =
        1'b0;


    gmii_a_rxd =
        8'h00;

    gmii_a_rx_dv =
        1'b0;

    gmii_a_rx_er =
        1'b0;


    gmii_b_rxd =
        8'h00;

    gmii_b_rx_dv =
        1'b0;

    gmii_b_rx_er =
        1'b0;


    payload_ready =
        1'b1;


    error_count =
        0;

    tc_error =
        0;


    $display("");

    $display(
        "======================================================"
    );

    $display(
        "M5-D2c3 FINAL DUAL RX END-TO-END REGRESSION"
    );

    $display(
        "======================================================"
    );

    $display("");


    // ========================================================
    // TC-01
    // Reset / idle
    // ========================================================

    reset_dut();

    tc_error =
        0;


    if (
        payload_valid
        !==
        1'b0
    ) begin

        $display(
            "ERROR: payload_valid after reset"
        );

        error_count =
            error_count + 1;

        tc_error =
            tc_error + 1;

    end


    if (
        accepted_count
        !==
        32'd0
    ) begin

        $display(
            "ERROR: accepted_count after reset = %0d",
            accepted_count
        );

        error_count =
            error_count + 1;

        tc_error =
            tc_error + 1;

    end


    if (
        duplicate_count
        !==
        32'd0
    ) begin

        $display(
            "ERROR: duplicate_count after reset"
        );

        error_count =
            error_count + 1;

        tc_error =
            tc_error + 1;

    end


    if (
        stale_count
        !==
        32'd0
    ) begin

        $display(
            "ERROR: stale_count after reset"
        );

        error_count =
            error_count + 1;

        tc_error =
            tc_error + 1;

    end


    if (
        tc_error
        ==
        0
    )
        $display(
            "TC-M5-D2c3-01 PASS: reset / idle"
        );
    else
        $display(
            "TC-M5-D2c3-01 FAIL"
        );


    // ========================================================
    // TC-02
    // A-only valid frame
    //
    // GMII -> L2 -> IPv4/UDP -> VL0 -> D1 accept
    //      -> A commit replay -> final output
    // ========================================================

    reset_dut();

    tc_error =
        0;


    send_frame_a(
        FRAME_VL0,
        8'h10,
        8'hA1,
        8'hA2,
        8'hA3,
        8'hA4
    );


    wait_output_count(
        4
    );


    expect_frame4(
        0,
        1'b0,
        8'hA1,
        8'hA2,
        8'hA3,
        8'hA4
    );


    if (
        accepted_count
        !==
        32'd1
    ) begin

        $display(
            "ERROR: accepted_count=%0d expected=1",
            accepted_count
        );

        error_count =
            error_count + 1;

        tc_error =
            tc_error + 1;

    end


    if (
        accepted_a_count
        !==
        32'd1
    ) begin

        $display(
            "ERROR: accepted_a_count=%0d expected=1",
            accepted_a_count
        );

        error_count =
            error_count + 1;

        tc_error =
            tc_error + 1;

    end


    if (
        tc_error
        ==
        0
    )
        $display(
            "TC-M5-D2c3-02 PASS: A GMII -> accepted A payload"
        );
    else
        $display(
            "TC-M5-D2c3-02 FAIL"
        );


    // ========================================================
    // TC-03
    // Cross-network duplicate
    //
    // A seq10 first -> accepted
    // B seq10 later -> cross-network duplicate
    //
    // Only A payload may appear.
    // ========================================================

    reset_dut();

    tc_error =
        0;


    send_frame_a(
        FRAME_VL0,
        8'h10,
        8'h11,
        8'h12,
        8'h13,
        8'h14
    );


    wait_output_count(
        4
    );


    send_frame_b(
        FRAME_VL0,
        8'h10,
        8'h21,
        8'h22,
        8'h23,
        8'h24
    );


    expect_no_more_output(
        4
    );


    expect_frame4(
        0,
        1'b0,
        8'h11,
        8'h12,
        8'h13,
        8'h14
    );


    if (
        accepted_count
        !==
        32'd1
    ) begin

        $display(
            "ERROR: accepted_count=%0d expected=1",
            accepted_count
        );

        error_count =
            error_count + 1;

        tc_error =
            tc_error + 1;

    end


    if (
        cross_network_duplicate_count
        !==
        32'd1
    ) begin

        $display(
            "ERROR: cross_network_duplicate_count=%0d expected=1",
            cross_network_duplicate_count
        );

        error_count =
            error_count + 1;

        tc_error =
            tc_error + 1;

    end


    if (
        duplicate_count
        !==
        32'd1
    ) begin

        $display(
            "ERROR: duplicate_count=%0d expected=1",
            duplicate_count
        );

        error_count =
            error_count + 1;

        tc_error =
            tc_error + 1;

    end


    if (
        tc_error
        ==
        0
    )
        $display(
            "TC-M5-D2c3-03 PASS: cross-network duplicate eliminated"
        );
    else
        $display(
            "TC-M5-D2c3-03 FAIL"
        );


    // ========================================================
    // TC-04
    // First-valid-wins in opposite direction
    //
    // B first -> accepted
    // A same sequence later -> duplicate
    //
    // Proves implementation is NOT always-prefer-A.
    // ========================================================

    reset_dut();

    tc_error =
        0;


    send_frame_b(
        FRAME_VL0,
        8'h20,
        8'hB1,
        8'hB2,
        8'hB3,
        8'hB4
    );


    wait_output_count(
        4
    );


    send_frame_a(
        FRAME_VL0,
        8'h20,
        8'hA1,
        8'hA2,
        8'hA3,
        8'hA4
    );


    expect_no_more_output(
        4
    );


    expect_frame4(
        0,
        1'b1,
        8'hB1,
        8'hB2,
        8'hB3,
        8'hB4
    );


    if (
        accepted_b_count
        !==
        32'd1
    ) begin

        $display(
            "ERROR: accepted_b_count=%0d expected=1",
            accepted_b_count
        );

        error_count =
            error_count + 1;

        tc_error =
            tc_error + 1;

    end


    if (
        cross_network_duplicate_count
        !==
        32'd1
    ) begin

        $display(
            "ERROR: opposite-direction duplicate count=%0d",
            cross_network_duplicate_count
        );

        error_count =
            error_count + 1;

        tc_error =
            tc_error + 1;

    end


    if (
        tc_error
        ==
        0
    )
        $display(
            "TC-M5-D2c3-04 PASS: B-first proves first-valid-wins"
        );
    else
        $display(
            "TC-M5-D2c3-04 FAIL"
        );


    // ========================================================
    // TC-05
    // Same-network repeat
    // ========================================================

    reset_dut();

    tc_error =
        0;


    send_frame_b(
        FRAME_VL0,
        8'h31,
        8'h31,
        8'h32,
        8'h33,
        8'h34
    );


    wait_output_count(
        4
    );


    send_frame_b(
        FRAME_VL0,
        8'h31,
        8'h41,
        8'h42,
        8'h43,
        8'h44
    );


    expect_no_more_output(
        4
    );


    if (
        same_network_repeat_count
        !==
        32'd1
    ) begin

        $display(
            "ERROR: same_network_repeat_count=%0d expected=1",
            same_network_repeat_count
        );

        error_count =
            error_count + 1;

        tc_error =
            tc_error + 1;

    end


    if (
        duplicate_count
        !==
        32'd1
    ) begin

        $display(
            "ERROR: duplicate_count=%0d expected=1",
            duplicate_count
        );

        error_count =
            error_count + 1;

        tc_error =
            tc_error + 1;

    end


    if (
        tc_error
        ==
        0
    )
        $display(
            "TC-M5-D2c3-05 PASS: same-network repeat eliminated"
        );
    else
        $display(
            "TC-M5-D2c3-05 FAIL"
        );


    // ========================================================
    // TC-06
    // Stale sequence
    //
    // B seq11 accepted
    // A seq10 is old -> stale
    // ========================================================

    reset_dut();

    tc_error =
        0;


    send_frame_b(
        FRAME_VL0,
        8'h11,
        8'h51,
        8'h52,
        8'h53,
        8'h54
    );


    wait_output_count(
        4
    );


    send_frame_a(
        FRAME_VL0,
        8'h10,
        8'h61,
        8'h62,
        8'h63,
        8'h64
    );


    expect_no_more_output(
        4
    );


    if (
        stale_count
        !==
        32'd1
    ) begin

        $display(
            "ERROR: stale_count=%0d expected=1",
            stale_count
        );

        error_count =
            error_count + 1;

        tc_error =
            tc_error + 1;

    end


    if (
        accepted_count
        !==
        32'd1
    ) begin

        $display(
            "ERROR: stale test accepted_count=%0d expected=1",
            accepted_count
        );

        error_count =
            error_count + 1;

        tc_error =
            tc_error + 1;

    end


    if (
        tc_error
        ==
        0
    )
        $display(
            "TC-M5-D2c3-06 PASS: stale physical copy discarded"
        );
    else
        $display(
            "TC-M5-D2c3-06 FAIL"
        );


    // ========================================================
    // TC-07
    // Sequence wrap 255 -> 0
    // ========================================================

    reset_dut();

    tc_error =
        0;


    send_frame_a(
        FRAME_VL0,
        8'hFF,
        8'h71,
        8'h72,
        8'h73,
        8'h74
    );


    wait_output_count(
        4
    );


    send_frame_b(
        FRAME_VL0,
        8'h00,
        8'h81,
        8'h82,
        8'h83,
        8'h84
    );


    wait_output_count(
        8
    );


    expect_frame4(
        0,
        1'b0,
        8'h71,
        8'h72,
        8'h73,
        8'h74
    );


    expect_frame4(
        4,
        1'b1,
        8'h81,
        8'h82,
        8'h83,
        8'h84
    );


    if (
        accepted_count
        !==
        32'd2
    ) begin

        $display(
            "ERROR: wrap accepted_count=%0d expected=2",
            accepted_count
        );

        error_count =
            error_count + 1;

        tc_error =
            tc_error + 1;

    end


    if (
        stale_count
        !==
        32'd0
    ) begin

        $display(
            "ERROR: 255->0 incorrectly stale"
        );

        error_count =
            error_count + 1;

        tc_error =
            tc_error + 1;

    end


    if (
        tc_error
        ==
        0
    )
        $display(
            "TC-M5-D2c3-07 PASS: 255->0 wrap accepted"
        );
    else
        $display(
            "TC-M5-D2c3-07 FAIL"
        );


    // ========================================================
    // TC-08
    // Sequence gap
    //
    // 10 -> 13
    //
    // Missing:
    //   11
    //   12
    //
    // sequence_gap_count must increment by 2.
    // Frame 13 itself is ACCEPTED.
    // ========================================================

    reset_dut();

    tc_error =
        0;


    send_frame_a(
        FRAME_VL0,
        8'd10,
        8'h91,
        8'h92,
        8'h93,
        8'h94
    );


    wait_output_count(
        4
    );


    send_frame_b(
        FRAME_VL0,
        8'd13,
        8'hA1,
        8'hA2,
        8'hA3,
        8'hA4
    );


    wait_output_count(
        8
    );


    if (
        accepted_count
        !==
        32'd2
    ) begin

        $display(
            "ERROR: gap frame was not accepted"
        );

        error_count =
            error_count + 1;

        tc_error =
            tc_error + 1;

    end


    if (
        sequence_gap_count
        !==
        32'd2
    ) begin

        $display(
            "ERROR: sequence_gap_count=%0d expected=2",
            sequence_gap_count
        );

        error_count =
            error_count + 1;

        tc_error =
            tc_error + 1;

    end


    expect_frame4(
        4,
        1'b1,
        8'hA1,
        8'hA2,
        8'hA3,
        8'hA4
    );


    if (
        tc_error
        ==
        0
    )
        $display(
            "TC-M5-D2c3-08 PASS: sequence gap counted and frame accepted"
        );
    else
        $display(
            "TC-M5-D2c3-08 FAIL"
        );


    // ========================================================
    // TC-09
    // Per-VL isolation
    //
    // VL0 seq50
    // VL1 seq50
    //
    // Same sequence number but different VL.
    // Both MUST be accepted.
    // ========================================================

    reset_dut();

    tc_error =
        0;


    send_frame_a(
        FRAME_VL0,
        8'h50,
        8'hC1,
        8'hC2,
        8'hC3,
        8'hC4
    );


    wait_output_count(
        4
    );


    send_frame_b(
        FRAME_VL1,
        8'h50,
        8'hD1,
        8'hD2,
        8'hD3,
        8'hD4
    );


    wait_output_count(
        8
    );


    expect_frame4(
        0,
        1'b0,
        8'hC1,
        8'hC2,
        8'hC3,
        8'hC4
    );


    expect_frame4(
        4,
        1'b1,
        8'hD1,
        8'hD2,
        8'hD3,
        8'hD4
    );


    if (
        accepted_count
        !==
        32'd2
    ) begin

        $display(
            "ERROR: per-VL accepted_count=%0d expected=2",
            accepted_count
        );

        error_count =
            error_count + 1;

        tc_error =
            tc_error + 1;

    end


    if (
        duplicate_count
        !==
        32'd0
    ) begin

        $display(
            "ERROR: different VL incorrectly classified duplicate"
        );

        error_count =
            error_count + 1;

        tc_error =
            tc_error + 1;

    end


    if (
        tc_error
        ==
        0
    )
        $display(
            "TC-M5-D2c3-09 PASS: per-VL sequence state isolated"
        );
    else
        $display(
            "TC-M5-D2c3-09 FAIL"
        );


    // ========================================================
    // TC-10
    // Local rejection before D1
    //
    // A = bad FCS
    // B = unknown VL
    //
    // Neither may modify D1 history or produce payload.
    // ========================================================

    reset_dut();

    tc_error =
        0;


    send_frame_a(
        FRAME_BAD_FCS,
        8'h60,
        8'hE1,
        8'hE2,
        8'hE3,
        8'hE4
    );


    send_frame_b(
        FRAME_UNKNOWN,
        8'h61,
        8'hF1,
        8'hF2,
        8'hF3,
        8'hF4
    );


    settle();


    if (
        output_count
        !==
        0
    ) begin

        $display(
            "ERROR: invalid frame produced final payload"
        );

        error_count =
            error_count + 1;

        tc_error =
            tc_error + 1;

    end


    if (
        accepted_count
        !==
        32'd0
    ) begin

        $display(
            "ERROR: local reject polluted D1 accepted_count=%0d",
            accepted_count
        );

        error_count =
            error_count + 1;

        tc_error =
            tc_error + 1;

    end


    if (
        duplicate_count
        !==
        32'd0
    ) begin

        $display(
            "ERROR: local reject polluted duplicate history"
        );

        error_count =
            error_count + 1;

        tc_error =
            tc_error + 1;

    end


    if (
        stale_count
        !==
        32'd0
    ) begin

        $display(
            "ERROR: local reject polluted stale history"
        );

        error_count =
            error_count + 1;

        tc_error =
            tc_error + 1;

    end


    if (
        a_crc_error_count
        < 1
    ) begin

        $display(
            "ERROR: bad FCS did not raise A CRC error"
        );

        error_count =
            error_count + 1;

        tc_error =
            tc_error + 1;

    end


    if (
        b_unknown_count
        < 1
    ) begin

        $display(
            "ERROR: unknown VL did not raise B unknown error"
        );

        error_count =
            error_count + 1;

        tc_error =
            tc_error + 1;

    end


    if (
        tc_error
        ==
        0
    )
        $display(
            "TC-M5-D2c3-10 PASS: L2/VL local reject does not pollute D1"
        );
    else
        $display(
            "TC-M5-D2c3-10 FAIL"
        );


    // ========================================================
    // TC-11
    // Final output backpressure + dual replay arbitration
    //
    // Hold final application ready LOW.
    //
    // A seq70 accepted.
    // B seq71 accepted.
    //
    // Both commit buffers eventually have accepted payload
    // available, but D2c2 must:
    //
    //   - hold data stable during stall
    //   - output one complete frame
    //   - only then output the other frame
    //
    // Reset D2c2 round-robin state means first simultaneous
    // payload arbitration prefers A.
    // ========================================================

    reset_dut();

    tc_error =
        0;


    @(negedge clk);

    payload_ready =
        1'b0;


    // A accepted but replay stalls at output.

    send_frame_a(
        FRAME_VL0,
        8'h70,
        8'h01,
        8'h02,
        8'h03,
        8'h04
    );


    // B is newer, therefore also accepted.

    send_frame_b(
        FRAME_VL0,
        8'h71,
        8'h11,
        8'h12,
        8'h13,
        8'h14
    );


    // Give both decision paths time to settle.

    repeat (80)
        @(posedge clk);

    #1;


    if (
        accepted_count
        !==
        32'd2
    ) begin

        $display(
            "ERROR: stalled dual replay accepted_count=%0d expected=2",
            accepted_count
        );

        error_count =
            error_count + 1;

        tc_error =
            tc_error + 1;

    end


    if (
        output_count
        !==
        0
    ) begin

        $display(
            "ERROR: payload transferred while payload_ready=0"
        );

        error_count =
            error_count + 1;

        tc_error =
            tc_error + 1;

    end


    if (
        payload_valid
        !==
        1'b1
    ) begin

        $display(
            "ERROR: no payload held during output stall"
        );

        error_count =
            error_count + 1;

        tc_error =
            tc_error + 1;

    end


    // First arbitration after reset should select A.

    if (
        payload_network
        !==
        1'b0
    ) begin

        $display(
            "ERROR: first stalled payload source expected A"
        );

        error_count =
            error_count + 1;

        tc_error =
            tc_error + 1;

    end


    if (
        payload_data
        !==
        8'h01
    ) begin

        $display(
            "ERROR: stalled first payload byte=%02x expected=01",
            payload_data
        );

        error_count =
            error_count + 1;

        tc_error =
            tc_error + 1;

    end


    // Check stability while still stalled.

    repeat (8) begin

        @(posedge clk);

        #1;


        if (
            payload_valid
            !==
            1'b1
        ) begin

            $display(
                "ERROR: payload_valid dropped during stall"
            );

            error_count =
                error_count + 1;

            tc_error =
                tc_error + 1;

        end


        if (
            payload_network
            !==
            1'b0
        ) begin

            $display(
                "ERROR: payload source changed during stall"
            );

            error_count =
                error_count + 1;

            tc_error =
                tc_error + 1;

        end


        if (
            payload_data
            !==
            8'h01
        ) begin

            $display(
                "ERROR: payload_data changed during stall"
            );

            error_count =
                error_count + 1;

            tc_error =
                tc_error + 1;

        end

    end


    // Release application.

    @(negedge clk);

    payload_ready =
        1'b1;


    wait_output_count(
        8
    );


    // A must be one complete frame.

    expect_frame4(
        0,
        1'b0,
        8'h01,
        8'h02,
        8'h03,
        8'h04
    );


    // Then B must be one complete frame.

    expect_frame4(
        4,
        1'b1,
        8'h11,
        8'h12,
        8'h13,
        8'h14
    );


    if (
        a_commit_overflow_error
        !==
        1'b0
    ) begin

        $display(
            "ERROR: A commit buffer overflow"
        );

        error_count =
            error_count + 1;

        tc_error =
            tc_error + 1;

    end


    if (
        b_commit_overflow_error
        !==
        1'b0
    ) begin

        $display(
            "ERROR: B commit buffer overflow"
        );

        error_count =
            error_count + 1;

        tc_error =
            tc_error + 1;

    end


    if (
        tc_error
        ==
        0
    )
        $display(
            "TC-M5-D2c3-11 PASS: backpressure + frame-atomic dual replay"
        );
    else
        $display(
            "TC-M5-D2c3-11 FAIL"
        );


    // ========================================================
    // TC-12
    // Same-network serialization stress
    //
    // Hold final output stalled.
    //
    // Send two valid A frames back-to-back at GMII level:
    //   A seq80
    //   A seq81
    //
    // D2a has only one commit slot.
    //
    // The second validated Ethernet frame may wait inside
    // gmii_rx_adapter, but it must NOT overwrite the first
    // candidate/commit context.
    //
    // After output is released:
    //   frame 80 payload first
    //   frame 81 payload second
    // ========================================================

    reset_dut();

    tc_error =
        0;


    @(negedge clk);

    payload_ready =
        1'b0;


    send_frame_a(
        FRAME_VL0,
        8'h80,
        8'h21,
        8'h22,
        8'h23,
        8'h24
    );


    // First frame should already be accepted and replay-stalled.
    //
    // Send second physical frame immediately on same network.
    // gmii_rx_adapter may buffer it while D2a ingress is closed.

    send_frame_a(
        FRAME_VL0,
        8'h81,
        8'h31,
        8'h32,
        8'h33,
        8'h34
    );


    repeat (80)
        @(posedge clk);

    #1;


    // Before release, only first candidate should have reached
    // D1. The second must still be serialized behind replay.

    if (
        accepted_count
        !==
        32'd1
    ) begin

        $display(
            "ERROR: serialization failed before release accepted_count=%0d expected=1",
            accepted_count
        );

        error_count =
            error_count + 1;

        tc_error =
            tc_error + 1;

    end


    if (
        output_count
        !==
        0
    ) begin

        $display(
            "ERROR: serialized test transferred while stalled"
        );

        error_count =
            error_count + 1;

        tc_error =
            tc_error + 1;

    end


    // Release first replay.

    @(negedge clk);

    payload_ready =
        1'b1;


    // First frame drains, D2a returns to free ingress,
    // second frame may now progress to parser/D1/replay.

    wait_output_count(
        8
    );


    expect_frame4(
        0,
        1'b0,
        8'h21,
        8'h22,
        8'h23,
        8'h24
    );


    expect_frame4(
        4,
        1'b0,
        8'h31,
        8'h32,
        8'h33,
        8'h34
    );


    if (
        accepted_count
        !==
        32'd2
    ) begin

        $display(
            "ERROR: serialization final accepted_count=%0d expected=2",
            accepted_count
        );

        error_count =
            error_count + 1;

        tc_error =
            tc_error + 1;

    end


    if (
        duplicate_count
        !==
        32'd0
    ) begin

        $display(
            "ERROR: serialized newer frame classified duplicate"
        );

        error_count =
            error_count + 1;

        tc_error =
            tc_error + 1;

    end


    if (
        stale_count
        !==
        32'd0
    ) begin

        $display(
            "ERROR: serialized newer frame classified stale"
        );

        error_count =
            error_count + 1;

        tc_error =
            tc_error + 1;

    end


    if (
        tc_error
        ==
        0
    )
        $display(
            "TC-M5-D2c3-12 PASS: same-network ingress serialization"
        );
    else
        $display(
            "TC-M5-D2c3-12 FAIL"
        );


    // ========================================================
    // FINAL
    // ========================================================

    $display("");

    $display(
        "======================================================"
    );


    if (
        error_count
        ==
        0
    ) begin

        $display(
            "M5-D2c3 ALL TESTS PASS"
        );

        $display(
            "M5 FINAL RX REDUNDANCY PATH PASS"
        );

        $display(
            "M5 ALL REGRESSION TESTS PASS"
        );

    end
    else begin

        $display(
            "M5-D2c3 FAILED: %0d error(s)",
            error_count
        );

        $fatal(
            1,
            "M5 FINAL REGRESSION FAILED"
        );

    end


    $display(
        "======================================================"
    );


    #100;

    $finish;

end


// ============================================================
// Global watchdog
// ============================================================

initial begin

    #2000000;

    $fatal(
        1,
        "M5-D2c3 GLOBAL TIMEOUT"
    );

end


endmodule
