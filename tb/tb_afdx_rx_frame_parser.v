`timescale 1ns / 1ps

module tb_afdx_rx_frame_parser;


// ============================================================
// Test variants
// ============================================================

localparam integer CASE_VALID_VL0 = 0;
localparam integer CASE_UNKNOWN    = 2;
localparam integer CASE_BAD_FCS    = 7;


// ============================================================
// Clock / reset
// ============================================================

reg clk;
reg rst;

integer error_count;
integer tc_error;

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


// ============================================================
// Candidate / decision / payload
// ============================================================

reg        candidate_ready;
reg        decision_valid;
reg        decision_accept;
reg        payload_ready;


wire        candidate_valid;
wire [1:0]  candidate_vl_index;
wire [15:0] candidate_vl_id;
wire [10:0] candidate_payload_length;
wire [7:0]  candidate_sequence;
wire        candidate_outstanding;

wire [7:0]  payload_data;
wire        payload_valid;
wire        payload_sof;
wire        payload_eof;

wire        commit_overflow_error;


// ============================================================
// Useful DUT signals
// ============================================================

wire        l2_good_frame;
wire        l2_crc_error;

wire        meta_valid;
wire        vl_result_valid;
wire        vl_accept;
wire [1:0]  vl_index;

wire        unknown_vl_error;


// ============================================================
// DUT
// ============================================================

afdx_rx_frame_parser dut (
    .rx_cfg_table(672'd0),
    .clk                       (clk),
    .rst                       (rst),

    .gmii_rxd                  (gmii_rxd),
    .gmii_rx_dv                (gmii_rx_dv),
    .gmii_rx_er                (gmii_rx_er),

    .dst_mac                   (),
    .src_mac                   (),
    .ether_type                (),
    .ip_total_length           (),
    .ip_ttl                    (),
    .ip_protocol               (),
    .ip_header_checksum        (),
    .src_ip                    (),
    .dst_ip                    (),
    .udp_src_port              (),
    .udp_dst_port              (),
    .udp_length                (),
    .udp_checksum              (),
    .payload_length            (),
    .padding_length            (),

    .afdx_sequence             (),
    .meta_valid                (meta_valid),

    .candidate_valid           (candidate_valid),
    .candidate_ready           (candidate_ready),
    .candidate_vl_index        (candidate_vl_index),
    .candidate_vl_id           (candidate_vl_id),
    .candidate_payload_length  (candidate_payload_length),
    .candidate_sequence        (candidate_sequence),
    .candidate_outstanding     (candidate_outstanding),

    .decision_valid            (decision_valid),
    .decision_accept           (decision_accept),

    .payload_data              (payload_data),
    .payload_valid             (payload_valid),
    .payload_ready             (payload_ready),
    .payload_sof               (payload_sof),
    .payload_eof               (payload_eof),

    .frame_done                (),
    .frame_valid               (),

    .l2_good_frame             (l2_good_frame),
    .l2_output_frame_done      (),
    .l2_crc_error              (l2_crc_error),
    .l2_format_error           (),
    .l2_length_error           (),
    .l2_rx_error               (),
    .l2_overflow_error         (),

    .ether_type_error          (),
    .ip_version_error          (),
    .ip_ihl_error              (),
    .ip_checksum_error         (),
    .ip_protocol_error         (),
    .ip_length_error           (),
    .udp_length_error          (),
    .structure_error           (),

    .vl_result_valid           (vl_result_valid),
    .vl_accept                 (vl_accept),
    .vl_reject                 (),
    .vl_index                  (vl_index),
    .vl_id                     (),
    .vl_lmax                   (),
    .unknown_vl_error          (unknown_vl_error),
    .disabled_vl_error         (),
    .ip_whitelist_error        (),
    .udp_whitelist_error       (),
    .length_whitelist_error    (),

    .commit_overflow_error     (commit_overflow_error)
);


// ============================================================
// Frame storage
// ============================================================

reg [7:0] frame_body [0:1517];
integer frame_body_len;

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
        for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
            if (crc_temp[0] ^ data_in[bit_index])
                crc_temp = (crc_temp >> 1) ^ 32'hEDB88320;
            else
                crc_temp = crc_temp >> 1;
        end
        crc32_update_byte = crc_temp;
    end
endfunction


// ============================================================
// Build test frame (VL0 valid / unknown VL / bad FCS)
//
// Layout:
//   0..13   Ethernet
//   14..33  IPv4
//   34..41  UDP
//   42..    payload (4 bytes)
//   padding
//   final   AFDX sequence
// ============================================================

task build_frame;
    input integer variant;
    input [7:0]  seq;

    integer i;
    integer payload_len_local;
    integer padding_len_local;
    reg [7:0]  dst_mac_last;
    reg [7:0]  src_ip_last;
    reg [7:0]  dst_ip_last;
    reg [15:0] udp_dst_local;
    reg [15:0] ip_len_local;
    reg [15:0] udp_len_local;
    reg [31:0] sum32;
    reg [31:0] crc_temp;
    reg [15:0] built_ip_checksum;

    begin
        payload_len_local = 4;
        dst_mac_last = 8'h02;
        src_ip_last  = 8'h01;
        dst_ip_last  = 8'h02;
        udp_dst_local = 16'd10001;

        case (variant)
            CASE_VALID_VL0: begin end
            CASE_UNKNOWN: begin
                dst_mac_last = 8'h99;
            end
            CASE_BAD_FCS: begin end
            default: begin
                $fatal(1, "Illegal variant %0d", variant);
            end
        endcase

        udp_len_local = 16'd8 + payload_len_local;
        ip_len_local  = 16'd20 + udp_len_local;

        if ((14 + ip_len_local + 1) < 60)
            padding_len_local = 60 - (14 + ip_len_local + 1);
        else
            padding_len_local = 0;

        frame_body_len = 14 + ip_len_local + padding_len_local + 1;

        for (i = 0; i < frame_body_len; i = i + 1)
            frame_body[i] = 8'h00;

        // Ethernet
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
        frame_body[12] = 8'h08;
        frame_body[13] = 8'h00;

        // IPv4
        frame_body[14] = 8'h45;
        frame_body[15] = 8'h00;
        frame_body[16] = ip_len_local[15:8];
        frame_body[17] = ip_len_local[7:0];
        frame_body[18] = 8'h00;
        frame_body[19] = 8'h00;
        frame_body[20] = 8'h00;
        frame_body[21] = 8'h00;
        frame_body[22] = 8'h40;
        frame_body[23] = 8'h11;
        frame_body[24] = 8'h00;
        frame_body[25] = 8'h00;
        frame_body[26] = 8'h0A;
        frame_body[27] = 8'h00;
        frame_body[28] = 8'h00;
        frame_body[29] = src_ip_last;
        frame_body[30] = 8'h0A;
        frame_body[31] = 8'h00;
        frame_body[32] = 8'h00;
        frame_body[33] = dst_ip_last;

        // UDP
        frame_body[34] = 8'h27;
        frame_body[35] = 8'h10;
        frame_body[36] = udp_dst_local[15:8];
        frame_body[37] = udp_dst_local[7:0];
        frame_body[38] = udp_len_local[15:8];
        frame_body[39] = udp_len_local[7:0];
        frame_body[40] = 8'h00;
        frame_body[41] = 8'h00;

        // Payload
        for (i = 0; i < payload_len_local; i = i + 1)
            frame_body[42 + i] = i;

        // Padding
        for (i = 42 + payload_len_local; i < frame_body_len - 1; i = i + 1)
            frame_body[i] = 8'h00;

        // AFDX sequence
        frame_body[frame_body_len - 1] = seq;

        // IPv4 checksum
        frame_body[24] = 8'h00;
        frame_body[25] = 8'h00;
        sum32 = 32'd0;
        for (i = 14; i < 34; i = i + 2)
            sum32 = sum32 + {frame_body[i], frame_body[i+1]};
        while (sum32[31:16] != 16'd0)
            sum32 = {16'd0, sum32[15:0]} + sum32[31:16];
        built_ip_checksum = ~sum32[15:0];
        frame_body[24] = built_ip_checksum[15:8];
        frame_body[25] = built_ip_checksum[7:0];
        // Ethernet CRC32
        crc_temp = 32'hFFFFFFFF;
        for (i = 0; i < frame_body_len; i = i + 1)
            crc_temp = crc32_update_byte(crc_temp, frame_body[i]);
        built_fcs = crc_temp ^ 32'hFFFFFFFF;

        if (variant == CASE_BAD_FCS)
            built_fcs = built_fcs ^ 32'h00000001;
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
        gmii_rxd = byte_value;
    end
endtask


task send_frame_variant;
    input integer variant;
    input [7:0]  seq;
    integer i;
    begin
        build_frame(variant, seq);

        for (i = 0; i < 7; i = i + 1)
            send_gmii_byte(8'h55);
        send_gmii_byte(8'hD5);

        for (i = 0; i < frame_body_len; i = i + 1)
            send_gmii_byte(frame_body[i]);

        send_gmii_byte(built_fcs[7:0]);
        send_gmii_byte(built_fcs[15:8]);
        send_gmii_byte(built_fcs[23:16]);
        send_gmii_byte(built_fcs[31:24]);

        @(negedge clk);
        gmii_rx_dv = 1'b0;
        gmii_rx_er = 1'b0;
        gmii_rxd   = 8'h00;

        repeat (16) @(posedge clk);
    end
endtask


// ============================================================
// Candidate / decision handshake helpers
// ============================================================

task wait_candidate;
    integer wait_cycle;
    begin : WAIT_CAND
        for (wait_cycle = 0; wait_cycle < 4000; wait_cycle = wait_cycle + 1) begin
            @(posedge clk);
            #1;
            if (candidate_valid)
                disable WAIT_CAND;
        end
        $display("ERROR: candidate timeout");
        error_count = error_count + 1;
        tc_error = tc_error + 1;
    end
endtask


task fire_candidate;
    begin
        @(negedge clk);
        candidate_ready = 1'b1;
        @(posedge clk);
        #1;
        candidate_ready = 1'b0;
        @(negedge clk);
    end
endtask


task decide;
    input accept;
    begin
        @(negedge clk);
        decision_valid  = 1'b1;
        decision_accept = accept;
        @(posedge clk);
        #1;
        @(negedge clk);
        decision_valid  = 1'b0;
        decision_accept = 1'b0;
    end
endtask


// ============================================================
// Counters
// ============================================================

integer candidate_count;
integer l2_crc_error_count;
integer base_candidate;


always @(posedge clk) begin
    if (rst) begin
        candidate_count     = 0;
        l2_crc_error_count  = 0;
    end
    else begin
        if (candidate_valid && candidate_ready)
            candidate_count = candidate_count + 1;
        if (l2_crc_error)
            l2_crc_error_count = l2_crc_error_count + 1;
    end
end


// ============================================================
// Reset
// ============================================================

task reset_dut;
    begin
        @(negedge clk);
        rst = 1'b1;
        gmii_rxd   = 8'h00;
        gmii_rx_dv = 1'b0;
        gmii_rx_er = 1'b0;
        candidate_ready  = 1'b0;
        decision_valid   = 1'b0;
        decision_accept  = 1'b0;
        payload_ready    = 1'b1;
        repeat (3) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;
        repeat (2) @(posedge clk);
        #1;
    end
endtask


// ============================================================
// Main
// ============================================================

initial begin

    rst = 1'b1;
    gmii_rxd   = 8'h00;
    gmii_rx_dv = 1'b0;
    gmii_rx_er = 1'b0;
    candidate_ready  = 1'b0;
    decision_valid   = 1'b0;
    decision_accept  = 1'b0;
    payload_ready    = 1'b1;

    error_count = 0;
    tc_error    = 0;


    // ====================================================
    // TC-M5-D2a-01 reset / idle
    // ====================================================

    reset_dut();
    tc_error = 0;

    if (candidate_valid !== 1'b0 || candidate_outstanding !== 1'b0) begin
        $display("ERROR: candidate not idle after reset");
        error_count = error_count + 1; tc_error = tc_error + 1;
    end

    if (tc_error == 0)
        $display("TC-M5-D2a-01 PASS: reset / idle");


    // ====================================================
    // TC-M5-D2a-02 valid candidate + accept/replay
    // ====================================================

    tc_error = 0;

    send_frame_variant(CASE_VALID_VL0, 8'h10);
    wait_candidate();

    if (!candidate_valid) begin
        $display("ERROR: no candidate for valid frame");
        error_count = error_count + 1; tc_error = tc_error + 1;
    end

    if (candidate_vl_index !== 2'd0 ||
        candidate_sequence !== 8'h10 ||
        candidate_payload_length !== 11'd4) begin
        $display("ERROR: candidate metadata wrong vl=%0d seq=%0d len=%0d",
                 candidate_vl_index, candidate_sequence, candidate_payload_length);
        error_count = error_count + 1; tc_error = tc_error + 1;
    end

    fire_candidate();
    decide(1'b1);

    // Hold payload with backpressure so we can observe the replay.
    payload_ready = 1'b0;

    repeat (3) @(posedge clk);
    #1;

    if (payload_valid !== 1'b1) begin
        $display("ERROR: payload not replayed after accept");
        error_count = error_count + 1; tc_error = tc_error + 1;
    end

    if (payload_data !== 8'h00) begin
        $display("ERROR: payload first byte wrong");
        error_count = error_count + 1; tc_error = tc_error + 1;
    end

    // Drain payload.
    payload_ready = 1'b1;
    repeat (6) @(posedge clk);
    #1;

    if (tc_error == 0)
        $display("TC-M5-D2a-02 PASS: valid candidate + accept/replay");


    // ====================================================
    // TC-M5-D2a-03 candidate hold under decision delay
    // ====================================================

    tc_error = 0;

    send_frame_variant(CASE_VALID_VL0, 8'h20);
    wait_candidate();

    // Hold candidate for 8 clocks without accepting.
    repeat (8) @(posedge clk);
    #1;

    if (!candidate_valid ||
        candidate_sequence !== 8'h20 ||
        candidate_vl_index !== 2'd0) begin
        $display("ERROR: candidate did not hold stable");
        error_count = error_count + 1; tc_error = tc_error + 1;
    end

    fire_candidate();
    decide(1'b1);
    repeat (6) @(posedge clk);
    #1;

    if (tc_error == 0)
        $display("TC-M5-D2a-03 PASS: candidate hold under decision delay");


    // ====================================================
    // TC-M5-D2a-04 unknown VL discarded before D1
    // ====================================================

    tc_error = 0;

    // Capture current candidate count.
    send_frame_variant(CASE_UNKNOWN, 8'h30);

    // Wait enough time for the frame to be fully processed.
    repeat (40) @(posedge clk);
    #1;

    if (candidate_valid !== 1'b0) begin
        $display("ERROR: unknown VL produced a candidate");
        error_count = error_count + 1; tc_error = tc_error + 1;
    end

    if (tc_error == 0)
        $display("TC-M5-D2a-04 PASS: unknown VL discarded before D1");


    // ====================================================
    // TC-M5-D2a-05 bad FCS rejected at L2
    // ====================================================

    tc_error = 0;

    send_frame_variant(CASE_BAD_FCS, 8'h40);
    repeat (40) @(posedge clk);
    #1;

    if (l2_crc_error_count == 0) begin
        $display("ERROR: bad FCS not detected at L2");
        error_count = error_count + 1; tc_error = tc_error + 1;
    end

    if (candidate_valid !== 1'b0) begin
        $display("ERROR: bad FCS produced a candidate");
        error_count = error_count + 1; tc_error = tc_error + 1;
    end

    if (tc_error == 0)
        $display("TC-M5-D2a-05 PASS: bad FCS rejected at L2");


    // ====================================================
    // TC-M5-D2a-06 sequence left untouched for D1
    // ====================================================

    tc_error = 0;

    // Two identical-sequence valid frames must each produce a
    // candidate (no duplicate elimination inside D2a).

    base_candidate = candidate_count;

    send_frame_variant(CASE_VALID_VL0, 8'h66);
    wait_candidate();
    if (candidate_sequence !== 8'h66) begin
        $display("ERROR: first 0x66 sequence wrong");
        error_count = error_count + 1; tc_error = tc_error + 1;
    end
    fire_candidate();
    decide(1'b1);
    repeat (6) @(posedge clk);
    #1;

    send_frame_variant(CASE_VALID_VL0, 8'h66);
    wait_candidate();
    if (candidate_sequence !== 8'h66) begin
        $display("ERROR: second 0x66 sequence wrong");
        error_count = error_count + 1; tc_error = tc_error + 1;
    end
    fire_candidate();
    decide(1'b1);
    repeat (6) @(posedge clk);
    #1;

    if ((candidate_count - base_candidate) != 2) begin
        $display("ERROR: candidate_count delta=%0d (expected 2, duplicate NOT eliminated)",
                 candidate_count - base_candidate);
        error_count = error_count + 1; tc_error = tc_error + 1;
    end

    if (tc_error == 0)
        $display("TC-M5-D2a-06 PASS: sequence left untouched for D1");


    // ====================================================
    // TC-M5-D2a-07 payload replay backpressure
    // ====================================================

    tc_error = 0;

    payload_ready = 1'b0;

    send_frame_variant(CASE_VALID_VL0, 8'h77);
    wait_candidate();
    fire_candidate();
    decide(1'b1);

    // Payload should be asserted but held by backpressure.
    repeat (4) @(posedge clk);
    #1;

    if (payload_valid !== 1'b1) begin
        $display("ERROR: payload not asserted during backpressure");
        error_count = error_count + 1; tc_error = tc_error + 1;
    end

    if (payload_data !== 8'h00) begin
        $display("ERROR: payload data wrong during backpressure");
        error_count = error_count + 1; tc_error = tc_error + 1;
    end

    // Release.
    payload_ready = 1'b1;
    repeat (8) @(posedge clk);
    #1;

    if (tc_error == 0)
        $display("TC-M5-D2a-07 PASS: payload replay backpressure");


    // ====================================================
    // FINAL
    // ====================================================

    $display("");
    $display("==============================================");
    if (commit_overflow_error !== 1'b0) begin
        $display("ERROR: commit_overflow_error asserted");
        error_count = error_count + 1;
    end
    if (error_count == 0)
        $display("M5-D2a GMII RX FRAME PARSER ALL TESTS PASS");
    else
        $display("M5-D2a FAILED: %0d error(s)", error_count);
    $display("==============================================");

    #20;
    $finish;
end


endmodule
