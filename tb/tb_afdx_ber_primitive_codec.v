`timescale 1ns / 1ps

module tb_afdx_ber_primitive_codec;
    reg encode_valid, decode_valid;
    reg [7:0] encode_type, decode_type;
    reg [31:0] encode_value;
    reg [3:0] decode_len;
    reg [55:0] decode_tlv;
    wire encode_done, encode_error, decode_done, decode_error;
    wire [3:0] encode_len;
    wire [55:0] encode_tlv;
    wire [31:0] decode_value;
    integer errors;

    afdx_ber_primitive_codec dut (
        .encode_valid(encode_valid), .encode_type(encode_type),
        .encode_value(encode_value), .encode_done(encode_done),
        .encode_error(encode_error), .encode_len(encode_len),
        .encode_tlv(encode_tlv), .decode_valid(decode_valid),
        .decode_type(decode_type), .decode_len(decode_len),
        .decode_tlv(decode_tlv), .decode_done(decode_done),
        .decode_error(decode_error), .decode_value(decode_value)
    );

    task encode_decode;
        input [7:0] typ;
        input [31:0] value;
        begin
            encode_type = typ; encode_value = value; encode_valid = 1'b1; #1;
            if (!encode_done || encode_error) begin
                $display("ERROR encode type=%02h value=%08h", typ, value); errors = errors + 1;
            end
            decode_type = typ; decode_len = encode_len; decode_tlv = encode_tlv; decode_valid = 1'b1; #1;
            if (!decode_done || decode_error || decode_value !== value) begin
                $display("ERROR roundtrip type=%02h value=%08h decoded=%08h", typ, value, decode_value); errors = errors + 1;
            end
            encode_valid = 1'b0; decode_valid = 1'b0; #1;
        end
    endtask

    initial begin
        errors = 0; encode_valid = 0; decode_valid = 0; encode_type = 0;
        encode_value = 0; decode_type = 0; decode_len = 0; decode_tlv = 0;

        encode_decode(8'h02, 32'h0000_0000);
        encode_decode(8'h02, 32'h0000_007F);
        encode_decode(8'h02, 32'h0000_0080);
        encode_decode(8'h02, 32'hFFFF_FF80);
        encode_decode(8'h02, 32'hFFFF_FFFF);
        encode_decode(8'h41, 32'h0000_007F);
        encode_decode(8'h41, 32'h0000_0080);
        encode_decode(8'h41, 32'h7FFF_FFFF);
        encode_decode(8'h41, 32'h8000_0000);
        encode_decode(8'h41, 32'hFFFF_FFFF);
        encode_decode(8'h43, 32'h0000_1234);
        encode_decode(8'h43, 32'hDEAD_BEEF);

        encode_type = 8'h99; encode_value = 0; encode_valid = 1'b1; #1;
        if (!encode_error) begin $display("ERROR unsupported type accepted"); errors = errors + 1; end
        encode_valid = 1'b0;

        decode_type = 8'h02; decode_len = 4'd4; decode_tlv = 56'h02_01_80_00000000; decode_valid = 1'b1; #1;
        if (!decode_error) begin $display("ERROR malformed integer accepted"); errors = errors + 1; end
        decode_valid = 1'b0;

        if (errors == 0) begin
            $display("M6C-A-01 PASS: INTEGER encode/decode");
            $display("M6C-A-02 PASS: Counter32 encode/decode");
            $display("M6C-A-03 PASS: TimeTicks encode/decode");
            $display("M6C-A-04 PASS: unsupported type rejection");
            $display("M6C-A-05 PASS: malformed TLV rejection");
            $display("M6C-A BER PRIMITIVE ALL TESTS PASS");
            #1 $finish;
        end else $fatal(1, "M6C-A failed: %0d error(s)", errors);
    end
endmodule
