`timescale 1ns / 1ps

module tb_afdx_snmp_transaction;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst = 1;
    reg req = 0;
    reg req_op = 0;
    reg [7:0] req_object_id = 0;
    wire m6b_req_valid;
    wire m6b_req_op;
    wire [7:0] m6b_req_object_id;
    reg m6b_rsp_valid = 0;
    reg m6b_rsp_error = 0;
    reg [1:0] m6b_rsp_error_code = 0;
    reg [7:0] m6b_rsp_object_id = 0;
    reg [7:0] m6b_rsp_asn1_type = 0;
    reg [31:0] m6b_rsp_value = 0;
    wire m6c_req;
    wire [7:0] m6c_object_id;
    wire [7:0] m6c_asn1_type;
    wire [31:0] m6c_value;
    wire [1:0] m6c_response_status;
    reg m6c_done = 0;
    reg m6c_error = 0;
    reg [6:0] m6c_varbind_length = 0;
    reg [511:0] m6c_varbind_bytes = 0;
    wire rsp_valid;
    wire rsp_error;
    wire [2:0] rsp_error_code;
    wire [7:0] rsp_object_id;
    wire [6:0] rsp_length;
    wire [511:0] rsp_bytes;
    integer errors;
    integer test_id;

    afdx_snmp_transaction u_dut (
        .clk(clk), .rst(rst), .req(req), .req_op(req_op), .req_object_id(req_object_id),
        .m6b_req_valid(m6b_req_valid), .m6b_req_op(m6b_req_op), .m6b_req_object_id(m6b_req_object_id),
        .m6b_rsp_valid(m6b_rsp_valid), .m6b_rsp_error(m6b_rsp_error), .m6b_rsp_error_code(m6b_rsp_error_code),
        .m6b_rsp_object_id(m6b_rsp_object_id), .m6b_rsp_asn1_type(m6b_rsp_asn1_type), .m6b_rsp_value(m6b_rsp_value),
        .m6c_req(m6c_req), .m6c_object_id(m6c_object_id), .m6c_asn1_type(m6c_asn1_type),
        .m6c_value(m6c_value), .m6c_response_status(m6c_response_status), .m6c_done(m6c_done),
        .m6c_error(m6c_error), .m6c_varbind_length(m6c_varbind_length), .m6c_varbind_bytes(m6c_varbind_bytes),
        .rsp_valid(rsp_valid), .rsp_error(rsp_error), .rsp_error_code(rsp_error_code),
        .rsp_object_id(rsp_object_id), .rsp_length(rsp_length), .rsp_bytes(rsp_bytes)
    );

    task automatic run_case;
        input integer id;
        input op;
        input [7:0] object_id;
        input m6b_error;
        input [1:0] m6b_code;
        input [7:0] returned_id;
        input [7:0] returned_type;
        input [31:0] returned_value;
        input codec_error;
        input [6:0] expected_length;
        input expected_error;
        input [2:0] expected_code;
        begin
            test_id = id;
            @(negedge clk); req <= 1; req_op <= op; req_object_id <= object_id;
            @(negedge clk); req <= 0;
            wait (m6b_req_valid);
            @(negedge clk);
            m6b_rsp_valid <= 1; m6b_rsp_error <= m6b_error; m6b_rsp_error_code <= m6b_code;
            m6b_rsp_object_id <= returned_id; m6b_rsp_asn1_type <= returned_type; m6b_rsp_value <= returned_value;
            @(negedge clk); m6b_rsp_valid <= 0;
            if (!m6b_error) begin
                wait (m6c_req);
                @(negedge clk); m6c_done <= 1; m6c_error <= codec_error;
                m6c_varbind_length <= expected_length;
                m6c_varbind_bytes <= {424'd0, 88'h300A060801030601040101};
                @(negedge clk); m6c_done <= 0;
            end
            wait (rsp_valid);
            if ((rsp_error !== expected_error) || (rsp_error_code !== expected_code) ||
                (rsp_object_id !== returned_id) || (rsp_length !== expected_length)) begin
                $display("M6D-I-%02d FAIL: err=%b code=%d obj=%d len=%d", id, rsp_error, rsp_error_code, rsp_object_id, rsp_length);
                errors = errors + 1;
            end else begin
                $display("M6D-I-%02d PASS", id);
            end
            @(negedge clk);
        end
    endtask

    initial begin
        errors = 0;
        #20; rst = 0;
        run_case(1, 0, 8'd1, 0, 0, 8'd1, 8'h02, 32'd7, 0, 7'd13, 0, 0);
        run_case(2, 0, 8'd2, 0, 0, 8'd2, 8'h41, 32'd99, 0, 7'd13, 0, 0);
        run_case(3, 0, 8'd3, 0, 0, 8'd3, 8'h43, 32'd1234, 0, 7'd13, 0, 0);
        run_case(4, 1, 8'd0, 0, 0, 8'd1, 8'h02, 32'd7, 0, 7'd13, 0, 0);
        run_case(5, 1, 8'd24, 0, 0, 8'd25, 8'h41, 32'd25, 0, 7'd13, 0, 0);
        run_case(6, 1, 8'd25, 1, 2, 8'd25, 0, 0, 0, 0, 1, 2);
        run_case(7, 0, 8'd0, 1, 1, 8'd0, 0, 0, 0, 0, 1, 1);
        run_case(8, 0, 8'd26, 1, 1, 8'd26, 0, 0, 0, 0, 1, 1);
        run_case(9, 0, 8'd6, 1, 3, 8'd6, 8'h41, 0, 0, 0, 1, 3);
        run_case(10, 0, 8'd1, 0, 0, 8'd1, 8'h02, 7, 1, 0, 1, 4);
        $display("M6D transaction errors: %0d", errors);
        if (errors == 0) $display("M6D SNMP TRANSACTION PASS");
        else $display("M6D SNMP TRANSACTION FAIL");
        $finish;
    end
endmodule
