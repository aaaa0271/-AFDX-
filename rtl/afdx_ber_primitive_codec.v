`timescale 1ns / 1ps

module afdx_ber_primitive_codec (
    input  wire        encode_valid,
    input  wire [7:0]  encode_type,
    input  wire [31:0] encode_value,
    output reg         encode_done,
    output reg         encode_error,
    output reg [3:0]   encode_len,
    output reg [55:0]  encode_tlv,

    input  wire        decode_valid,
    input  wire [7:0]  decode_type,
    input  wire [3:0]  decode_len,
    input  wire [55:0] decode_tlv,
    output reg         decode_done,
    output reg         decode_error,
    output reg [31:0]  decode_value
);
    localparam [7:0] ASN1_INTEGER   = 8'h02;
    localparam [7:0] ASN1_COUNTER32 = 8'h41;
    localparam [7:0] ASN1_TIMETICKS = 8'h43;

    reg [3:0] content_len;
    reg [39:0] content;
    reg known_type;
    reg unsigned_type;
    reg [31:0] value;

    always @(*) begin
        encode_done = encode_valid;
        encode_error = 1'b0;
        encode_len = 4'd0;
        encode_tlv = 56'd0;
        content_len = 4'd0;
        content = 40'd0;
        known_type = (encode_type == ASN1_INTEGER) ||
                     (encode_type == ASN1_COUNTER32) ||
                     (encode_type == ASN1_TIMETICKS);
        unsigned_type = (encode_type == ASN1_COUNTER32) ||
                        (encode_type == ASN1_TIMETICKS);
        value = encode_value;

        if (encode_valid) begin
            if (!known_type) begin
                encode_error = 1'b1;
            end else if (unsigned_type) begin
                if (value <= 32'h0000_007F) begin
                    content_len = 1; content[7:0] = value[7:0];
                end else if (value <= 32'h0000_7FFF) begin
                    content_len = 2; content[15:0] = value[15:0];
                end else if (value <= 32'h007F_FFFF) begin
                    content_len = 3; content[23:0] = value[23:0];
                end else if (value <= 32'h7FFF_FFFF) begin
                    content_len = 4; content[31:0] = value;
                end else begin
                    content_len = 5; content[39:32] = 8'h00; content[31:0] = value;
                end
            end else begin
                if (value[31] && (value >= 32'hFFFF_FF80)) begin
                    content_len = 1; content[7:0] = value[7:0];
                end else if (value[31] && (value >= 32'hFFFF_8000)) begin
                    content_len = 2; content[15:0] = value[15:0];
                end else if (value[31] && (value >= 32'hFF80_0000)) begin
                    content_len = 3; content[23:0] = value[23:0];
                end else if (!value[31] && (value <= 32'h0000_007F)) begin
                    content_len = 1; content[7:0] = value[7:0];
                end else if (!value[31] && (value <= 32'h0000_7FFF)) begin
                    content_len = 2; content[15:0] = value[15:0];
                end else if (!value[31] && (value <= 32'h007F_FFFF)) begin
                    content_len = 3; content[23:0] = value[23:0];
                end else begin
                    content_len = 4; content[31:0] = value;
                end
            end

            if (!encode_error) begin
                encode_len = content_len + 2;
                encode_tlv[55:48] = encode_type;
                encode_tlv[47:40] = content_len;
                encode_tlv[39:0] = content;
            end
        end
    end

    always @(*) begin
        decode_done = decode_valid;
        decode_error = 1'b0;
        decode_value = 32'd0;

        if (decode_valid) begin
            if ((decode_type != decode_tlv[55:48]) ||
                (decode_len != decode_tlv[47:40] + 2) ||
                (decode_len < 3) || (decode_len > 7)) begin
                decode_error = 1'b1;
            end else if (decode_type == ASN1_INTEGER) begin
                case (decode_len)
                    3: decode_value = {{24{decode_tlv[7]}}, decode_tlv[7:0]};
                    4: decode_value = {{16{decode_tlv[15]}}, decode_tlv[15:8], decode_tlv[7:0]};
                    5: decode_value = {{8{decode_tlv[23]}}, decode_tlv[23:16], decode_tlv[15:8], decode_tlv[7:0]};
                    6: decode_value = {decode_tlv[31:24], decode_tlv[23:16], decode_tlv[15:8], decode_tlv[7:0]};
                    default: decode_error = 1'b1;
                endcase
            end else if ((decode_type == ASN1_COUNTER32) ||
                         (decode_type == ASN1_TIMETICKS)) begin
                case (decode_len)
                    3: decode_value = {24'd0, decode_tlv[7:0]};
                    4: decode_value = {16'd0, decode_tlv[15:8], decode_tlv[7:0]};
                    5: decode_value = {8'd0, decode_tlv[23:16], decode_tlv[15:8], decode_tlv[7:0]};
                    6: decode_value = {decode_tlv[31:24], decode_tlv[23:16], decode_tlv[15:8], decode_tlv[7:0]};
                    7: decode_value = {decode_tlv[31:24], decode_tlv[23:16], decode_tlv[15:8], decode_tlv[7:0]};
                    default: decode_error = 1'b1;
                endcase
            end else begin
                decode_error = 1'b1;
            end
        end
    end
endmodule
