`timescale 1ns / 1ps

module afdx_m6c_integration #(
    parameter integer MAX_OID_ARCS = 16,
    parameter integer MAX_OID_BYTES = 32,
    parameter integer MAX_VB_BYTES = 64
)(
    input wire clk,
    input wire rst,
    input wire req,
    input wire [7:0] object_id,
    input wire [7:0] asn1_type,
    input wire [31:0] value,
    input wire [1:0] response_status,
    output reg done,
    output reg error,
    output reg [6:0] varbind_length,
    output reg [MAX_VB_BYTES*8-1:0] varbind_bytes
);
    localparam [7:0] ASN1_INTEGER = 8'h02;
    localparam [7:0] ASN1_COUNTER32 = 8'h41;
    localparam [7:0] ASN1_TIMETICKS = 8'h43;
    localparam [7:0] ASN1_OID = 8'h06;
    localparam [7:0] ASN1_SEQUENCE = 8'h30;
    localparam [2:0] S_IDLE=0, S_BUILD=1, S_OID_START=2, S_OID_WAIT=3,
                     S_VALUE_WAIT=4, S_ASSEMBLE=5, S_DONE=6;

    reg [2:0] state;
    reg [7:0] type_q;
    reg [31:0] value_q;
    reg [1:0] status_q;
    reg [4:0] oid_arc_count;
    reg [MAX_OID_ARCS*32-1:0] oid_arcs;
    reg oid_req;
    wire oid_done, oid_error;
    wire [5:0] oid_length;
    wire [MAX_OID_BYTES*8-1:0] oid_bytes;
    reg prim_req;
    wire prim_done, prim_error;
    wire [3:0] prim_length;
    wire [55:0] prim_tlv;
    reg [3:0] prim_length_q;
    reg [55:0] prim_tlv_q;
    integer i;
    integer inner_len;
    integer total_len;

    afdx_ber_oid_codec #(.MAX_ARCS(MAX_OID_ARCS), .MAX_BYTES(MAX_OID_BYTES)) u_oid (
        .clk(clk), .rst(rst), .enc_req(oid_req), .enc_arc_count(oid_arc_count),
        .enc_arcs(oid_arcs), .enc_done(oid_done), .enc_error(oid_error),
        .enc_length(oid_length), .enc_bytes(oid_bytes), .dec_req(1'b0),
        .dec_length(6'd0), .dec_bytes({MAX_OID_BYTES*8{1'b0}}),
        .dec_done(), .dec_error(), .dec_arc_count(), .dec_arcs()
    );

    afdx_ber_primitive_codec u_primitive (
        .encode_valid(prim_req), .encode_type(type_q), .encode_value(value_q),
        .encode_done(prim_done), .encode_error(prim_error), .encode_len(prim_length),
        .encode_tlv(prim_tlv), .decode_valid(1'b0), .decode_type(8'd0),
        .decode_len(4'd0), .decode_tlv(56'd0), .decode_done(), .decode_error(),
        .decode_value()
    );

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE; done <= 0; error <= 0; varbind_length <= 0;
            varbind_bytes <= 0; type_q <= 0; value_q <= 0; status_q <= 0;
            prim_length_q <= 0; prim_tlv_q <= 0;
            oid_arc_count <= 0; oid_arcs <= 0; oid_req <= 0; prim_req <= 0;
        end else begin
            done <= 0; oid_req <= 0; prim_req <= 0;
            case (state)
                S_IDLE: if (req) begin
                    error <= 0; varbind_length <= 0; varbind_bytes <= 0;
                    type_q <= asn1_type; value_q <= value; status_q <= response_status;
                    if ((response_status != 0) || (object_id < 1) || (object_id > 25) ||
                        ((asn1_type != ASN1_INTEGER) && (asn1_type != ASN1_COUNTER32) &&
                         (asn1_type != ASN1_TIMETICKS))) begin
                        error <= 1; state <= S_DONE;
                    end else begin
                        oid_arcs <= 0; oid_arcs[0*32 +: 32] <= 32'd1; oid_arcs[1*32 +: 32] <= 32'd3;
                        oid_arcs[2*32 +: 32] <= 32'd6; oid_arcs[3*32 +: 32] <= 32'd1;
                        oid_arcs[4*32 +: 32] <= 32'd4; oid_arcs[5*32 +: 32] <= 32'd1;
                        oid_arcs[6*32 +: 32] <= 32'd32473; oid_arcs[7*32 +: 32] <= 32'd1;
                        oid_arcs[8*32 +: 32] <= 32'd1; oid_arcs[9*32 +: 32] <= {24'd0, object_id};
                        oid_arc_count <= 10; state <= S_BUILD;
                    end
                end
                S_BUILD: state <= S_OID_START;
                S_OID_START: begin oid_req <= 1; state <= S_OID_WAIT; end
                S_OID_WAIT: if (oid_done) begin
                    if (oid_error) begin error <= 1; state <= S_DONE; end
                    else begin prim_req <= 1; state <= S_VALUE_WAIT; end
                end
                S_VALUE_WAIT: if (prim_done) begin
                    if (prim_error) begin error <= 1; state <= S_DONE; end
                    else begin
                        prim_length_q <= prim_length;
                        prim_tlv_q <= prim_tlv;
                        state <= S_ASSEMBLE;
                    end
                end
                S_ASSEMBLE: begin
                    inner_len = 2 + oid_length + prim_length_q;
                    total_len = inner_len + 2;
                    if ((inner_len >= 128) || (total_len > MAX_VB_BYTES)) begin
                        error <= 1; state <= S_DONE;
                    end else begin
                        varbind_bytes <= 0;
                        varbind_bytes[0*8 +: 8] <= ASN1_SEQUENCE;
                        varbind_bytes[1*8 +: 8] <= inner_len;
                        varbind_bytes[2*8 +: 8] <= ASN1_OID;
                        varbind_bytes[3*8 +: 8] <= oid_length;
                        for (i=0; i<MAX_OID_BYTES; i=i+1)
                            if (i < oid_length) varbind_bytes[(4+i)*8 +: 8] <= oid_bytes[i*8 +: 8];
                        varbind_bytes[(4+oid_length)*8 +: 8] <= prim_tlv_q[55:48];
                        varbind_bytes[(5+oid_length)*8 +: 8] <= prim_tlv_q[47:40];
                        case (prim_length_q)
                            4'd3: varbind_bytes[(6+oid_length)*8 +: 8] <= prim_tlv_q[7:0];
                            4'd4: begin varbind_bytes[(6+oid_length)*8 +: 8] <= prim_tlv_q[15:8]; varbind_bytes[(7+oid_length)*8 +: 8] <= prim_tlv_q[7:0]; end
                            4'd5: begin varbind_bytes[(6+oid_length)*8 +: 8] <= prim_tlv_q[23:16]; varbind_bytes[(7+oid_length)*8 +: 8] <= prim_tlv_q[15:8]; varbind_bytes[(8+oid_length)*8 +: 8] <= prim_tlv_q[7:0]; end
                            4'd6: begin varbind_bytes[(6+oid_length)*8 +: 8] <= prim_tlv_q[31:24]; varbind_bytes[(7+oid_length)*8 +: 8] <= prim_tlv_q[23:16]; varbind_bytes[(8+oid_length)*8 +: 8] <= prim_tlv_q[15:8]; varbind_bytes[(9+oid_length)*8 +: 8] <= prim_tlv_q[7:0]; end
                            default: begin varbind_bytes[(6+oid_length)*8 +: 8] <= prim_tlv_q[39:32]; varbind_bytes[(7+oid_length)*8 +: 8] <= prim_tlv_q[31:24]; varbind_bytes[(8+oid_length)*8 +: 8] <= prim_tlv_q[23:16]; varbind_bytes[(9+oid_length)*8 +: 8] <= prim_tlv_q[15:8]; varbind_bytes[(10+oid_length)*8 +: 8] <= prim_tlv_q[7:0]; end
                        endcase
                        varbind_length <= total_len; state <= S_DONE;
                    end
                end
                S_DONE: begin done <= 1; state <= S_IDLE; end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
