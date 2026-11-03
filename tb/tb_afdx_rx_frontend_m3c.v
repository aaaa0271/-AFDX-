`timescale 1ns / 1ps

module tb_afdx_rx_frontend_m3c;


// ============================================================
// Test variants
// ============================================================

localparam integer CASE_VALID_VL0  = 0;
localparam integer CASE_VALID_VL1  = 1;
localparam integer CASE_UNKNOWN    = 2;
localparam integer CASE_BAD_IP     = 3;
localparam integer CASE_BAD_UDP    = 4;
localparam integer CASE_LMAX       = 5;
localparam integer CASE_DISABLED   = 6;
localparam integer CASE_BAD_FCS    = 7;
localparam integer CASE_BAD_IPCHK  = 8;


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
// GMII
// ============================================================

reg [7:0] gmii_rxd;
reg       gmii_rx_dv;
reg       gmii_rx_er;

reg       payload_ready;


// ============================================================
// Useful DUT signals
// ============================================================

wire [47:0] dst_mac;

wire [31:0] src_ip;
wire [31:0] dst_ip;

wire [15:0] udp_dst_port;

wire [10:0] payload_length;

wire [15:0] ip_header_checksum;

wire        meta_valid;


// M3-A
wire        l2_good_frame;
wire        l2_crc_error;


// M3-B
wire        ip_checksum_error;


// M3-C
wire        vl_result_valid;

wire        vl_accept;
wire        vl_reject;

wire [1:0]  vl_index;
wire [15:0] vl_id;
wire [10:0] vl_lmax;

wire unknown_vl_error;
wire disabled_vl_error;

wire ip_whitelist_error;
wire udp_whitelist_error;
wire length_whitelist_error;


// ============================================================
// DUT
// ============================================================

afdx_rx_frontend dut (

    .clk                    (clk),
    .rst                    (rst),

    .gmii_rxd               (gmii_rxd),
    .gmii_rx_dv             (gmii_rx_dv),
    .gmii_rx_er             (gmii_rx_er),

    .dst_mac                (dst_mac),

    .src_ip                 (src_ip),
    .dst_ip                 (dst_ip),

    .ip_header_checksum     (ip_header_checksum),

    .udp_dst_port           (udp_dst_port),

    .payload_length         (payload_length),

    .meta_valid             (meta_valid),

    .payload_ready          (payload_ready),

    .l2_good_frame          (l2_good_frame),
    .l2_crc_error           (l2_crc_error),

    .ip_checksum_error      (ip_checksum_error),

    .vl_result_valid        (vl_result_valid),

    .vl_accept              (vl_accept),
    .vl_reject              (vl_reject),

    .vl_index               (vl_index),
    .vl_id                  (vl_id),
    .vl_lmax                (vl_lmax),

    .unknown_vl_error       (unknown_vl_error),
    .disabled_vl_error      (disabled_vl_error),

    .ip_whitelist_error     (ip_whitelist_error),
    .udp_whitelist_error    (udp_whitelist_error),

    .length_whitelist_error (
        length_whitelist_error
    )

);


// ============================================================
// Counters / captured result
// ============================================================

integer error_count;

integer vl_event_count;
integer l2_good_count;
integer l2_crc_error_count;
integer meta_count;
integer ip_checksum_error_count;


reg        cap_accept;
reg        cap_reject;

reg [1:0]  cap_vl_index;
reg [15:0] cap_vl_id;
reg [10:0] cap_vl_lmax;

reg        cap_unknown;
reg        cap_disabled;
reg        cap_ip;
reg        cap_udp;
reg        cap_length;


// ============================================================
// Monitor
// ============================================================

always @(posedge clk) begin

    if (rst) begin

        vl_event_count          = 0;

        l2_good_count           = 0;
        l2_crc_error_count      = 0;

        meta_count              = 0;

        ip_checksum_error_count = 0;

        cap_accept   = 1'b0;
        cap_reject   = 1'b0;

        cap_vl_index = 2'd0;
        cap_vl_id    = 16'd0;
        cap_vl_lmax  = 11'd0;

        cap_unknown  = 1'b0;
        cap_disabled = 1'b0;
        cap_ip       = 1'b0;
        cap_udp      = 1'b0;
        cap_length   = 1'b0;

    end
    else begin

        if (l2_good_frame)
            l2_good_count =
                l2_good_count + 1;

        if (l2_crc_error)
            l2_crc_error_count =
                l2_crc_error_count + 1;

        if (meta_valid)
            meta_count =
                meta_count + 1;

        if (ip_checksum_error)
            ip_checksum_error_count =
                ip_checksum_error_count + 1;


        if (vl_result_valid) begin

            vl_event_count =
                vl_event_count + 1;

            cap_accept =
                vl_accept;

            cap_reject =
                vl_reject;

            cap_vl_index =
                vl_index;

            cap_vl_id =
                vl_id;

            cap_vl_lmax =
                vl_lmax;

            cap_unknown =
                unknown_vl_error;

            cap_disabled =
                disabled_vl_error;

            cap_ip =
                ip_whitelist_error;

            cap_udp =
                udp_whitelist_error;

            cap_length =
                length_whitelist_error;

        end

    end

end


// ============================================================
// Frame storage
//
// Maximum used here is only ~300 bytes, but allocate enough
// room for a normal Ethernet frame.
// ============================================================

reg [7:0] frame_body [0:1517];

integer frame_body_len;

reg [15:0] built_ip_checksum;
reg [31:0] built_fcs;


// ============================================================
// Ethernet CRC32
// ============================================================

function [31:0] crc32_update_byte;

    input [31:0] crc_in;
    input [7:0]  data_in;

    integer bit_index;

    reg [31:0] crc_temp;

    begin

        crc_temp = crc_in;

        for (
            bit_index = 0;
            bit_index < 8;
            bit_index = bit_index + 1
        ) begin

            if (
                crc_temp[0]
                ^
                data_in[bit_index]
            ) begin

                crc_temp =
                    (crc_temp >> 1)
                    ^
                    32'hEDB88320;

            end
            else begin

                crc_temp =
                    crc_temp >> 1;

            end

        end

        crc32_update_byte =
            crc_temp;

    end

endfunction


// ============================================================
// Build test frame
//
// Layout:
//   0..13          Ethernet
//   14..33         IPv4
//   34..41         UDP
//   42..           UDP payload
//   padding
//   final byte     AFDX sequence
//
// FCS is generated separately.
// ============================================================

task build_frame;

    input integer variant;

    integer i;

    integer payload_len_local;
    integer padding_len_local;

    reg [7:0] dst_mac_last;
    reg [7:0] src_ip_last;
    reg [7:0] dst_ip_last;

    reg [15:0] udp_dst_local;

    reg [15:0] ip_len_local;
    reg [15:0] udp_len_local;

    reg [31:0] sum32;
    reg [31:0] crc_temp;

    begin

        // ----------------------------------------------------
        // Default = valid VL0
        // ----------------------------------------------------

        payload_len_local = 4;

        dst_mac_last = 8'h02;

        src_ip_last = 8'h01;
        dst_ip_last = 8'h02;

        udp_dst_local = 16'd10001;


        // ----------------------------------------------------
        // Variant configuration
        // ----------------------------------------------------

        case (variant)

            CASE_VALID_VL0: begin
            end


            CASE_VALID_VL1: begin

                dst_mac_last =
                    8'h03;

                dst_ip_last =
                    8'h03;

                udp_dst_local =
                    16'd20001;

            end


            CASE_UNKNOWN: begin

                dst_mac_last =
                    8'h99;

            end


            CASE_BAD_IP: begin

                src_ip_last =
                    8'h63;       // 10.0.0.99

            end


            CASE_BAD_UDP: begin

                udp_dst_local =
                    16'd12345;

            end


            // VL1 has LMAX=256.
            // Send 257-byte UDP payload.
            CASE_LMAX: begin

                dst_mac_last =
                    8'h03;

                dst_ip_last =
                    8'h03;

                udp_dst_local =
                    16'd20001;

                payload_len_local =
                    257;

            end


            CASE_DISABLED: begin

                dst_mac_last =
                    8'h04;

                dst_ip_last =
                    8'h04;

                udp_dst_local =
                    16'd30001;

            end


            CASE_BAD_FCS: begin
            end


            CASE_BAD_IPCHK: begin
            end


            default: begin

                $fatal(
                    1,
                    "Illegal build_frame variant %0d",
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


        // Ethernet body needs at least 60 bytes before FCS.
        //
        // body =
        // Ethernet(14)
        // + IP total length
        // + padding
        // + sequence(1)

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


        for (
            i = 0;
            i < frame_body_len;
            i = i + 1
        )
            frame_body[i] =
                8'h00;


        // ====================================================
        // Ethernet
        // ====================================================

        frame_body[0] = 8'h02;
        frame_body[1] = 8'h00;
        frame_body[2] = 8'h00;
        frame_body[3] = 8'h00;
        frame_body[4] = 8'h00;
        frame_body[5] = dst_mac_last;


        frame_body[6]  = 8'h02;
        frame_body[7]  = 8'h00;
        frame_body[8]  = 8'h00;
        frame_body[9]  = 8'h00;
        frame_body[10] = 8'h00;
        frame_body[11] = 8'h01;


        // IPv4 EtherType
        frame_body[12] = 8'h08;
        frame_body[13] = 8'h00;


        // ====================================================
        // IPv4
        // ====================================================

        frame_body[14] = 8'h45;
        frame_body[15] = 8'h00;

        frame_body[16] =
            ip_len_local[15:8];

        frame_body[17] =
            ip_len_local[7:0];

        // Identification
        frame_body[18] = 8'h00;
        frame_body[19] = 8'h00;

        // Flags / fragment
        frame_body[20] = 8'h00;
        frame_body[21] = 8'h00;

        // TTL
        frame_body[22] = 8'h40;

        // UDP
        frame_body[23] = 8'h11;

        // IPv4 checksum placeholder
        frame_body[24] = 8'h00;
        frame_body[25] = 8'h00;


        // Source IP 10.0.0.X
        frame_body[26] = 8'h0A;
        frame_body[27] = 8'h00;
        frame_body[28] = 8'h00;
        frame_body[29] = src_ip_last;


        // Destination IP
        frame_body[30] = 8'h0A;
        frame_body[31] = 8'h00;
        frame_body[32] = 8'h00;
        frame_body[33] = dst_ip_last;


        // ====================================================
        // UDP
        // ====================================================

        // Src = 10000 = 0x2710
        frame_body[34] = 8'h27;
        frame_body[35] = 8'h10;

        frame_body[36] =
            udp_dst_local[15:8];

        frame_body[37] =
            udp_dst_local[7:0];

        frame_body[38] =
            udp_len_local[15:8];

        frame_body[39] =
            udp_len_local[7:0];

        // Current profile: UDP checksum = 0
        frame_body[40] = 8'h00;
        frame_body[41] = 8'h00;


        // ====================================================
        // UDP payload
        // ====================================================

        for (
            i = 0;
            i < payload_len_local;
            i = i + 1
        ) begin

            frame_body[42 + i] =
                i;

        end


        // ====================================================
        // Padding
        // ====================================================

        for (
            i = 42 + payload_len_local;
            i < frame_body_len - 1;
            i = i + 1
        ) begin

            frame_body[i] =
                8'h00;

        end


        // ====================================================
        // AFDX sequence
        // ====================================================

        frame_body[
            frame_body_len - 1
        ] = 8'h00;


        // ====================================================
        // IPv4 checksum
        // ====================================================

        frame_body[24] = 8'h00;
        frame_body[25] = 8'h00;

        sum32 = 32'd0;

        for (
            i = 14;
            i < 34;
            i = i + 2
        ) begin

            sum32 =
                sum32
                +
                {
                    frame_body[i],
                    frame_body[i + 1]
                };

        end


        while (
            sum32[31:16]
            !=
            16'd0
        ) begin

            sum32 =
                {
                    16'd0,
                    sum32[15:0]
                }
                +
                sum32[31:16];

        end


        built_ip_checksum =
            ~sum32[15:0];


        frame_body[24] =
            built_ip_checksum[15:8];

        frame_body[25] =
            built_ip_checksum[7:0];


        // ----------------------------------------------------
        // Deliberately corrupt IPv4 checksum.
        //
        // IMPORTANT:
        // CRC is calculated AFTER this corruption so M3-A
        // still sees a valid Ethernet FCS.
        // ----------------------------------------------------

        if (
            variant == CASE_BAD_IPCHK
        ) begin

            frame_body[25] =
                frame_body[25]
                ^
                8'h01;

        end


        // ====================================================
        // Ethernet CRC32
        // ====================================================

        crc_temp =
            32'hFFFFFFFF;

        for (
            i = 0;
            i < frame_body_len;
            i = i + 1
        ) begin

            crc_temp =
                crc32_update_byte(
                    crc_temp,
                    frame_body[i]
                );

        end


        built_fcs =
            crc_temp
            ^
            32'hFFFFFFFF;


        // Deliberate Layer-2 corruption.
        if (
            variant == CASE_BAD_FCS
        ) begin

            built_fcs =
                built_fcs
                ^
                32'h00000001;

        end

    end

endtask


// ============================================================
// GMII sender
// ============================================================

task send_gmii_byte;

    input [7:0] byte_value;

    begin

        @(negedge clk);

        gmii_rx_dv = 1'b1;
        gmii_rx_er = 1'b0;

        gmii_rxd =
            byte_value;

    end

endtask


task send_frame_variant;

    input integer variant;

    integer i;

    begin

        build_frame(variant);


        // 7-byte preamble
        for (
            i = 0;
            i < 7;
            i = i + 1
        )
            send_gmii_byte(
                8'h55
            );


        // SFD
        send_gmii_byte(
            8'hD5
        );


        // Ethernet body
        for (
            i = 0;
            i < frame_body_len;
            i = i + 1
        )
            send_gmii_byte(
                frame_body[i]
            );


        // FCS is sent LSB first
        send_gmii_byte(
            built_fcs[7:0]
        );

        send_gmii_byte(
            built_fcs[15:8]
        );

        send_gmii_byte(
            built_fcs[23:16]
        );

        send_gmii_byte(
            built_fcs[31:24]
        );


        @(negedge clk);

        gmii_rx_dv = 1'b0;
        gmii_rx_er = 1'b0;
        gmii_rxd   = 8'h00;


        // IFG / idle
        repeat (16)
            @(posedge clk);

    end

endtask


// ============================================================
// Wait for M3-C result with LOCAL timeout
// ============================================================

task wait_vl_result;

    input integer base_count;
    output got_result;

    integer wait_cycle;

    begin : WAIT_BLOCK

        got_result = 1'b0;

        for (
            wait_cycle = 0;
            wait_cycle < 4000;
            wait_cycle = wait_cycle + 1
        ) begin

            @(posedge clk);

            #1;

            if (
                vl_event_count
                >
                base_count
            ) begin

                got_result =
                    1'b1;

                disable WAIT_BLOCK;

            end

        end

    end

endtask


// ============================================================
// Normal policy case
// ============================================================

task run_policy_case;

    input integer test_id;
    input integer variant;

    input exp_accept;
    input exp_reject;

    input [1:0]  exp_index;
    input [15:0] exp_id;
    input [10:0] exp_lmax;

    input exp_unknown;
    input exp_disabled;
    input exp_ip;
    input exp_udp;
    input exp_length;

    integer start_error;

    integer base_vl;
    integer base_l2_good;
    integer base_l2_crc;
    integer base_meta;
    integer base_ip_checksum_error;

    reg got_result;

    begin

        start_error =
            error_count;

        base_vl =
            vl_event_count;

        base_l2_good =
            l2_good_count;

        base_l2_crc =
            l2_crc_error_count;

        base_meta =
            meta_count;

        base_ip_checksum_error =
            ip_checksum_error_count;


        send_frame_variant(
            variant
        );


        wait_vl_result(
            base_vl,
            got_result
        );


        if (!got_result) begin

            $display(
                "TC-M3C-INT-%03d ERROR: no vl_result_valid",
                test_id
            );

            error_count =
                error_count + 1;

        end
        else begin

            if (
                cap_accept !== exp_accept
            )
                error_count =
                    error_count + 1;

            if (
                cap_reject !== exp_reject
            )
                error_count =
                    error_count + 1;

            if (
                cap_vl_index !== exp_index
            )
                error_count =
                    error_count + 1;

            if (
                cap_vl_id !== exp_id
            )
                error_count =
                    error_count + 1;

            if (
                cap_vl_lmax !== exp_lmax
            )
                error_count =
                    error_count + 1;

            if (
                cap_unknown !== exp_unknown
            )
                error_count =
                    error_count + 1;

            if (
                cap_disabled !== exp_disabled
            )
                error_count =
                    error_count + 1;

            if (
                cap_ip !== exp_ip
            )
                error_count =
                    error_count + 1;

            if (
                cap_udp !== exp_udp
            )
                error_count =
                    error_count + 1;

            if (
                cap_length !== exp_length
            )
                error_count =
                    error_count + 1;

        end


        // Every policy test must be a valid Layer-2 frame.

        if (
            l2_good_count
            !=
            base_l2_good + 1
        ) begin

            $display(
                "TC-M3C-INT-%03d ERROR: M3-A did not accept frame",
                test_id
            );

            error_count =
                error_count + 1;

        end


        if (
            l2_crc_error_count
            !=
            base_l2_crc
        ) begin

            $display(
                "TC-M3C-INT-%03d ERROR: unexpected CRC error",
                test_id
            );

            error_count =
                error_count + 1;

        end


        // Parser must emit metadata.

        if (
            meta_count
            !=
            base_meta + 1
        ) begin

            $display(
                "TC-M3C-INT-%03d ERROR: metadata event missing",
                test_id
            );

            error_count =
                error_count + 1;

        end


        if (
            ip_checksum_error_count
            !=
            base_ip_checksum_error
        ) begin

            $display(
                "TC-M3C-INT-%03d ERROR: unexpected IP checksum error",
                test_id
            );

            error_count =
                error_count + 1;

        end


        if (
            error_count
            ==
            start_error
        )
            $display(
                "TC-M3C-INT-%03d PASS",
                test_id
            );
        else
            $display(
                "TC-M3C-INT-%03d FAIL",
                test_id
            );

    end

endtask


// ============================================================
// Bad FCS test
// ============================================================

task run_bad_fcs_case;

    integer start_error;

    integer base_vl;
    integer base_l2_good;
    integer base_l2_crc;
    integer base_meta;
    integer base_ip_checksum_error;

    begin

        start_error =
            error_count;

        base_vl =
            vl_event_count;

        base_l2_good =
            l2_good_count;

        base_l2_crc =
            l2_crc_error_count;

        base_meta =
            meta_count;

        base_ip_checksum_error =
            ip_checksum_error_count;


        send_frame_variant(
            CASE_BAD_FCS
        );


        repeat (500)
            @(posedge clk);

        #1;


        // Must die at M3-A.

        if (
            l2_crc_error_count
            !=
            base_l2_crc + 1
        )
            error_count =
                error_count + 1;


        if (
            l2_good_count
            !=
            base_l2_good
        )
            error_count =
                error_count + 1;


        if (
            meta_count
            !=
            base_meta
        )
            error_count =
                error_count + 1;


        if (
            vl_event_count
            !=
            base_vl
        )
            error_count =
                error_count + 1;


        if (
            ip_checksum_error_count
            !=
            base_ip_checksum_error
        )
            error_count =
                error_count + 1;


        if (
            error_count
            ==
            start_error
        )
            $display(
                "TC-M3C-INT-008 BAD FCS BLOCKED AT M3-A PASS"
            );
        else
            $display(
                "TC-M3C-INT-008 BAD FCS FAIL"
            );

    end

endtask


// ============================================================
// Bad IPv4 checksum test
// ============================================================

task run_bad_ip_checksum_case;

    integer start_error;

    integer base_vl;
    integer base_l2_good;
    integer base_l2_crc;
    integer base_meta;
    integer base_ip_checksum_error;

    begin

        start_error =
            error_count;

        base_vl =
            vl_event_count;

        base_l2_good =
            l2_good_count;

        base_l2_crc =
            l2_crc_error_count;

        base_meta =
            meta_count;

        base_ip_checksum_error =
            ip_checksum_error_count;


        send_frame_variant(
            CASE_BAD_IPCHK
        );


        repeat (500)
            @(posedge clk);

        #1;


        // Ethernet is valid.
        if (
            l2_good_count
            !=
            base_l2_good + 1
        )
            error_count =
                error_count + 1;


        if (
            l2_crc_error_count
            !=
            base_l2_crc
        )
            error_count =
                error_count + 1;


        // Must die at M3-B.
        if (
            ip_checksum_error_count
            !=
            base_ip_checksum_error + 1
        )
            error_count =
                error_count + 1;


        if (
            meta_count
            !=
            base_meta
        )
            error_count =
                error_count + 1;


        if (
            vl_event_count
            !=
            base_vl
        )
            error_count =
                error_count + 1;


        if (
            error_count
            ==
            start_error
        )
            $display(
                "TC-M3C-INT-009 BAD IPV4 CHECKSUM BLOCKED AT M3-B PASS"
            );
        else
            $display(
                "TC-M3C-INT-009 BAD IPV4 CHECKSUM FAIL"
            );

    end

endtask


// ============================================================
// Main
// ============================================================

initial begin

    error_count = 0;

    gmii_rxd   = 8'h00;
    gmii_rx_dv = 1'b0;
    gmii_rx_er = 1'b0;

    payload_ready =
        1'b1;

    rst =
        1'b1;


    repeat (10)
        @(posedge clk);

    @(negedge clk);

    rst =
        1'b0;


    repeat (5)
        @(posedge clk);


    $display("");
    $display("==============================================");
    $display("M3-A/B/C RX PIPELINE TEST");
    $display("==============================================");
    $display("");


    // --------------------------------------------------------
    // 001 Valid VL0
    // --------------------------------------------------------

    run_policy_case(
        1,
        CASE_VALID_VL0,

        1'b1,
        1'b0,

        2'd0,
        16'h0002,
        11'd512,

        1'b0,
        1'b0,
        1'b0,
        1'b0,
        1'b0
    );


    // --------------------------------------------------------
    // 002 Valid VL1
    // --------------------------------------------------------

    run_policy_case(
        2,
        CASE_VALID_VL1,

        1'b1,
        1'b0,

        2'd1,
        16'h0003,
        11'd256,

        1'b0,
        1'b0,
        1'b0,
        1'b0,
        1'b0
    );


    // --------------------------------------------------------
    // 003 Unknown VL
    // --------------------------------------------------------

    run_policy_case(
        3,
        CASE_UNKNOWN,

        1'b0,
        1'b1,

        2'd0,
        16'h0000,
        11'd0,

        1'b1,
        1'b0,
        1'b0,
        1'b0,
        1'b0
    );


    // --------------------------------------------------------
    // 004 Wrong IP
    // --------------------------------------------------------

    run_policy_case(
        4,
        CASE_BAD_IP,

        1'b0,
        1'b1,

        2'd0,
        16'h0002,
        11'd512,

        1'b0,
        1'b0,
        1'b1,
        1'b0,
        1'b0
    );


    // --------------------------------------------------------
    // 005 Wrong UDP port
    // --------------------------------------------------------

    run_policy_case(
        5,
        CASE_BAD_UDP,

        1'b0,
        1'b1,

        2'd0,
        16'h0002,
        11'd512,

        1'b0,
        1'b0,
        1'b0,
        1'b1,
        1'b0
    );


    // --------------------------------------------------------
    // 006 LMAX exceeded
    //
    // VL1 LMAX = 256
    // Generated payload = 257
    // --------------------------------------------------------

    run_policy_case(
        6,
        CASE_LMAX,

        1'b0,
        1'b1,

        2'd1,
        16'h0003,
        11'd256,

        1'b0,
        1'b0,
        1'b0,
        1'b0,
        1'b1
    );


    // --------------------------------------------------------
    // 007 Disabled VL
    // --------------------------------------------------------

    run_policy_case(
        7,
        CASE_DISABLED,

        1'b0,
        1'b1,

        2'd2,
        16'h0004,
        11'd128,

        1'b0,
        1'b1,
        1'b0,
        1'b0,
        1'b0
    );


    // --------------------------------------------------------
    // 008 Corrupt Ethernet FCS
    // --------------------------------------------------------

    run_bad_fcs_case;


    // --------------------------------------------------------
    // 009 Corrupt IPv4 checksum but regenerate valid FCS
    // --------------------------------------------------------

    run_bad_ip_checksum_case;


    // ========================================================
    // Final
    // ========================================================

    $display("");
    $display("==============================================");

    if (
        error_count == 0
    ) begin

        $display(
            "M3-A/B/C RX PIPELINE REGRESSION PASS"
        );

        $display(
            "VALID VL0 PASS"
        );

        $display(
            "VALID VL1 PASS"
        );

        $display(
            "UNKNOWN VL PASS"
        );

        $display(
            "IP WHITELIST PASS"
        );

        $display(
            "UDP WHITELIST PASS"
        );

        $display(
            "LMAX PASS"
        );

        $display(
            "DISABLED VL PASS"
        );

        $display(
            "BAD FCS BLOCKED AT M3-A PASS"
        );

        $display(
            "BAD IPV4 CHECKSUM BLOCKED AT M3-B PASS"
        );

    end
    else begin

        $display(
            "M3-A/B/C RX PIPELINE FAIL"
        );

        $display(
            "TOTAL ERRORS = %0d",
            error_count
        );

        $fatal(
            1,
            "M3 REGRESSION FAILED"
        );

    end

    $display("==============================================");
    $display("");

    #100;

    $finish;

end


// ============================================================
// Global watchdog
// ============================================================

initial begin

    #1000000;

    $fatal(
        1,
        "M3 INTEGRATION GLOBAL TIMEOUT"
    );

end


endmodule
