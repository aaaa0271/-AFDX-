`timescale 1ns / 1ps

module tb_afdx_snmp_response_builder;
    localparam integer MAX_VARBIND_BYTES = 64;
    localparam integer MAX_MSG_BYTES = 96;

    reg clk;
    reg rst_n;
    reg req;
    reg [31:0] request_id;
    reg [MAX_VARBIND_BYTES*8-1:0] varbind_data;
    reg [7:0] varbind_length;
    wire done;
    wire valid;
    wire [7:0] error_code;
    wire [MAX_MSG_BYTES*8-1:0] msg_data;
    wire [7:0] msg_length;
    integer errors;
    integer timeout_count;

    afdx_snmp_response_builder #(
        .MAX_VARBIND_BYTES(MAX_VARBIND_BYTES),
        .MAX_MSG_BYTES(MAX_MSG_BYTES)
    ) dut (
        .clk(clk), .rst_n(rst_n), .req(req), .request_id(request_id),
        .varbind_data(varbind_data), .varbind_length(varbind_length),
        .done(done), .valid(valid), .error_code(error_code),
        .msg_data(msg_data), .msg_length(msg_length)
    );

    always #5 clk = ~clk;

    function [7:0] msg_byte;
        input integer index;
        begin
            msg_byte = msg_data[(MAX_MSG_BYTES*8-1)-index*8 -: 8];
        end
    endfunction

    task set_vb_byte;
        input integer index;
        input [7:0] value;
        begin
            varbind_data[(MAX_VARBIND_BYTES*8-1)-index*8 -: 8] = value;
        end
    endtask

    task pulse_req;
        begin
            @(negedge clk); req = 1'b1;
            @(posedge clk); #1;
            req = 1'b0;
        end
    endtask

    task wait_done;
        begin
            timeout_count = 0;
            while ((done !== 1'b1) && (timeout_count < 20)) begin
                @(posedge clk); #1;
                timeout_count = timeout_count + 1;
            end
            if (done !== 1'b1) begin
                $display("ERROR: timeout waiting for done");
                errors = errors + 1;
            end
        end
    endtask

    task check_byte;
        input integer index;
        input [7:0] expected;
        begin
            if (msg_byte(index) !== expected) begin
                $display("ERROR byte[%0d]: got=%02h expected=%02h", index, msg_byte(index), expected);
                errors = errors + 1;
            end
        end
    endtask

    task load_mock_varbind;
        begin
            varbind_data = {MAX_VARBIND_BYTES*8{1'b0}};
            varbind_length = 8'd9;
            set_vb_byte(0, 8'h30); set_vb_byte(1, 8'h07);
            set_vb_byte(2, 8'h06); set_vb_byte(3, 8'h02);
            set_vb_byte(4, 8'h2B); set_vb_byte(5, 8'h06);
            set_vb_byte(6, 8'h02); set_vb_byte(7, 8'h01);
            set_vb_byte(8, 8'h05);
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        req = 1'b0;
        request_id = 32'd0;
        varbind_data = {MAX_VARBIND_BYTES*8{1'b0}};
        varbind_length = 8'd0;
        errors = 0;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        $display("M6D-D-01 basic valid response");
        load_mock_varbind();
        request_id = 32'h12345678;
        pulse_req();
        wait_done();
        if ((valid === 1'b1) && (error_code === 8'd0))
            $display("M6D-D-01 PASS");
        else begin
            $display("M6D-D-01 FAIL valid=%b err=%0d", valid, error_code);
            errors = errors + 1;
        end

        $display("M6D-D-02 envelope fields");
        check_byte(0, 8'h30); check_byte(1, 8'h24);
        check_byte(2, 8'h02); check_byte(3, 8'h01); check_byte(4, 8'h01);
        check_byte(5, 8'h04); check_byte(6, 8'h06);
        check_byte(7, 8'h70); check_byte(8, 8'h75); check_byte(9, 8'h62);
        check_byte(10, 8'h6C); check_byte(11, 8'h69); check_byte(12, 8'h63);
        check_byte(13, 8'hA2); check_byte(14, 8'h17);
        $display("M6D-D-02 PASS");

        $display("M6D-D-03 request-id echo");
        check_byte(15, 8'h02); check_byte(16, 8'h04);
        check_byte(17, 8'h12); check_byte(18, 8'h34);
        check_byte(19, 8'h56); check_byte(20, 8'h78);
        $display("M6D-D-03 PASS");

        $display("M6D-D-04 noError fields");
        check_byte(21, 8'h02); check_byte(22, 8'h01); check_byte(23, 8'h00);
        check_byte(24, 8'h02); check_byte(25, 8'h01); check_byte(26, 8'h00);
        $display("M6D-D-04 PASS");

        $display("M6D-D-05 VarBind preservation");
        check_byte(27, 8'h30); check_byte(28, 8'h09);
        check_byte(29, 8'h30); check_byte(30, 8'h07);
        check_byte(31, 8'h06); check_byte(32, 8'h02);
        check_byte(33, 8'h2B); check_byte(34, 8'h06);
        check_byte(35, 8'h02); check_byte(36, 8'h01); check_byte(37, 8'h05);
        if (msg_length !== 8'd38) begin
            $display("ERROR msg_length=%0d expected=38", msg_length);
            errors = errors + 1;
        end
        $display("M6D-D-05 PASS");

        $display("M6D-D-06 invalid VarBind length");
        varbind_length = 8'd0;
        request_id = 32'h01020304;
        pulse_req();
        wait_done();
        if ((valid === 1'b0) && (error_code === 8'd1))
            $display("M6D-D-06 PASS");
        else begin
            $display("M6D-D-06 FAIL valid=%b err=%0d", valid, error_code);
            errors = errors + 1;
        end

        $display("========================================");
        if (errors == 0)
            $display("M6D-D RESPONSE BUILDER PASS");
        else
            $display("M6D-D RESPONSE BUILDER FAIL errors=%0d", errors);
        $display("M6D-D builder errors: %0d", errors);
        $display("========================================");
        $finish;
    end
endmodule
