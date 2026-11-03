`timescale 1ns / 1ps


module tb_afdx_rx_frontend_m3d;


// ============================================================
// Test variants
//
// Reuse the M3-C variant set and add a sequence byte so the
// same frame builder can drive both the VL decision path and
// the M3-D sequence-integrity path.
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

wire [15:0] ip_header_checksum;

wire        meta_valid;

wire [10:0] payload_length;


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


// ============================================================
// M3-D final frame result
// ============================================================

wire        rx_result_valid;

wire        rx_accept;
wire        rx_reject;

wire [1:0]  rx_vl_index;
wire [15:0] rx_vl_id;

wire [7:0]  rx_error_code;


// M3-D sequence integrity status

wire        seq_first_frame;
wire        seq_reset_sequence;
wire        seq_single_loss;

wire        seq_duplicate_error;
wire        seq_sequence_error;

wire [7:0]  seq_psn_before;
wire [7:0]  seq_psn_after;


// M3-D commit buffer status

wire        commit_overflow_error;


// ============================================================
// Committed payload stream (application side)
// ============================================================

wire [7:0]  payload_data;
wire        payload_valid;

wire        payload_sof;
wire        payload_eof;


// ============================================================
// DUT
// ============================================================

afdx_rx_frontend dut (

    .clk                    (clk),
    .rst                    (rst),

    .gmii_rxd               (gmii_rxd),
    .gmii_rx_dv             (gmii_rx_dv),
    .gmii_rx_er             (gmii_rx_er),

    .ip_header_checksum     (ip_header_checksum),

    .payload_length         (payload_length),

    .meta_valid             (meta_valid),

    .payload_ready          (payload_ready),

    .payload_data           (payload_data),
    .payload_valid          (payload_valid),
    .payload_sof            (payload_sof),
    .payload_eof            (payload_eof),

    .l2_good_frame          (l2_good_frame),
    .l2_crc_error           (l2_crc_error),

    .ip_checksum_error      (ip_checksum_error),

    .vl_result_valid        (vl_result_valid),

    .vl_accept              (vl_accept),
    .vl_reject              (vl_reject),

    .vl_index               (vl_index),
    .vl_id                  (vl_id),
    .vl_lmax                (vl_lmax),

    .rx_result_valid        (rx_result_valid),

    .rx_accept              (rx_accept),
    .rx_reject              (rx_reject),

    .rx_vl_index            (rx_vl_index),
    .rx_vl_id               (rx_vl_id),

    .rx_error_code          (rx_error_code),

    .seq_first_frame        (seq_first_frame),
    .seq_reset_sequence     (seq_reset_sequence),
    .seq_single_loss        (seq_single_loss),

    .seq_duplicate_error    (seq_duplicate_error),
    .seq_sequence_error     (seq_sequence_error),

    .seq_psn_before         (seq_psn_before),
    .seq_psn_after          (seq_psn_after),

    .commit_overflow_error  (commit_overflow_error)
);


// ============================================================
// rx_result monitor
//
// Sampled on the negative edge because rx_result_valid and its
// companion signals (rx_vl_*, rx_error_code, seq_*) are stable
// for the whole high cycle of rx_result_valid.
//
// Sampling on posedge would race with the non-blocking update
// that clears frame_vl_valid at the end of the result cycle.
// ============================================================

integer rx_result_count;

reg        cap_rx_accept;
reg        cap_rx_reject;

reg [1:0]  cap_rx_vl_index;
reg [15:0] cap_rx_vl_id;

reg [7:0]  cap_rx_error_code;


reg        cap_seq_first_frame;
reg        cap_seq_reset_sequence;
reg        cap_seq_single_loss;

reg        cap_seq_duplicate_error;
reg        cap_seq_sequence_error;

reg [7:0]  cap_seq_psn_before;
reg [7:0]  cap_seq_psn_after;


always @(negedge clk) begin

    if (rst) begin

        rx_result_count = 0;

        cap_rx_accept = 1'b0;
        cap_rx_reject = 1'b0;

        cap_rx_vl_index = 2'd0;
        cap_rx_vl_id    = 16'd0;

        cap_rx_error_code = 8'h00;

        cap_seq_first_frame    = 1'b0;
        cap_seq_reset_sequence = 1'b0;
        cap_seq_single_loss    = 1'b0;

        cap_seq_duplicate_error = 1'b0;
        cap_seq_sequence_error  = 1'b0;

        cap_seq_psn_before = 8'h00;
        cap_seq_psn_after  = 8'h00;

    end
    else begin

        if (rx_result_valid) begin

            rx_result_count = rx_result_count + 1;

            cap_rx_accept = rx_accept;
            cap_rx_reject = rx_reject;

            cap_rx_vl_index = rx_vl_index;
            cap_rx_vl_id    = rx_vl_id;

            cap_rx_error_code = rx_error_code;

            cap_seq_first_frame    = seq_first_frame;
            cap_seq_reset_sequence = seq_reset_sequence;
            cap_seq_single_loss    = seq_single_loss;

            cap_seq_duplicate_error = seq_duplicate_error;
            cap_seq_sequence_error  = seq_sequence_error;

            cap_seq_psn_before = seq_psn_before;
            cap_seq_psn_after  = seq_psn_after;

        end

    end

end


// ============================================================
// Committed payload scoreboard
// ============================================================

integer output_count;

reg [7:0] received [0:511];
reg       cap_sof  [0:511];
reg       cap_eof  [0:511];


always @(posedge clk) begin

    if (rst) begin

        output_count = 0;

    end
    else begin

        if (payload_valid && payload_ready) begin

            received[output_count] = payload_data;
            cap_sof[output_count]  = payload_sof;
            cap_eof[output_count]  = payload_eof;

            output_count = output_count + 1;

        end

    end

end


// ============================================================
// Counters / captured result
// ============================================================

integer error_count;

integer l2_good_count;
integer l2_crc_error_count;
integer meta_count;
integer ip_checksum_error_count;


always @(posedge clk) begin

    if (rst) begin

        l2_good_count           = 0;
        l2_crc_error_count      = 0;
        meta_count              = 0;
        ip_checksum_error_count = 0;

    end
    else begin

        if (l2_good_frame)
            l2_good_count = l2_good_count + 1;

        if (l2_crc_error)
            l2_crc_error_count = l2_crc_error_count + 1;

        if (meta_valid)
            meta_count = meta_count + 1;

        if (ip_checksum_error)
            ip_checksum_error_count = ip_checksum_error_count + 1;

    end

end


// ============================================================
// Frame storage
// ============================================================

reg [7:0] frame_body [0:1517];

integer frame_body_len;

reg [15:0] built_ip_checksum;
reg [31:0] built_fcs;

reg [7:0]  cur_seq;


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
// The AFDX sequence byte is taken from the global cur_seq.
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
                i[7:0];

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
        ] = cur_seq;


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
// Send a frame with an explicit AFDX sequence byte
// ============================================================

task send_frame_seq;

    input integer variant;
    input [7:0]  seq;

    begin

        cur_seq = seq;

        send_frame_variant(variant);

    end

endtask


// ============================================================
// Wait for rx_result_valid
// ============================================================

task wait_rx_result;

    input integer base_count;
    output got_result;

    integer wait_cycle;

    begin : WAIT_RX_BLOCK

        got_result = 1'b0;

        for (
            wait_cycle = 0;
            wait_cycle < 4000;
            wait_cycle = wait_cycle + 1
        ) begin

            @(negedge clk);

            if (
                rx_result_count
                >
                base_count
            ) begin

                got_result =
                    1'b1;

                disable WAIT_RX_BLOCK;

            end

        end

    end

endtask


// ============================================================
// Clear payload scoreboard
// ============================================================

task clear_scoreboard;

    integer i;

    begin

        output_count = 0;

        for (i = 0; i < 512; i = i + 1) begin

            received[i] = 8'h00;

            cap_sof[i] = 1'b0;
            cap_eof[i] = 1'b0;

        end

    end

endtask


// ============================================================
// Wait until the committed payload replay reaches a given
// byte count (or times out).
// ============================================================

task wait_output_count;

    input integer expected;

    integer timeout;

    begin

        timeout = 0;

        while (
            (output_count < expected)
            &&
            (timeout < 20000)
        ) begin

            @(negedge clk);

            timeout = timeout + 1;

        end


        if (timeout >= 20000) begin

            $display(
                "ERROR: wait_output_count timeout, got %0d expected %0d",
                output_count,
                expected
            );

            error_count = error_count + 1;

        end

    end

endtask


// ============================================================
// Standard integration case
//
// exp_seq_checked = 1 means a sequence-integrity result is
// expected (accept or sequence reject). It gates the seq_* and
// psn_* checks because those are only meaningful when the
// sequence checker was actually armed.
// ============================================================

task run_case;

    input integer test_id;
    input integer variant;
    input [7:0]  seq;

    input exp_accept;
    input exp_reject;

    input [7:0]  exp_err_code;
    input [1:0]  exp_vl_index;
    input [15:0] exp_vl_id;

    input exp_seq_checked;

    input exp_first;
    input exp_reset;
    input exp_loss;
    input exp_duplicate;
    input exp_seq_error;

    input [7:0] exp_psn_before;
    input [7:0] exp_psn_after;

    input [7:0] exp_payload_len;

    integer start_error;

    integer base_rx;
    integer base_l2_good;
    integer base_l2_crc;

    reg got_result;

    integer i;

    begin

        start_error = error_count;

        base_rx      = rx_result_count;
        base_l2_good = l2_good_count;
        base_l2_crc  = l2_crc_error_count;

        clear_scoreboard;

        send_frame_seq(variant, seq);

        wait_rx_result(base_rx, got_result);


        if (!got_result) begin

            $display(
                "TC-M3D-INT-%03d ERROR: no rx_result_valid",
                test_id
            );

            error_count = error_count + 1;

        end
        else begin

            if (cap_rx_accept !== exp_accept) begin

                $display(
                    "TC-M3D-INT-%03d ERROR: rx_accept = %b expected %b",
                    test_id,
                    cap_rx_accept,
                    exp_accept
                );

                error_count = error_count + 1;

            end


            if (cap_rx_reject !== exp_reject) begin

                $display(
                    "TC-M3D-INT-%03d ERROR: rx_reject = %b expected %b",
                    test_id,
                    cap_rx_reject,
                    exp_reject
                );

                error_count = error_count + 1;

            end


            if (cap_rx_vl_index !== exp_vl_index) begin

                $display(
                    "TC-M3D-INT-%03d ERROR: rx_vl_index = %0d expected %0d",
                    test_id,
                    cap_rx_vl_index,
                    exp_vl_index
                );

                error_count = error_count + 1;

            end


            if (cap_rx_vl_id !== exp_vl_id) begin

                $display(
                    "TC-M3D-INT-%03d ERROR: rx_vl_id = %04x expected %04x",
                    test_id,
                    cap_rx_vl_id,
                    exp_vl_id
                );

                error_count = error_count + 1;

            end


            if (cap_rx_error_code !== exp_err_code) begin

                $display(
                    "TC-M3D-INT-%03d ERROR: rx_error_code = %02x expected %02x",
                    test_id,
                    cap_rx_error_code,
                    exp_err_code
                );

                error_count = error_count + 1;

            end


            if (exp_seq_checked) begin

                if (cap_seq_first_frame !== exp_first) begin

                    $display(
                        "TC-M3D-INT-%03d ERROR: seq_first_frame",
                        test_id
                    );

                    error_count = error_count + 1;

                end


                if (cap_seq_reset_sequence !== exp_reset) begin

                    $display(
                        "TC-M3D-INT-%03d ERROR: seq_reset_sequence",
                        test_id
                    );

                    error_count = error_count + 1;

                end


                if (cap_seq_single_loss !== exp_loss) begin

                    $display(
                        "TC-M3D-INT-%03d ERROR: seq_single_loss",
                        test_id
                    );

                    error_count = error_count + 1;

                end


                if (cap_seq_duplicate_error !== exp_duplicate) begin

                    $display(
                        "TC-M3D-INT-%03d ERROR: seq_duplicate_error",
                        test_id
                    );

                    error_count = error_count + 1;

                end


                if (cap_seq_sequence_error !== exp_seq_error) begin

                    $display(
                        "TC-M3D-INT-%03d ERROR: seq_sequence_error",
                        test_id
                    );

                    error_count = error_count + 1;

                end


                if (cap_seq_psn_before !== exp_psn_before) begin

                    $display(
                        "TC-M3D-INT-%03d ERROR: psn_before = %0d expected %0d",
                        test_id,
                        cap_seq_psn_before,
                        exp_psn_before
                    );

                    error_count = error_count + 1;

                end


                if (cap_seq_psn_after !== exp_psn_after) begin

                    $display(
                        "TC-M3D-INT-%03d ERROR: psn_after = %0d expected %0d",
                        test_id,
                        cap_seq_psn_after,
                        exp_psn_after
                    );

                    error_count = error_count + 1;

                end

            end

        end


        // ----------------------------------------------------
        // Committed payload
        // ----------------------------------------------------

        if (exp_payload_len > 0) begin

            wait_output_count(exp_payload_len);

            repeat (4)
                @(posedge clk);

            if (output_count !== exp_payload_len) begin

                $display(
                    "TC-M3D-INT-%03d ERROR: output_count = %0d expected %0d",
                    test_id,
                    output_count,
                    exp_payload_len
                );

                error_count = error_count + 1;

            end


            // Payload bytes are i = 0,1,2,...

            for (i = 0; i < exp_payload_len; i = i + 1) begin

                if (received[i] !== i[7:0]) begin

                    $display(
                        "TC-M3D-INT-%03d ERROR: payload[%0d] = %02x expected %02x",
                        test_id,
                        i,
                        received[i],
                        i[7:0]
                    );

                    error_count = error_count + 1;

                end

            end


            if (cap_sof[0] !== 1'b1) begin

                $display(
                    "TC-M3D-INT-%03d ERROR: payload SOF missing",
                    test_id
                );

                error_count = error_count + 1;

            end


            if (cap_eof[exp_payload_len - 1] !== 1'b1) begin

                $display(
                    "TC-M3D-INT-%03d ERROR: payload EOF missing",
                    test_id
                );

                error_count = error_count + 1;

            end

        end
        else begin

            // No payload may escape for a rejected frame.

            repeat (8)
                @(posedge clk);

            if (output_count !== 0) begin

                $display(
                    "TC-M3D-INT-%03d ERROR: rejected frame leaked %0d bytes",
                    test_id,
                    output_count
                );

                error_count = error_count + 1;

            end

        end


        // ----------------------------------------------------
        // Every frame here is a valid Layer-2 frame.
        // ----------------------------------------------------

        if (l2_good_count != base_l2_good + 1) begin

            $display(
                "TC-M3D-INT-%03d ERROR: M3-A did not accept frame",
                test_id
            );

            error_count = error_count + 1;

        end


        if (l2_crc_error_count != base_l2_crc) begin

            $display(
                "TC-M3D-INT-%03d ERROR: unexpected CRC error",
                test_id
            );

            error_count = error_count + 1;

        end


        if (error_count == start_error)
            $display("TC-M3D-INT-%03d PASS", test_id);
        else
            $display("TC-M3D-INT-%03d FAIL", test_id);

    end

endtask


// ============================================================
// Downstream backpressure case
//
// A good VL0 frame must replay its payload, but the replay
// must stall without data loss or duplication while
// payload_ready is deasserted.
// ============================================================

task run_backpressure_case;

    integer start_error;

    integer base_rx;

    reg got_result;

    integer i;

    begin

        start_error = error_count;

        base_rx = rx_result_count;

        clear_scoreboard;

        payload_ready = 1'b1;

        send_frame_seq(CASE_VALID_VL0, 8'd2);

        wait_rx_result(base_rx, got_result);


        if (!got_result) begin

            $display(
                "TC-M3D-INT-015 ERROR: no rx_result_valid"
            );

            error_count = error_count + 1;

        end
        else if (cap_rx_accept !== 1'b1) begin

            $display(
                "TC-M3D-INT-015 ERROR: frame not accepted"
            );

            error_count = error_count + 1;

        end


        // Wait for the replay to begin and transfer exactly one
        // byte, then stall.

        while (output_count < 1)
            @(negedge clk);

        payload_ready = 1'b0;

        repeat (8)
            @(posedge clk);

        if (output_count != 1) begin

            $display(
                "TC-M3D-INT-015 ERROR: replay advanced during backpressure (%0d)",
                output_count
            );

            error_count = error_count + 1;

        end


        @(negedge clk);

        payload_ready = 1'b1;

        wait_output_count(4);

        repeat (4)
            @(posedge clk);


        if (output_count != 4) begin

            $display(
                "TC-M3D-INT-015 ERROR: output_count = %0d expected 4",
                output_count
            );

            error_count = error_count + 1;

        end


        for (i = 0; i < 4; i = i + 1) begin

            if (received[i] !== i[7:0]) begin

                $display(
                    "TC-M3D-INT-015 ERROR: payload[%0d] = %02x expected %02x",
                    i,
                    received[i],
                    i[7:0]
                );

                error_count = error_count + 1;

            end

        end


        if (cap_sof[0] !== 1'b1) begin

            $display(
                "TC-M3D-INT-015 ERROR: SOF missing"
            );

            error_count = error_count + 1;

        end


        if (cap_eof[3] !== 1'b1) begin

            $display(
                "TC-M3D-INT-015 ERROR: EOF missing"
            );

            error_count = error_count + 1;

        end


        if (error_count == start_error)
            $display("TC-M3D-INT-015 PASS");
        else
            $display("TC-M3D-INT-015 FAIL");

    end

endtask


// ============================================================
// Bad FCS case
//
// A Layer-2 rejected frame must not reach the M3-B/C/D
// decision path at all, therefore no rx_result_valid.
// ============================================================

task run_bad_fcs_case;

    integer start_error;

    integer base_rx;
    integer base_l2_good;
    integer base_l2_crc;

    begin

        start_error = error_count;

        base_rx      = rx_result_count;
        base_l2_good = l2_good_count;
        base_l2_crc  = l2_crc_error_count;

        send_frame_seq(CASE_BAD_FCS, 8'd0);

        repeat (500)
            @(posedge clk);


        if (l2_crc_error_count != base_l2_crc + 1) begin

            $display(
                "TC-M3D-INT-016 ERROR: CRC error not reported"
            );

            error_count = error_count + 1;

        end


        if (l2_good_count != base_l2_good) begin

            $display(
                "TC-M3D-INT-016 ERROR: bad frame accepted by M3-A"
            );

            error_count = error_count + 1;

        end


        if (rx_result_count != base_rx) begin

            $display(
                "TC-M3D-INT-016 ERROR: bad FCS produced rx_result_valid"
            );

            error_count = error_count + 1;

        end


        if (error_count == start_error)
            $display("TC-M3D-INT-016 PASS");
        else
            $display("TC-M3D-INT-016 FAIL");

    end

endtask


// ============================================================
// Main
// ============================================================

initial begin

    error_count = 0;

    cur_seq = 8'h00;

    gmii_rxd   = 8'h00;
    gmii_rx_dv = 1'b0;
    gmii_rx_er = 1'b0;

    payload_ready = 1'b1;

    rst = 1'b1;


    repeat (10)
        @(posedge clk);

    @(negedge clk);

    rst = 1'b0;


    repeat (5)
        @(posedge clk);


    $display("");
    $display("==============================================");
    $display("M3-D RX FRONTEND INTEGRATION TEST");
    $display("==============================================");
    $display("");


    // --------------------------------------------------------
    // 001 First VL0 frame, SN=1
    // --------------------------------------------------------

    run_case(
        1, CASE_VALID_VL0, 8'd1,
        1'b1, 1'b0,
        8'h00, 2'd0, 16'h0002,
        1'b1,
        1'b1, 1'b0, 1'b0, 1'b0, 1'b0,
        8'd0, 8'd1,
        8'd4
    );


    // --------------------------------------------------------
    // 002 Normal increment 1 -> 2
    // --------------------------------------------------------

    run_case(
        2, CASE_VALID_VL0, 8'd2,
        1'b1, 1'b0,
        8'h00, 2'd0, 16'h0002,
        1'b1,
        1'b0, 1'b0, 1'b0, 1'b0, 1'b0,
        8'd1, 8'd2,
        8'd4
    );


    // --------------------------------------------------------
    // 003 Single frame loss: 2 -> 4
    // --------------------------------------------------------

    run_case(
        3, CASE_VALID_VL0, 8'd4,
        1'b1, 1'b0,
        8'h00, 2'd0, 16'h0002,
        1'b1,
        1'b0, 1'b0, 1'b1, 1'b0, 1'b0,
        8'd2, 8'd4,
        8'd4
    );


    // --------------------------------------------------------
    // 004 Duplicate: 4 -> 4 (sequence reject)
    // --------------------------------------------------------

    run_case(
        4, CASE_VALID_VL0, 8'd4,
        1'b0, 1'b1,
        8'h40, 2'd0, 16'h0002,
        1'b1,
        1'b0, 1'b0, 1'b0, 1'b1, 1'b0,
        8'd4, 8'd4,
        8'd0
    );


    // --------------------------------------------------------
    // 005 Recovery after duplicate: 4 -> 5
    // --------------------------------------------------------

    run_case(
        5, CASE_VALID_VL0, 8'd5,
        1'b1, 1'b0,
        8'h00, 2'd0, 16'h0002,
        1'b1,
        1'b0, 1'b0, 1'b0, 1'b0, 1'b0,
        8'd4, 8'd5,
        8'd4
    );


    // --------------------------------------------------------
    // 006 Bad IPv4 checksum (parser reject)
    //
    // rx_error_code = 0x20, rx_vl_id = 0, no payload replay.
    // --------------------------------------------------------

    run_case(
        6, CASE_BAD_IPCHK, 8'd0,
        1'b0, 1'b1,
        8'h20, 2'd0, 16'h0000,
        1'b0,
        1'b0, 1'b0, 1'b0, 1'b0, 1'b0,
        8'd0, 8'd0,
        8'd0
    );


    // --------------------------------------------------------
    // 007 Good frame immediately after bad IPv4 checksum
    //
    // No stale VL / decision contamination. rx_vl_id must be
    // 0x0002 (not 0 from the previous bad frame).
    // --------------------------------------------------------

    run_case(
        7, CASE_VALID_VL0, 8'd6,
        1'b1, 1'b0,
        8'h00, 2'd0, 16'h0002,
        1'b1,
        1'b0, 1'b0, 1'b0, 1'b0, 1'b0,
        8'd5, 8'd6,
        8'd4
    );


    // --------------------------------------------------------
    // 008 Unknown VL
    // --------------------------------------------------------

    run_case(
        8, CASE_UNKNOWN, 8'd0,
        1'b0, 1'b1,
        8'h30, 2'd0, 16'h0000,
        1'b0,
        1'b0, 1'b0, 1'b0, 1'b0, 1'b0,
        8'd0, 8'd0,
        8'd0
    );


    // --------------------------------------------------------
    // 009 Disabled VL
    // --------------------------------------------------------

    run_case(
        9, CASE_DISABLED, 8'd0,
        1'b0, 1'b1,
        8'h31, 2'd2, 16'h0004,
        1'b0,
        1'b0, 1'b0, 1'b0, 1'b0, 1'b0,
        8'd0, 8'd0,
        8'd0
    );


    // --------------------------------------------------------
    // 010 IP whitelist violation
    // --------------------------------------------------------

    run_case(
        10, CASE_BAD_IP, 8'd0,
        1'b0, 1'b1,
        8'h32, 2'd0, 16'h0002,
        1'b0,
        1'b0, 1'b0, 1'b0, 1'b0, 1'b0,
        8'd0, 8'd0,
        8'd0
    );


    // --------------------------------------------------------
    // 011 UDP whitelist violation
    // --------------------------------------------------------

    run_case(
        11, CASE_BAD_UDP, 8'd0,
        1'b0, 1'b1,
        8'h33, 2'd0, 16'h0002,
        1'b0,
        1'b0, 1'b0, 1'b0, 1'b0, 1'b0,
        8'd0, 8'd0,
        8'd0
    );


    // --------------------------------------------------------
    // 012 LMAX exceeded (VL1 LMAX=256, payload=257)
    // --------------------------------------------------------

    run_case(
        12, CASE_LMAX, 8'd0,
        1'b0, 1'b1,
        8'h34, 2'd1, 16'h0003,
        1'b0,
        1'b0, 1'b0, 1'b0, 1'b0, 1'b0,
        8'd0, 8'd0,
        8'd0
    );


    // --------------------------------------------------------
    // 013 SN=0 transmitter reset indication
    // --------------------------------------------------------

    run_case(
        13, CASE_VALID_VL0, 8'd0,
        1'b1, 1'b0,
        8'h00, 2'd0, 16'h0002,
        1'b1,
        1'b0, 1'b1, 1'b0, 1'b0, 1'b0,
        8'd6, 8'd0,
        8'd4
    );


    // --------------------------------------------------------
    // 014 After reset indication: 0 -> 1
    // --------------------------------------------------------

    run_case(
        14, CASE_VALID_VL0, 8'd1,
        1'b1, 1'b0,
        8'h00, 2'd0, 16'h0002,
        1'b1,
        1'b0, 1'b0, 1'b0, 1'b0, 1'b0,
        8'd0, 8'd1,
        8'd4
    );


    // --------------------------------------------------------
    // 015 Downstream backpressure
    // --------------------------------------------------------

    run_backpressure_case;


    // --------------------------------------------------------
    // 016 Bad Ethernet FCS
    // --------------------------------------------------------

    run_bad_fcs_case;


    // ========================================================
    // Final
    // ========================================================

    $display("");
    $display("==============================================");

    if (error_count == 0) begin

        $display("M3-D RX FRONTEND INTEGRATION REGRESSION PASS");

        $display("FIRST FRAME ACCEPT VERIFIED");
        $display("NORMAL INCREMENT VERIFIED");
        $display("SINGLE FRAME LOSS VERIFIED");
        $display("DUPLICATE REJECT VERIFIED");
        $display("DUPLICATE RECOVERY VERIFIED");
        $display("BAD IPV4 CHECKSUM REJECT VERIFIED");
        $display("STALE VL CONTAMINATION CLEAN VERIFIED");
        $display("UNKNOWN VL REJECT VERIFIED");
        $display("DISABLED VL REJECT VERIFIED");
        $display("IP WHITELIST REJECT VERIFIED");
        $display("UDP WHITELIST REJECT VERIFIED");
        $display("LMAX REJECT VERIFIED");
        $display("SN=0 RESET SEMANTICS VERIFIED");
        $display("POST-RESET INCREMENT VERIFIED");
        $display("DOWNSTREAM BACKPRESSURE VERIFIED");
        $display("BAD FCS BLOCKED AT M3-A VERIFIED");

    end
    else begin

        $display("M3-D RX FRONTEND INTEGRATION FAIL");

        $display("TOTAL ERRORS = %0d", error_count);

        $fatal(1, "M3-D RX FRONTEND INTEGRATION FAILED");

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

    $fatal(1, "M3-D RX FRONTEND INTEGRATION GLOBAL TIMEOUT");

end


endmodule
