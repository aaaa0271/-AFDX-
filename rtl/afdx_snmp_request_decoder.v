`timescale 1ns / 1ps

module afdx_snmp_request_decoder #(
    parameter integer MAX_MSG_BYTES = 128,
    parameter integer COMMUNITY_BYTES = 6
)(
    input wire clk,
    input wire rst,
    input wire req,
    input wire [7:0] msg_length,
    input wire [MAX_MSG_BYTES*8-1:0] msg_bytes,
    output reg done,
    output reg error,
    output reg [3:0] error_code,
    output reg request_op,
    output reg [31:0] request_id,
    output reg [7:0] object_id,
    output reg [7:0] community_length,
    output reg [COMMUNITY_BYTES*8-1:0] community_bytes
);
    localparam [3:0] ERR_NONE=0, ERR_MALFORMED=1, ERR_COMMUNITY=2,
                     ERR_UNSUPPORTED_PDU=3, ERR_SET_REJECT=4,
                     ERR_VERSION=5, ERR_FIELD=6, ERR_OID=7;
    integer i;
    reg parse_error;
    reg [3:0] parse_code;
    reg [31:0] parsed_request_id;
    reg [7:0] parsed_object_id;
    reg parsed_op;

    function [7:0] b;
        input integer index;
        begin b = msg_bytes[index*8 +: 8]; end
    endfunction

    always @(msg_length or msg_bytes) begin
        parse_error = 1'b0;
        parse_code = ERR_NONE;
        parsed_request_id = 32'd0;
        parsed_object_id = 8'd0;
        parsed_op = 1'b0;

        if (msg_length != 8'd44 || b(0) != 8'h30 || b(1) != 8'h2A)
            begin parse_error=1; parse_code=ERR_MALFORMED; end
        else if ((b(2)!=8'h02) || (b(3)!=8'h01) || (b(4)!=8'h00))
            begin parse_error=1; parse_code=ERR_VERSION; end
        else if ((b(5)!=8'h04) || (b(6)!=COMMUNITY_BYTES) ||
                 (b(7)!="p") || (b(8)!="u") || (b(9)!="b") ||
                 (b(10)!="l") || (b(11)!="i") || (b(12)!="c"))
            begin parse_error=1; parse_code=ERR_COMMUNITY; end
        else if ((b(13)!=8'hA0) && (b(13)!=8'hA1))
            begin parse_error=1; parse_code=(b(13)==8'hA3) ? ERR_SET_REJECT : ERR_UNSUPPORTED_PDU; end
        else if (b(14)!=8'h1D)
            begin parse_error=1; parse_code=ERR_MALFORMED; end
        else if ((b(15)!=8'h02) || (b(16)!=8'h03))
            begin parse_error=1; parse_code=ERR_FIELD; end
        else begin
            parsed_request_id = {8'd0,b(17),b(18),b(19)};
            if ((b(20)!=8'h02) || (b(21)!=8'h01) || (b(22)!=8'h00) ||
                (b(23)!=8'h02) || (b(24)!=8'h01) || (b(25)!=8'h00) ||
                (b(26)!=8'h30) || (b(27)!=8'h10) ||
                (b(28)!=8'h30) || (b(29)!=8'h0E) ||
                (b(30)!=8'h06) || (b(31)!=8'h0A))
                begin parse_error=1; parse_code=ERR_FIELD; end
            else if ((b(32)!=8'h2B) || (b(33)!=8'h06) || (b(34)!=8'h01) ||
                     (b(35)!=8'h04) || (b(36)!=8'h01) || (b(37)!=8'h81) ||
                     (b(38)!=8'hFD) || (b(39)!=8'h59) || (b(40)!=8'h01) ||
                     (b(41)<8'd1) || (b(41)>8'd25))
                begin parse_error=1; parse_code=ERR_OID; end
            else if ((b(42)!=8'h05) || (b(43)!=8'h00))
                begin parse_error=1; parse_code=ERR_FIELD; end
            else begin
                parsed_object_id = b(41);
                parsed_op = (b(13)==8'hA1);
            end
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            done <= 1'b0;
            error <= 1'b0;
            error_code <= ERR_NONE;
            request_op <= 1'b0;
            request_id <= 32'd0;
            object_id <= 8'd0;
            community_length <= 8'd0;
            community_bytes <= {COMMUNITY_BYTES*8{1'b0}};
        end else begin
            done <= 1'b0;
            if (req) begin
                done <= 1'b1;
                error <= parse_error;
                error_code <= parse_code;
                request_op <= parsed_op;
                request_id <= parsed_request_id;
                object_id <= parsed_object_id;
                community_length <= COMMUNITY_BYTES;
                for (i=0; i<COMMUNITY_BYTES; i=i+1)
                    community_bytes[i*8 +: 8] <= b(7+i);
            end
        end
    end
endmodule
