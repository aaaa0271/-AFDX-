`timescale 1ns / 1ps

module tb_afdx_vl_identifier;


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
// DUT input
// ============================================================

reg        meta_valid;

reg [47:0] dst_mac;

reg [31:0] src_ip;
reg [31:0] dst_ip;

reg [15:0] udp_src_port;
reg [15:0] udp_dst_port;

reg [10:0] payload_length;


// ============================================================
// DUT output
// ============================================================

wire        result_valid;

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


integer error_count;


// ============================================================
// DUT
// ============================================================

afdx_vl_identifier dut (
    .cfg_table(672'd0),

    .clk                    (clk),
    .rst                    (rst),

    .meta_valid             (meta_valid),

    .dst_mac                (dst_mac),

    .src_ip                 (src_ip),
    .dst_ip                 (dst_ip),

    .udp_src_port           (udp_src_port),
    .udp_dst_port           (udp_dst_port),

    .payload_length         (payload_length),

    .result_valid           (result_valid),

    .vl_accept              (vl_accept),
    .vl_reject              (vl_reject),

    .vl_index               (vl_index),
    .vl_id                  (vl_id),
    .vl_lmax                (vl_lmax),

    .unknown_vl_error       (unknown_vl_error),
    .disabled_vl_error      (disabled_vl_error),

    .ip_whitelist_error     (ip_whitelist_error),
    .udp_whitelist_error    (udp_whitelist_error),

    .length_whitelist_error (length_whitelist_error)

);


// ============================================================
// Apply metadata
// ============================================================

task apply_meta;

    input [47:0] t_dst_mac;

    input [31:0] t_src_ip;
    input [31:0] t_dst_ip;

    input [15:0] t_udp_src;
    input [15:0] t_udp_dst;

    input [10:0] t_payload_length;

    begin

        @(negedge clk);

        dst_mac        = t_dst_mac;

        src_ip         = t_src_ip;
        dst_ip         = t_dst_ip;

        udp_src_port   = t_udp_src;
        udp_dst_port   = t_udp_dst;

        payload_length = t_payload_length;

        meta_valid = 1'b1;


        @(negedge clk);

        meta_valid = 1'b0;

        #1;

    end

endtask


// ============================================================
// Check
// ============================================================

task check_result;

    input integer tc;

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

    integer base_error;

    begin

        base_error = error_count;

        if (result_valid !== 1'b1) begin
            $display("TC%0d ERROR: result_valid", tc);
            error_count = error_count + 1;
        end

        if (vl_accept !== exp_accept) begin
            $display("TC%0d ERROR: vl_accept", tc);
            error_count = error_count + 1;
        end

        if (vl_reject !== exp_reject) begin
            $display("TC%0d ERROR: vl_reject", tc);
            error_count = error_count + 1;
        end

        if (vl_index !== exp_index) begin
            $display(
                "TC%0d ERROR: vl_index expected %0d got %0d",
                tc,
                exp_index,
                vl_index
            );
            error_count = error_count + 1;
        end

        if (vl_id !== exp_id) begin
            $display(
                "TC%0d ERROR: vl_id expected %04h got %04h",
                tc,
                exp_id,
                vl_id
            );
            error_count = error_count + 1;
        end

        if (vl_lmax !== exp_lmax) begin
            $display(
                "TC%0d ERROR: LMAX expected %0d got %0d",
                tc,
                exp_lmax,
                vl_lmax
            );
            error_count = error_count + 1;
        end

        if (unknown_vl_error !== exp_unknown) begin
            $display("TC%0d ERROR: unknown_vl_error", tc);
            error_count = error_count + 1;
        end

        if (disabled_vl_error !== exp_disabled) begin
            $display("TC%0d ERROR: disabled_vl_error", tc);
            error_count = error_count + 1;
        end

        if (ip_whitelist_error !== exp_ip) begin
            $display("TC%0d ERROR: ip_whitelist_error", tc);
            error_count = error_count + 1;
        end

        if (udp_whitelist_error !== exp_udp) begin
            $display("TC%0d ERROR: udp_whitelist_error", tc);
            error_count = error_count + 1;
        end

        if (length_whitelist_error !== exp_length) begin
            $display("TC%0d ERROR: length_whitelist_error", tc);
            error_count = error_count + 1;
        end


        if (error_count == base_error)
            $display("TEST %0d PASS", tc);
        else
            $display("TEST %0d FAIL", tc);

    end

endtask


// ============================================================
// Main
// ============================================================

initial begin

    error_count = 0;

    rst = 1'b1;

    meta_valid = 1'b0;

    dst_mac = 48'd0;

    src_ip = 32'd0;
    dst_ip = 32'd0;

    udp_src_port = 16'd0;
    udp_dst_port = 16'd0;

    payload_length = 11'd0;


    repeat (5)
        @(posedge clk);

    @(negedge clk);
    rst = 1'b0;


    // --------------------------------------------------------
    // TC1 Valid VL0
    // --------------------------------------------------------

    apply_meta(
        48'h020000000002,
        32'h0A000001,
        32'h0A000002,
        16'd10000,
        16'd10001,
        11'd4
    );

    check_result(
        1,
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
    // TC2 Valid VL1
    // --------------------------------------------------------

    apply_meta(
        48'h020000000003,
        32'h0A000001,
        32'h0A000003,
        16'd10000,
        16'd20001,
        11'd4
    );

    check_result(
        2,
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
    // TC3 Unknown VL
    // --------------------------------------------------------

    apply_meta(
        48'h020000000099,
        32'h0A000001,
        32'h0A000002,
        16'd10000,
        16'd10001,
        11'd4
    );

    check_result(
        3,
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
    // TC4 Wrong IP
    // --------------------------------------------------------

    apply_meta(
        48'h020000000002,
        32'h0A000063,
        32'h0A000002,
        16'd10000,
        16'd10001,
        11'd4
    );

    check_result(
        4,
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
    // TC5 Wrong UDP destination port
    // --------------------------------------------------------

    apply_meta(
        48'h020000000002,
        32'h0A000001,
        32'h0A000002,
        16'd10000,
        16'd12345,
        11'd4
    );

    check_result(
        5,
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
    // TC6 VL0 LMAX violation
    // --------------------------------------------------------

    apply_meta(
        48'h020000000002,
        32'h0A000001,
        32'h0A000002,
        16'd10000,
        16'd10001,
        11'd513
    );

    check_result(
        6,
        1'b0,
        1'b1,
        2'd0,
        16'h0002,
        11'd512,
        1'b0,
        1'b0,
        1'b0,
        1'b0,
        1'b1
    );


    // --------------------------------------------------------
    // TC7 Disabled VL2
    // --------------------------------------------------------

    apply_meta(
        48'h020000000004,
        32'h0A000001,
        32'h0A000004,
        16'd10000,
        16'd30001,
        11'd4
    );

    check_result(
        7,
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
    // Final
    // --------------------------------------------------------

    if (error_count == 0) begin

        $display("");
        $display("==============================================");
        $display("M3-C VL IDENTIFICATION TEST PASS");
        $display("VL0 VERIFIED");
        $display("VL1 VERIFIED");
        $display("UNKNOWN VL VERIFIED");
        $display("DISABLED VL VERIFIED");
        $display("IP WHITELIST VERIFIED");
        $display("UDP WHITELIST VERIFIED");
        $display("LMAX VERIFIED");
        $display("==============================================");
        $display("");

    end
    else begin

        $fatal(
            1,
            "M3-C VL IDENTIFICATION TEST FAIL: %0d errors",
            error_count
        );

    end

    $finish;

end


// ============================================================
// Timeout
// ============================================================

initial begin

    #20000;

    $fatal(
        1,
        "M3-C STANDALONE TIMEOUT"
    );

end


endmodule
