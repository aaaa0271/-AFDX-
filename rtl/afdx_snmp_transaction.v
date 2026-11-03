`timescale 1ns / 1ps

module afdx_snmp_transaction #(
    parameter integer MAX_VB_BYTES = 64
)(
    input wire clk,
    input wire rst,
    input wire req,
    input wire req_op,
    input wire [7:0] req_object_id,

    output reg m6b_req_valid,
    output reg m6b_req_op,
    output reg [7:0] m6b_req_object_id,
    input wire m6b_rsp_valid,
    input wire m6b_rsp_error,
    input wire [1:0] m6b_rsp_error_code,
    input wire [7:0] m6b_rsp_object_id,
    input wire [7:0] m6b_rsp_asn1_type,
    input wire [31:0] m6b_rsp_value,

    output reg m6c_req,
    output reg [7:0] m6c_object_id,
    output reg [7:0] m6c_asn1_type,
    output reg [31:0] m6c_value,
    output reg [1:0] m6c_response_status,
    input wire m6c_done,
    input wire m6c_error,
    input wire [6:0] m6c_varbind_length,
    input wire [MAX_VB_BYTES*8-1:0] m6c_varbind_bytes,

    output reg rsp_valid,
    output reg rsp_error,
    output reg [2:0] rsp_error_code,
    output reg [7:0] rsp_object_id,
    output reg [6:0] rsp_length,
    output reg [MAX_VB_BYTES*8-1:0] rsp_bytes
);
    localparam [2:0] ERR_NONE = 3'd0;
    localparam [2:0] ERR_NO_SUCH_OBJECT = 3'd1;
    localparam [2:0] ERR_END_OF_MIB_VIEW = 3'd2;
    localparam [2:0] ERR_TELEMETRY_UNAVAILABLE = 3'd3;
    localparam [2:0] ERR_CODEC = 3'd4;
    localparam [2:0] S_IDLE = 3'd0;
    localparam [2:0] S_M6B_REQ = 3'd1;
    localparam [2:0] S_M6B_WAIT = 3'd2;
    localparam [2:0] S_M6C_REQ = 3'd3;
    localparam [2:0] S_M6C_WAIT = 3'd4;
    localparam [2:0] S_COMPLETE = 3'd5;

    reg [2:0] state;
    reg req_op_q;
    reg [7:0] req_object_id_q;
    reg [7:0] response_object_id_q;
    reg [7:0] response_type_q;
    reg [31:0] response_value_q;

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            req_op_q <= 1'b0;
            req_object_id_q <= 8'd0;
            response_object_id_q <= 8'd0;
            response_type_q <= 8'd0;
            response_value_q <= 32'd0;
            m6b_req_valid <= 1'b0;
            m6b_req_op <= 1'b0;
            m6b_req_object_id <= 8'd0;
            m6c_req <= 1'b0;
            m6c_object_id <= 8'd0;
            m6c_asn1_type <= 8'd0;
            m6c_value <= 32'd0;
            m6c_response_status <= 2'd0;
            rsp_valid <= 1'b0;
            rsp_error <= 1'b0;
            rsp_error_code <= ERR_NONE;
            rsp_object_id <= 8'd0;
            rsp_length <= 7'd0;
            rsp_bytes <= {MAX_VB_BYTES*8{1'b0}};
        end else begin
            m6b_req_valid <= 1'b0;
            m6c_req <= 1'b0;
            rsp_valid <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (req) begin
                        req_op_q <= req_op;
                        req_object_id_q <= req_object_id;
                        state <= S_M6B_REQ;
                    end
                end
                S_M6B_REQ: begin
                    m6b_req_valid <= 1'b1;
                    m6b_req_op <= req_op_q;
                    m6b_req_object_id <= req_object_id_q;
                    state <= S_M6B_WAIT;
                end
                S_M6B_WAIT: begin
                    if (m6b_rsp_valid) begin
                        response_object_id_q <= m6b_rsp_object_id;
                        if (m6b_rsp_error) begin
                            rsp_error <= 1'b1;
                            rsp_error_code <= {1'b0, m6b_rsp_error_code};
                            rsp_object_id <= m6b_rsp_object_id;
                            rsp_length <= 7'd0;
                            rsp_bytes <= {MAX_VB_BYTES*8{1'b0}};
                            state <= S_COMPLETE;
                        end else begin
                            response_type_q <= m6b_rsp_asn1_type;
                            response_value_q <= m6b_rsp_value;
                            state <= S_M6C_REQ;
                        end
                    end
                end
                S_M6C_REQ: begin
                    m6c_req <= 1'b1;
                    m6c_object_id <= response_object_id_q;
                    m6c_asn1_type <= response_type_q;
                    m6c_value <= response_value_q;
                    m6c_response_status <= 2'd0;
                    state <= S_M6C_WAIT;
                end
                S_M6C_WAIT: begin
                    if (m6c_done) begin
                        rsp_object_id <= response_object_id_q;
                        if (m6c_error) begin
                            rsp_error <= 1'b1;
                            rsp_error_code <= ERR_CODEC;
                            rsp_length <= 7'd0;
                            rsp_bytes <= {MAX_VB_BYTES*8{1'b0}};
                        end else begin
                            rsp_error <= 1'b0;
                            rsp_error_code <= ERR_NONE;
                            rsp_length <= m6c_varbind_length;
                            rsp_bytes <= m6c_varbind_bytes;
                        end
                        state <= S_COMPLETE;
                    end
                end
                S_COMPLETE: begin
                    rsp_valid <= 1'b1;
                    state <= S_IDLE;
                end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
