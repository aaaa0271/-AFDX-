`timescale 1ns / 1ps
// One owned transaction plus a drain-only ingress context. No BER policy here.
module afdx_m6e_02a_boundary #(
    parameter integer MAX_PAYLOAD_BYTES = 96,
    parameter integer ADDR_WIDTH = 7
)(
    input wire clk, rst,
    input wire [31:0] src_ip,
    input wire [15:0] udp_src_port, udp_dst_port,
    input wire [10:0] payload_length,
    input wire meta_valid,
    input wire [7:0] payload_data,
    input wire payload_valid,
    output wire payload_ready,
    input wire payload_sof, payload_eof,
    input wire rx_result_valid, rx_accept, rx_reject,
    output reg meta_valid_out,
    output reg [31:0] src_ip_out,
    output reg [15:0] udp_src_port_out, udp_dst_port_out,
    output reg [10:0] payload_length_out,
    output wire [7:0] payload_data_out,
    output wire payload_valid_out,
    input wire payload_ready_out,
    output wire payload_sof_out, payload_eof_out,
    output reg frame_done, frame_valid,
    output wire busy
);
localparam IDLE=0, CAPTURE=1, DECIDE=2, META=3, OUTPUT=4, DONE=5;
reg [2:0] state;
reg [7:0] payload_mem [0:MAX_PAYLOAD_BYTES-1];
reg [ADDR_WIDTH-1:0] read_ptr;
reg [10:0] captured_count;
reg result_seen, result_accept, eof_seen, sof_seen, bad_stream;
reg dropping, drop_result, drop_eof, drop_zero;
wire input_fire = payload_valid && payload_ready;
wire accepted = rx_accept && !rx_reject;
assign busy = state != IDLE || dropping;
assign payload_ready = state == CAPTURE || dropping;
assign payload_valid_out = state == OUTPUT;
assign payload_data_out = payload_mem[read_ptr];
assign payload_sof_out = payload_valid_out && read_ptr == 0;
assign payload_eof_out = payload_valid_out && read_ptr == captured_count-1'b1;
always @(posedge clk) begin
    if (rst) begin
        state <= IDLE;
        read_ptr <= 0; captured_count <= 0;
        result_seen <= 0; result_accept <= 0;
        eof_seen <= 0; sof_seen <= 0; bad_stream <= 0;
        dropping <= 0; drop_result <= 0; drop_eof <= 0; drop_zero <= 0;
        meta_valid_out <= 0; frame_done <= 0; frame_valid <= 0;
        src_ip_out <= 0; udp_src_port_out <= 0;
        udp_dst_port_out <= 0; payload_length_out <= 0;
    end else begin
        meta_valid_out <= 0;
        frame_done <= 0;
        // Metadata arriving during replay owns a separate drain context. Its
        // result must never change the decision or requester of the replay.
        if (meta_valid && state != IDLE && state != CAPTURE && !dropping) begin
            dropping <= !(rx_result_valid && (!accepted || payload_length == 0));
            drop_result <= rx_result_valid;
            drop_eof <= 0;
            drop_zero <= payload_length == 0;
        end
        if (dropping) begin
            if (rx_result_valid) drop_result <= 1;
            if (input_fire && payload_eof) drop_eof <= 1;
            if ((rx_result_valid && !accepted) ||
                ((drop_result || rx_result_valid) &&
                 (drop_zero || drop_eof || (input_fire && payload_eof))))
                dropping <= 0;
        end
        case (state)
            IDLE: if (meta_valid && !dropping) begin
                src_ip_out <= src_ip;
                udp_src_port_out <= udp_src_port;
                udp_dst_port_out <= udp_dst_port;
                payload_length_out <= payload_length;
                captured_count <= 0; read_ptr <= 0;
                eof_seen <= 0; sof_seen <= 0;
                result_seen <= rx_result_valid;
                result_accept <= accepted;
                bad_stream <= udp_dst_port != 161 || payload_length == 0 ||
                              payload_length > MAX_PAYLOAD_BYTES;
                state <= CAPTURE;
            end
            CAPTURE: begin
                if (rx_result_valid) begin
                    result_seen <= 1;
                    result_accept <= accepted;
                end
                if (input_fire) begin
                    if (payload_sof && captured_count == 0 && !sof_seen)
                        sof_seen <= 1;
                    else if (payload_sof) bad_stream <= 1;
                    if (eof_seen) bad_stream <= 1;
                    if (captured_count < MAX_PAYLOAD_BYTES)
                        payload_mem[captured_count] <= payload_data;
                    else bad_stream <= 1;
                    if (captured_count != 11'h7ff)
                        captured_count <= captured_count + 1'b1;
                    else bad_stream <= 1;
                    if (payload_eof) eof_seen <= 1;
                end
                // Rejected frontend frames never replay. Zero length has no
                // EOF either. Neither condition may wait for a payload byte.
                if ((rx_result_valid && !accepted) ||
                    (result_seen && !result_accept)) state <= IDLE;
                else if ((result_seen || rx_result_valid) &&
                         (payload_length_out == 0 || eof_seen ||
                          (input_fire && payload_eof))) state <= DECIDE;
            end
            DECIDE: begin
                if (!bad_stream && sof_seen && eof_seen &&
                    result_accept && captured_count == payload_length_out) begin
                    meta_valid_out <= 1;
                    frame_valid <= 1;
                    state <= META;
                end else state <= IDLE;
            end
            // 01A samples metadata here before any payload can be visible.
            META: state <= OUTPUT;
            OUTPUT: if (payload_ready_out) begin
                if (payload_eof_out) begin
                    frame_done <= 1;
                    state <= DONE;
                end else read_ptr <= read_ptr + 1'b1;
            end
            // Keep frame_valid asserted on the edge sampling frame_done.
            DONE: begin frame_valid <= 0; state <= IDLE; end
            default: state <= IDLE;
        endcase
    end
end
endmodule
