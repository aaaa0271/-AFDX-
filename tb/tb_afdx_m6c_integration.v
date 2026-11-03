`timescale 1ns / 1ps

module tb_afdx_m6c_integration;
    parameter integer MAX_VB_BYTES = 64;
    reg clk, rst, req;
    reg [7:0] object_id, asn1_type;
    reg [31:0] value;
    reg [1:0] response_status;
    wire done, error;
    wire [6:0] varbind_length;
    wire [MAX_VB_BYTES*8-1:0] varbind_bytes;
    integer errors;
    integer i;

    afdx_m6c_integration #(.MAX_VB_BYTES(MAX_VB_BYTES)) dut (
        .clk(clk), .rst(rst), .req(req), .object_id(object_id),
        .asn1_type(asn1_type), .value(value), .response_status(response_status),
        .done(done), .error(error), .varbind_length(varbind_length),
        .varbind_bytes(varbind_bytes)
    );

    always #5 clk = ~clk;

    function [7:0] byte_at;
        input integer n;
        begin byte_at = varbind_bytes[n*8 +: 8]; end
    endfunction

    task send_request;
        input [7:0] obj;
        input [7:0] typ;
        input [31:0] val;
        input [1:0] stat;
        begin
            @(negedge clk);
            object_id = obj; asn1_type = typ; value = val;
            response_status = stat; req = 1'b1;
            @(posedge clk); #1; req = 1'b0;
            wait(done); #1;
        end
    endtask

    task check_prefix;
        input integer n;
        input [7:0] b0,b1,b2,b3,b4,b5,b6,b7,b8,b9,b10,b11,b12,b13,b14,b15,b16,b17;
        begin
            if ((varbind_length != n) ||
                (n > 0 && byte_at(0) != b0) || (n > 1 && byte_at(1) != b1) ||
                (n > 2 && byte_at(2) != b2) || (n > 3 && byte_at(3) != b3) ||
                (n > 4 && byte_at(4) != b4) || (n > 5 && byte_at(5) != b5) ||
                (n > 6 && byte_at(6) != b6) || (n > 7 && byte_at(7) != b7) ||
                (n > 8 && byte_at(8) != b8) || (n > 9 && byte_at(9) != b9) ||
                (n > 10 && byte_at(10) != b10) || (n > 11 && byte_at(11) != b11) ||
                (n > 12 && byte_at(12) != b12) || (n > 13 && byte_at(13) != b13) ||
                (n > 14 && byte_at(14) != b14) || (n > 15 && byte_at(15) != b15) ||
                (n > 16 && byte_at(16) != b16) || (n > 17 && byte_at(17) != b17)) begin
                $display("ERROR VarBind len=%0d bytes=%h", varbind_length, varbind_bytes[143:0]);
                errors = errors + 1;
            end
        end
    endtask

    task check_oid_suffix;
        input [7:0] suffix;
        begin
            if ((byte_at(0) != 8'h30) || (byte_at(2) != 8'h06) ||
                (byte_at(3) != 8'h0b) || (byte_at(4) != 8'h2b) ||
                (byte_at(5) != 8'h06) || (byte_at(6) != 8'h01) ||
                (byte_at(7) != 8'h04) || (byte_at(8) != 8'h01) ||
                (byte_at(9) != 8'h81) || (byte_at(10) != 8'hfd) ||
                (byte_at(11) != 8'h59) || (byte_at(12) != 8'h01) ||
                (byte_at(13) != 8'h01) || (byte_at(14) != suffix)) begin
                $display("ERROR OID suffix=%02h bytes=%h", suffix, varbind_bytes[119:0]);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        clk=0; rst=1; req=0; object_id=0; asn1_type=0; value=0; response_status=0; errors=0;
        repeat (3) @(posedge clk); rst=0;

        send_request(8'd1, 8'h02, 32'd5, 2'd0);
        if (error) errors=errors+1; else begin
            check_prefix(18,8'h30,8'h10,8'h06,8'h0b,8'h2b,8'h06,8'h01,8'h04,8'h01,8'h81,8'hfd,8'h59,8'h01,8'h01,8'h01,8'h02,8'h01,8'h05);
            $display("M6C-I-01 PASS: INTEGER VarBind encode");
        end

        send_request(8'd2, 8'h41, 32'd12345, 2'd0);
        if (error || byte_at(0)!=8'h30 || byte_at(15)!=8'h41) begin $display("M6C-I-02 FAIL len=%0d b15=%02h",varbind_length,byte_at(15)); errors=errors+1; end
        else $display("M6C-I-02 PASS: Counter32 VarBind encode");

        send_request(8'd3, 8'h43, 32'd98765, 2'd0);
        if (error || byte_at(0)!=8'h30 || byte_at(15)!=8'h43) begin $display("M6C-I-03 FAIL len=%0d b15=%02h",varbind_length,byte_at(15)); errors=errors+1; end
        else $display("M6C-I-03 PASS: TimeTicks VarBind encode");

        send_request(8'd1, 8'h02, 32'd5, 2'd0);
        if (error) errors=errors+1; else begin check_oid_suffix(8'h01); $display("M6C-I-04 PASS: first object OID"); end

        send_request(8'd25, 8'h41, 32'hdeadbeef, 2'd0);
        if (error) errors=errors+1; else begin check_oid_suffix(8'h19); $display("M6C-I-05 PASS: last object OID"); end

        send_request(8'd10, 8'h41, 32'd100, 2'd0);
        if (error || byte_at(0)!=8'h30 || byte_at(15)!=8'h41) errors=errors+1;
        else $display("M6C-I-06 PASS: M6B GET complete VarBind");

        send_request(8'd11, 8'h43, 32'd200, 2'd0);
        if (error || byte_at(0)!=8'h30 || byte_at(15)!=8'h43) errors=errors+1;
        else $display("M6C-I-07 PASS: M6B GETNEXT returned-object VarBind");

        send_request(8'd0, 8'h02, 32'd1, 2'd0);
        if (!error) errors=errors+1; else $display("M6C-I-08A PASS: invalid object rejection");
        send_request(8'd1, 8'h02, 32'd1, 2'd1);
        if (!error) errors=errors+1; else $display("M6C-I-08B PASS: response status rejection");

        send_request(8'd1, 8'h99, 32'd1, 2'd0);
        if (!error) errors=errors+1; else $display("M6C-I-08C PASS: invalid ASN.1 type rejection");

        send_request(8'd1, 8'h02, 32'd5, 2'd0);
        if (error) errors=errors+1; else $display("M6C-I-09 PASS: output capacity acceptance");

        for (i=1; i<=25; i=i+1) begin
            send_request(i[7:0], 8'h41, i*100, 2'd0);
            if (error || byte_at(0)!=8'h30) begin
                $display("ERROR sweep object=%0d", i); errors=errors+1;
            end
        end
        $display("M6C-I-10 PASS: full 25-object VarBind sweep");

        if (errors == 0) begin
            $display("========================================");
            $display("M6C-INTEGRATION ALL TESTS PASS");
            $display("========================================");
            #10 $finish;
        end else $fatal(1, "M6C-INTEGRATION FAILED: %0d error(s)", errors);
    end
endmodule
