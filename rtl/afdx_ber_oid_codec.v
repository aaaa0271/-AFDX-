`timescale 1ns / 1ps

module afdx_ber_oid_codec #(
    parameter integer MAX_ARCS  = 16,
    parameter integer MAX_BYTES = 32
)(
    input wire clk,
    input wire rst,
    input wire enc_req,
    input wire [4:0] enc_arc_count,
    input wire [MAX_ARCS*32-1:0] enc_arcs,
    output reg enc_done,
    output reg enc_error,
    output reg [5:0] enc_length,
    output reg [MAX_BYTES*8-1:0] enc_bytes,
    input wire dec_req,
    input wire [5:0] dec_length,
    input wire [MAX_BYTES*8-1:0] dec_bytes,
    output reg dec_done,
    output reg dec_error,
    output reg [4:0] dec_arc_count,
    output reg [MAX_ARCS*32-1:0] dec_arcs
);
    localparam S_IDLE = 3'd0;
    localparam S_ENC_EMIT = 3'd1;
    localparam S_DEC_FIRST = 3'd2;
    localparam S_DEC_ARC = 3'd3;
    localparam S_DONE = 3'd4;

    reg [2:0] state;
    reg [4:0] enc_index;
    reg [5:0] byte_index;
    reg [31:0] work_value;
    reg [6:0] group0, group1, group2, group3, group4;
    reg [2:0] group_count;
    reg [2:0] emit_index;
    reg [31:0] dec_value;
    reg [7:0] current_byte;
    reg [31:0] current_arc;
    reg [32:0] combined_value;
    reg op_encode;
    integer i;

    task prepare_base128;
        input [31:0] value;
        reg [31:0] v;
        begin
            v = value;
            group0 = v[6:0];
            group1 = 0; group2 = 0; group3 = 0; group4 = 0;
            group_count = 1;
            v = v >> 7;
            if (v != 0) begin group1 = v[6:0]; group_count = 2; v = v >> 7; end
            if (v != 0) begin group2 = v[6:0]; group_count = 3; v = v >> 7; end
            if (v != 0) begin group3 = v[6:0]; group_count = 4; v = v >> 7; end
            if (v != 0) begin group4 = v[6:0]; group_count = 5; end
        end
    endtask

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            enc_done <= 0; enc_error <= 0; enc_length <= 0; enc_bytes <= 0;
            dec_done <= 0; dec_error <= 0; dec_arc_count <= 0; dec_arcs <= 0;
            op_encode <= 0;
            enc_index <= 0; byte_index <= 0; work_value <= 0; group_count <= 0;
            emit_index <= 0; dec_value <= 0; current_arc <= 0;
        end else begin
            enc_done <= 0;
            dec_done <= 0;
            case (state)
                S_IDLE: begin
                    if (enc_req) begin
                        op_encode <= 1;
                        enc_error <= 0; enc_length <= 0; enc_bytes <= 0;
                        enc_index <= 2; byte_index <= 0;
                        if ((enc_arc_count < 2) || (enc_arc_count > MAX_ARCS)) begin
                            enc_error <= 1; state <= S_DONE;
                        end else if ((enc_arcs[31:0] > 2) ||
                                     ((enc_arcs[31:0] < 2) && (enc_arcs[63:32] > 39))) begin
                            enc_error <= 1; state <= S_DONE;
                        end else begin
                            combined_value = enc_arcs[31:0] * 40 + enc_arcs[63:32];
                            if (combined_value[32]) begin
                                enc_error <= 1; state <= S_DONE;
                            end else begin
                                prepare_base128(combined_value[31:0]);
                                emit_index <= group_count - 1;
                                state <= S_ENC_EMIT;
                            end
                        end
                    end else if (dec_req) begin
                        op_encode <= 0;
                        dec_error <= 0; dec_arc_count <= 0; dec_arcs <= 0;
                        byte_index <= 0; dec_value <= 0;
                        if ((dec_length == 0) || (dec_length > MAX_BYTES)) begin
                            dec_error <= 1; state <= S_DONE;
                        end else state <= S_DEC_FIRST;
                    end
                end

                S_ENC_EMIT: begin
                    if (byte_index >= MAX_BYTES) begin
                        enc_error <= 1; state <= S_DONE;
                    end else begin
                        case (emit_index)
                            3'd4: enc_bytes[byte_index*8 +: 8] <= {1'b1, group4};
                            3'd3: enc_bytes[byte_index*8 +: 8] <= {1'b1, group3};
                            3'd2: enc_bytes[byte_index*8 +: 8] <= {1'b1, group2};
                            3'd1: enc_bytes[byte_index*8 +: 8] <= {1'b1, group1};
                            default: enc_bytes[byte_index*8 +: 8] <= {1'b0, group0};
                        endcase
                        byte_index <= byte_index + 1;
                        if (emit_index != 0) begin
                            emit_index <= emit_index - 1;
                        end else if (enc_index >= enc_arc_count) begin
                            enc_length <= byte_index + 1;
                            state <= S_DONE;
                        end else begin
                            work_value = enc_arcs[enc_index*32 +: 32];
                            prepare_base128(work_value);
                            emit_index <= group_count - 1;
                            enc_index <= enc_index + 1;
                        end
                    end
                end

                S_DEC_FIRST: begin
                    current_byte = dec_bytes[byte_index*8 +: 8];
                    if (dec_value > 32'h01ffffff) begin
                        dec_error <= 1; state <= S_DONE;
                    end else begin
                        current_arc = (dec_value << 7) | current_byte[6:0];
                        if (current_byte[7]) begin
                            dec_value <= current_arc;
                            byte_index <= byte_index + 1;
                            if ((byte_index + 1) >= dec_length) begin
                                dec_error <= 1; state <= S_DONE;
                            end
                        end else begin
                            if (current_arc < 40) begin
                                dec_arcs[31:0] <= 0; dec_arcs[63:32] <= current_arc;
                            end else if (current_arc < 80) begin
                                dec_arcs[31:0] <= 1; dec_arcs[63:32] <= current_arc - 40;
                            end else begin
                                dec_arcs[31:0] <= 2; dec_arcs[63:32] <= current_arc - 80;
                            end
                            dec_arc_count <= 2; dec_value <= 0; byte_index <= byte_index + 1;
                            if ((byte_index + 1) >= dec_length) state <= S_DONE;
                            else state <= S_DEC_ARC;
                        end
                    end
                end

                S_DEC_ARC: begin
                    current_byte = dec_bytes[byte_index*8 +: 8];
                    if (dec_arc_count >= MAX_ARCS || dec_value > 32'h01ffffff) begin
                        dec_error <= 1; state <= S_DONE;
                    end else begin
                        current_arc = (dec_value << 7) | current_byte[6:0];
                        if (current_byte[7]) begin
                            dec_value <= current_arc;
                            byte_index <= byte_index + 1;
                            if ((byte_index + 1) >= dec_length) begin
                                dec_error <= 1; state <= S_DONE;
                            end
                        end else begin
                            dec_arcs[dec_arc_count*32 +: 32] <= current_arc;
                            dec_arc_count <= dec_arc_count + 1;
                            dec_value <= 0; byte_index <= byte_index + 1;
                            if ((byte_index + 1) >= dec_length) state <= S_DONE;
                        end
                    end
                end

                S_DONE: begin
                    if (op_encode) begin
                        enc_done <= 1;
                    end else begin
                        dec_done <= 1;
                    end
                    state <= S_IDLE;
                end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
