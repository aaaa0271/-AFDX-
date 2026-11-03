`timescale 1ns / 1ps

module afdx_mib_register_bank (
    input wire clk,
    input wire rst_n,
    input wire req_valid,
    input wire req_op,
    input wire [7:0] req_object_id,
    output reg rsp_valid,
    output reg rsp_error,
    output reg [1:0] rsp_error_code,
    output reg [7:0] rsp_object_id,
    output reg [7:0] rsp_asn1_type,
    output reg [31:0] rsp_value,
    output reg [7:0] m6a_rd_addr,
    input wire [31:0] m6a_rd_data,
    input wire m6a_rd_valid
);
    localparam [1:0] ERR_NONE = 2'd0;
    localparam [1:0] ERR_NO_SUCH_OBJECT = 2'd1;
    localparam [1:0] ERR_END_OF_MIB_VIEW = 2'd2;
    localparam [1:0] ERR_TELEMETRY_UNAVAILABLE = 2'd3;
    localparam [7:0] ASN1_INTEGER = 8'h02;
    localparam [7:0] ASN1_COUNTER32 = 8'h41;
    localparam [7:0] ASN1_TIMETICKS = 8'h43;

    reg pending;
    reg [7:0] pending_object_id;
    reg [7:0] pending_asn1_type;
    reg [7:0] pending_m6a_addr;
    reg decode_valid;
    reg [7:0] decode_object_id;
    reg [7:0] decode_addr;
    reg [7:0] decode_type;
    reg request_error;
    reg [1:0] request_error_code;

    always @(*) begin
        decode_valid = 1'b1;
        decode_object_id = req_object_id;
        decode_addr = 8'h00;
        decode_type = ASN1_COUNTER32;
        request_error = 1'b0;
        request_error_code = ERR_NONE;

        if (req_op) begin
            if (req_object_id < 8'h01)
                decode_object_id = 8'h01;
            else if (req_object_id < 8'h19)
                decode_object_id = req_object_id + 8'd1;
            else begin
                decode_valid = 1'b0;
                request_error = 1'b1;
                request_error_code = ERR_END_OF_MIB_VIEW;
            end
        end else if ((req_object_id < 8'h01) || (req_object_id > 8'h19)) begin
            decode_valid = 1'b0;
            request_error = 1'b1;
            request_error_code = ERR_NO_SUCH_OBJECT;
        end

        if (decode_valid) begin
            case (decode_object_id)
                8'h01: begin decode_addr = 8'h00; decode_type = ASN1_INTEGER; end
                8'h02: begin decode_addr = 8'h01; decode_type = ASN1_COUNTER32; end
                8'h03: begin decode_addr = 8'h02; decode_type = ASN1_TIMETICKS; end
                8'h04: begin decode_addr = 8'h03; decode_type = ASN1_INTEGER; end
                8'h05: begin decode_addr = 8'h04; decode_type = ASN1_INTEGER; end
                8'h06: begin decode_addr = 8'h10; decode_type = ASN1_COUNTER32; end
                8'h07: begin decode_addr = 8'h11; decode_type = ASN1_COUNTER32; end
                8'h08: begin decode_addr = 8'h12; decode_type = ASN1_COUNTER32; end
                8'h09: begin decode_addr = 8'h13; decode_type = ASN1_COUNTER32; end
                8'h0A: begin decode_addr = 8'h14; decode_type = ASN1_COUNTER32; end
                8'h0B: begin decode_addr = 8'h15; decode_type = ASN1_COUNTER32; end
                8'h0C: begin decode_addr = 8'h16; decode_type = ASN1_COUNTER32; end
                8'h0D: begin decode_addr = 8'h17; decode_type = ASN1_COUNTER32; end
                8'h0E: begin decode_addr = 8'h20; decode_type = ASN1_COUNTER32; end
                8'h0F: begin decode_addr = 8'h21; decode_type = ASN1_COUNTER32; end
                8'h10: begin decode_addr = 8'h22; decode_type = ASN1_COUNTER32; end
                8'h11: begin decode_addr = 8'h23; decode_type = ASN1_COUNTER32; end
                8'h12: begin decode_addr = 8'h24; decode_type = ASN1_COUNTER32; end
                8'h13: begin decode_addr = 8'h25; decode_type = ASN1_COUNTER32; end
                8'h14: begin decode_addr = 8'h26; decode_type = ASN1_COUNTER32; end
                8'h15: begin decode_addr = 8'h27; decode_type = ASN1_COUNTER32; end
                8'h16: begin decode_addr = 8'h28; decode_type = ASN1_COUNTER32; end
                8'h17: begin decode_addr = 8'h29; decode_type = ASN1_COUNTER32; end
                8'h18: begin decode_addr = 8'h2A; decode_type = ASN1_COUNTER32; end
                8'h19: begin decode_addr = 8'h2B; decode_type = ASN1_COUNTER32; end
                default: begin
                    decode_valid = 1'b0;
                    request_error = 1'b1;
                    request_error_code = ERR_NO_SUCH_OBJECT;
                end
            endcase
        end
    end

    always @(*) begin
        if (pending)
            m6a_rd_addr = pending_m6a_addr;
        else if (req_valid && decode_valid)
            m6a_rd_addr = decode_addr;
        else
            m6a_rd_addr = 8'h00;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pending <= 1'b0;
            pending_object_id <= 8'd0;
            pending_asn1_type <= 8'd0;
            pending_m6a_addr <= 8'd0;
            rsp_valid <= 1'b0;
            rsp_error <= 1'b0;
            rsp_error_code <= ERR_NONE;
            rsp_object_id <= 8'd0;
            rsp_asn1_type <= 8'd0;
            rsp_value <= 32'd0;
        end else begin
            rsp_valid <= 1'b0;
            if (pending) begin
                rsp_valid <= 1'b1;
                rsp_object_id <= pending_object_id;
                rsp_asn1_type <= pending_asn1_type;
                if (m6a_rd_valid) begin
                    rsp_error <= 1'b0;
                    rsp_error_code <= ERR_NONE;
                    rsp_value <= m6a_rd_data;
                end else begin
                    rsp_error <= 1'b1;
                    rsp_error_code <= ERR_TELEMETRY_UNAVAILABLE;
                    rsp_value <= 32'd0;
                end
                pending <= 1'b0;
            end
            if (req_valid) begin
                if (request_error) begin
                    rsp_valid <= 1'b1;
                    rsp_error <= 1'b1;
                    rsp_error_code <= request_error_code;
                    rsp_object_id <= req_object_id;
                    rsp_asn1_type <= 8'd0;
                    rsp_value <= 32'd0;
                    pending <= 1'b0;
                end else begin
                    pending <= 1'b1;
                    pending_object_id <= decode_object_id;
                    pending_asn1_type <= decode_type;
                    pending_m6a_addr <= decode_addr;
                end
            end
        end
    end
endmodule
