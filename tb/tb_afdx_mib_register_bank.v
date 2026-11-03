`timescale 1ns / 1ps

module tb_afdx_mib_register_bank;
    reg clk, rst_n, req_valid, req_op;
    reg [7:0] req_object_id;
    wire rsp_valid, rsp_error;
    wire [1:0] rsp_error_code;
    wire [7:0] rsp_object_id, rsp_asn1_type, m6a_rd_addr;
    wire [31:0] rsp_value;
    reg [31:0] m6a_rd_data;
    reg m6a_rd_valid;
    integer errors;

    localparam OP_GET = 1'b0;
    localparam OP_GETNEXT = 1'b1;
    localparam [7:0] ASN1_INTEGER = 8'h02;
    localparam [7:0] ASN1_COUNTER32 = 8'h41;
    localparam [7:0] ASN1_TIMETICKS = 8'h43;

    afdx_mib_register_bank dut (
        .clk(clk), .rst_n(rst_n), .req_valid(req_valid), .req_op(req_op),
        .req_object_id(req_object_id), .rsp_valid(rsp_valid), .rsp_error(rsp_error),
        .rsp_error_code(rsp_error_code), .rsp_object_id(rsp_object_id),
        .rsp_asn1_type(rsp_asn1_type), .rsp_value(rsp_value),
        .m6a_rd_addr(m6a_rd_addr), .m6a_rd_data(m6a_rd_data),
        .m6a_rd_valid(m6a_rd_valid)
    );

    initial begin clk = 1'b0; forever #5 clk = ~clk; end

    always @(*) begin
        m6a_rd_valid = 1'b1;
        case (m6a_rd_addr)
            8'h00: m6a_rd_data = 32'h0006_0A01;
            8'h01: m6a_rd_data = 32'h0000_0011;
            8'h02: m6a_rd_data = 32'h0000_1234;
            8'h03: m6a_rd_data = 32'h0000_003F;
            8'h04: m6a_rd_data = 32'h0000_0003;
            8'h10: m6a_rd_data = 32'hA600_0010;
            8'h11: m6a_rd_data = 32'hA600_0011;
            8'h12: m6a_rd_data = 32'hA600_0012;
            8'h13: m6a_rd_data = 32'hA600_0013;
            8'h14: m6a_rd_data = 32'hA600_0014;
            8'h15: m6a_rd_data = 32'hA600_0015;
            8'h16: m6a_rd_data = 32'hA600_0016;
            8'h17: m6a_rd_data = 32'hA600_0017;
            8'h20: m6a_rd_data = 32'hA600_0020;
            8'h21: m6a_rd_data = 32'hA600_0021;
            8'h22: m6a_rd_data = 32'hA600_0022;
            8'h23: m6a_rd_data = 32'hA600_0023;
            8'h24: m6a_rd_data = 32'hA600_0024;
            8'h25: m6a_rd_data = 32'hA600_0025;
            8'h26: m6a_rd_data = 32'hA600_0026;
            8'h27: m6a_rd_data = 32'hA600_0027;
            8'h28: m6a_rd_data = 32'hA600_0028;
            8'h29: m6a_rd_data = 32'hA600_0029;
            8'h2A: m6a_rd_data = 32'hA600_002A;
            8'h2B: m6a_rd_data = 32'hA600_002B;
            default: begin m6a_rd_data = 32'd0; m6a_rd_valid = 1'b0; end
        endcase
    end

    task send_request;
        input op; input [7:0] object_id;
        begin
            @(negedge clk); req_op = op; req_object_id = object_id; req_valid = 1'b1;
            @(negedge clk); req_valid = 1'b0;
        end
    endtask

    task check_success;
        input [7:0] expected_object; input [7:0] expected_type; input [31:0] expected_value;
        begin
            wait (rsp_valid === 1'b1); #1;
            if (rsp_error !== 1'b0 || rsp_object_id !== expected_object ||
                rsp_asn1_type !== expected_type || rsp_value !== expected_value) begin
                $display("ERROR: success expected obj=%02h type=%02h value=%08h got err=%0d obj=%02h type=%02h value=%08h", expected_object, expected_type, expected_value, rsp_error, rsp_object_id, rsp_asn1_type, rsp_value);
                errors = errors + 1;
            end
            @(negedge clk);
        end
    endtask

    task check_error;
        input [1:0] expected_code;
        begin
            wait (rsp_valid === 1'b1); #1;
            if (rsp_error !== 1'b1 || rsp_error_code !== expected_code) begin
                $display("ERROR: error expected=%0d got err=%0d code=%0d", expected_code, rsp_error, rsp_error_code);
                errors = errors + 1;
            end
            @(negedge clk);
        end
    endtask

    initial begin
        rst_n = 1'b0; req_valid = 1'b0; req_op = OP_GET; req_object_id = 0; errors = 0;
        repeat (4) @(posedge clk); rst_n = 1'b1; repeat (2) @(posedge clk);

        send_request(OP_GET, 8'h01); check_success(8'h01, ASN1_INTEGER, 32'h0006_0A01); $display("TC-M6B-01 PASS: GET version");
        send_request(OP_GET, 8'h03); check_success(8'h03, ASN1_TIMETICKS, 32'h0000_1234); $display("TC-M6B-02 PASS: TimeTicks mapping");
        send_request(OP_GET, 8'h0A); check_success(8'h0A, ASN1_COUNTER32, 32'hA600_0014); $display("TC-M6B-03 PASS: RX MIB mapping");
        send_request(OP_GET, 8'h15); check_success(8'h15, ASN1_COUNTER32, 32'hA600_0027); $display("TC-M6B-04 PASS: TX MIB mapping");
        send_request(OP_GETNEXT, 8'h05); check_success(8'h06, ASN1_COUNTER32, 32'hA600_0010); $display("TC-M6B-05 PASS: GETNEXT system->RX");
        send_request(OP_GETNEXT, 8'h0D); check_success(8'h0E, ASN1_COUNTER32, 32'hA600_0020); $display("TC-M6B-06 PASS: GETNEXT RX->TX");
        send_request(OP_GETNEXT, 8'h00); check_success(8'h01, ASN1_INTEGER, 32'h0006_0A01); $display("TC-M6B-07 PASS: GETNEXT first object");
        send_request(OP_GET, 8'h00); check_error(2'd1); $display("TC-M6B-08 PASS: noSuchObject");
        send_request(OP_GETNEXT, 8'h19); check_error(2'd2); $display("TC-M6B-09 PASS: endOfMibView");
        send_request(OP_GET, 8'h19); check_success(8'h19, ASN1_COUNTER32, 32'hA600_002B); $display("TC-M6B-10 PASS: last MIB object");

        if (errors == 0) begin
            $display("======================================");
            $display("M6B MIB REGISTER BANK ALL TESTS PASS");
            $display("======================================");
            #20 $finish;
        end else $fatal(1, "M6B FAILED: %0d errors", errors);
    end

    initial begin #100000 $fatal(1, "M6B timeout"); end
endmodule
