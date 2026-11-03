`timescale 1ns / 1ps

module afdx_m6d_integration #(
    parameter integer MAX_MSG_BYTES = 128,
    parameter integer MAX_VB_BYTES = 64,
    parameter integer MAX_VARBINDS = 2,
    parameter integer MAX_RESPONSE_BYTES = 96,
    parameter integer CLK_HZ = 1000
)(
    input wire clk,
    input wire rst_n,
    input wire req,
    input wire [7:0] msg_length,
    input wire [MAX_MSG_BYTES*8-1:0] msg_bytes,
    output reg response_done,
    output reg response_valid,
    output reg response_error,
    output reg [7:0] response_error_code,
    output reg [7:0] response_length,
    output reg [MAX_RESPONSE_BYTES*8-1:0] response_bytes,

    input wire m5_network_a_enable,
    input wire m5_network_b_enable,
    input wire m5_degraded_mode,
    input wire m5_redundancy_ok,
    input wire m5_frame_count_match,
    input wire m5_active_byte_count_match,
    input wire m5_fault_applied_event,
    input wire [31:0] m5_rx_accepted_count,
    input wire [31:0] m5_rx_accepted_a_count,
    input wire [31:0] m5_rx_accepted_b_count,
    input wire [31:0] m5_rx_duplicate_count,
    input wire [31:0] m5_rx_cross_network_duplicate_count,
    input wire [31:0] m5_rx_same_network_repeat_count,
    input wire [31:0] m5_rx_stale_count,
    input wire [31:0] m5_rx_sequence_gap_count,
    input wire [31:0] m5_tx_a_frame_count,
    input wire [31:0] m5_tx_b_frame_count,
    input wire [31:0] m5_tx_a_active_byte_count,
    input wire [31:0] m5_tx_b_active_byte_count,
    input wire [31:0] m5_tx_byte_mismatch_count,
    input wire [31:0] m5_tx_frame_skew_cycle_count,
    input wire [31:0] m5_tx_frame_done_skew_count,
    input wire [31:0] m5_tx_er_mismatch_count,
    input wire [31:0] m5_tx_a_error_cycle_count,
    input wire [31:0] m5_tx_b_error_cycle_count,
    input wire [31:0] m5_tx_a_underrun_count,
    input wire [31:0] m5_tx_b_underrun_count
);
    localparam [3:0] S_IDLE=0, S_DEC_FIRE=1, S_WAIT_DEC=2, S_DEC_CHECK=3, S_SNAPSHOT_FIRE=4, S_SNAPSHOT_WAIT=5, S_TXN_FIRE=6, S_WAIT_TXN=7, S_BLD_FIRE=8, S_WAIT_BLD=9, S_DONE=10, S_PROFILE_FIRE=11, S_PROFILE_WAIT=12;
    localparam [7:0] ERR_END_OF_MIB_VIEW = 8'd2;
    localparam [7:0] ERR_CODEC = 8'd4;
    localparam [7:0] ERR_INTERNAL = 8'd8;
    localparam [7:0] PARSE_MALFORMED=1, PARSE_COMMUNITY=2,
                     PARSE_UNSUPPORTED_PDU=3, PARSE_SET_REJECT=4, PARSE_OID=5;

    reg [3:0] state;
    reg decoder_req, transaction_req, builder_req;
    reg [31:0] request_id_q;
    reg snapshot_req_q;
    reg txn_op_q;
    reg [7:0] txn_object_id_q;
    reg [7:0] builder_vb_length;
    reg [MAX_VB_BYTES*8-1:0] builder_vb_data;
    reg [7:0] decoder_msg_length_q;
    reg [MAX_MSG_BYTES*8-1:0] decoder_msg_bytes_q;
    reg [MAX_MSG_BYTES*8-1:0] decoder_msg_bytes_fire_q;
    reg decoder_error_q;
    reg [3:0] decoder_error_code_q;
    reg [31:0] decoder_request_id_q;
    reg decoder_op_q;
    reg [7:0] decoder_object_id_q;

    wire decoder_done, decoder_error;
    wire [3:0] decoder_error_code;
    wire external_valid, profile_done, profile_op;
    wire [7:0] external_error_code, external_object_id, vb_count_parse;
    wire [31:0] external_request_id;
    wire [MAX_VARBINDS*8-1:0] external_object_ids;
    reg profile_req;
    reg [7:0] profile_length;
    reg [MAX_MSG_BYTES*8-1:0] profile_bytes;
    reg before_first_q;
    reg [7:0] request_object_id_q;
    reg [7:0] request_objects [0:MAX_VARBINDS-1];
    reg [7:0] request_count_q, request_index_q;
    reg [MAX_MSG_BYTES*8-1:0] normalized_message;
    integer vb_offset;
    assign external_object_id=external_object_ids[7:0];
    afdx_snmp_profile_decoder #(.MAX_MSG_BYTES(MAX_MSG_BYTES),.MAX_VARBINDS(MAX_VARBINDS)) u_profile (
        .clk(clk),.rst_n(rst_n),.req(profile_req),.msg_length(profile_length),.msg_bytes(profile_bytes),
        .done(profile_done),.valid(external_valid),.error_code(external_error_code),
        .request_op(profile_op),.request_id(external_request_id),.object_count(vb_count_parse),.object_ids(external_object_ids));
    function [7:0] canonical_oid_prefix;
        input integer index;
        begin
            case (index)
                0: canonical_oid_prefix = 8'h2B;
                1: canonical_oid_prefix = 8'h06;
                2: canonical_oid_prefix = 8'h01;
                3: canonical_oid_prefix = 8'h04;
                4: canonical_oid_prefix = 8'h01;
                5: canonical_oid_prefix = 8'h81;
                6: canonical_oid_prefix = 8'hFD;
                7: canonical_oid_prefix = 8'h59;
                8: canonical_oid_prefix = 8'h01;
                9: canonical_oid_prefix = 8'h01;
                default: canonical_oid_prefix = 8'h00;
            endcase
        end
    endfunction

    // Keep the legacy transaction decoder's private input constant-shaped.
    // Only the validated operation and first object differ; the wire request ID
    // never travels through that historical 24-bit internal interface.
    always @* begin
        normalized_message=0;
        normalized_message[351:0]=352'h0005010159fd81010401062b0a060e30103000010200010245230103021da063696c62757006040001022a30;
        normalized_message[13*8+:8]=profile_op?8'ha1:8'ha0;
        normalized_message[41*8+:8]=(external_object_id>=1&&external_object_id<=25)?external_object_id:8'd1;
    end

    wire decoder_op;
    wire [31:0] decoder_request_id;
    wire [7:0] decoder_object_id;
    wire txn_rsp_valid, txn_rsp_error;
    wire [2:0] txn_rsp_error_code;
    wire [7:0] txn_rsp_object_id;
    wire [6:0] txn_rsp_length;
    wire [MAX_VB_BYTES*8-1:0] txn_rsp_bytes;
    wire builder_done, builder_valid;
    wire [7:0] builder_error_code;
    wire [MAX_RESPONSE_BYTES*8-1:0] builder_msg_data;
    wire m6b_snapshot_ack, m6b_snapshot_valid;
    wire [31:0] m6b_snapshot_id;
    wire [7:0] builder_msg_length;

    wire m6b_req_valid, m6b_req_op;
    wire [7:0] m6b_req_object_id;
    wire m6b_rsp_valid, m6b_rsp_error;
    wire [1:0] m6b_rsp_error_code;
    wire [7:0] m6b_rsp_object_id, m6b_rsp_asn1_type;
    wire [31:0] m6b_rsp_value;
    wire m6c_req;
    wire [7:0] m6c_object_id, m6c_asn1_type;
    wire [31:0] m6c_value;
    wire [1:0] m6c_response_status;
    wire m6c_done, m6c_error;
    wire [6:0] m6c_varbind_length;
    wire [MAX_VB_BYTES*8-1:0] m6c_varbind_bytes;
    wire [7:0] m6a_rd_addr;
    wire [31:0] m6a_rd_data;
    wire m6a_rd_valid;
    integer i;

    reg [MAX_VB_BYTES*8-1:0] transaction_high, exception_high;
    integer b;
    always @* begin
        transaction_high=0;exception_high=0;
        for(b=0;b<MAX_VB_BYTES;b=b+1) if(b<txn_rsp_length)
            transaction_high[MAX_VB_BYTES*8-1-b*8-:8]=txn_rsp_bytes[b*8+:8];
        exception_high[MAX_VB_BYTES*8-1-0*8-:8]=8'h30;
        exception_high[MAX_VB_BYTES*8-1-1*8-:8]=8'h0f;
        exception_high[MAX_VB_BYTES*8-1-2*8-:8]=8'h06;
        exception_high[MAX_VB_BYTES*8-1-3*8-:8]=8'h0b;
        for(b=0;b<10;b=b+1) exception_high[MAX_VB_BYTES*8-1-(4+b)*8-:8]=canonical_oid_prefix(b);
        exception_high[MAX_VB_BYTES*8-1-14*8-:8]=request_objects[request_index_q];
        exception_high[MAX_VB_BYTES*8-1-15*8-:8]=txn_rsp_error_code==1?8'h80:8'h82;
    end

    afdx_snmp_request_decoder #(.MAX_MSG_BYTES(MAX_MSG_BYTES)) u_decoder (
        .clk(clk), .rst(!rst_n), .req(decoder_req), .msg_length(decoder_msg_length_q),
        .msg_bytes(decoder_msg_bytes_fire_q), .done(decoder_done), .error(decoder_error),
        .error_code(decoder_error_code), .request_op(decoder_op),
        .request_id(decoder_request_id), .object_id(decoder_object_id),
        .community_length(), .community_bytes()
    );

    afdx_m6b_integration #(.CLK_HZ(CLK_HZ)) u_m6b (
        .clk(clk), .rst_n(rst_n), .snapshot_req(snapshot_req_q), .snapshot_ack(m6b_snapshot_ack),
        .snapshot_valid(m6b_snapshot_valid), .snapshot_id(m6b_snapshot_id), .event_clear(1'b0),
        .req_valid(m6b_req_valid), .req_op(m6b_req_op), .req_object_id(m6b_req_object_id),
        .rsp_valid(m6b_rsp_valid), .rsp_error(m6b_rsp_error),
        .rsp_error_code(m6b_rsp_error_code), .rsp_object_id(m6b_rsp_object_id),
        .rsp_asn1_type(m6b_rsp_asn1_type), .rsp_value(m6b_rsp_value),
        .m5_network_a_enable(m5_network_a_enable), .m5_network_b_enable(m5_network_b_enable),
        .m5_degraded_mode(m5_degraded_mode), .m5_redundancy_ok(m5_redundancy_ok),
        .m5_frame_count_match(m5_frame_count_match), .m5_active_byte_count_match(m5_active_byte_count_match),
        .m5_fault_applied_event(m5_fault_applied_event), .m5_rx_accepted_count(m5_rx_accepted_count),
        .m5_rx_accepted_a_count(m5_rx_accepted_a_count), .m5_rx_accepted_b_count(m5_rx_accepted_b_count),
        .m5_rx_duplicate_count(m5_rx_duplicate_count), .m5_rx_cross_network_duplicate_count(m5_rx_cross_network_duplicate_count),
        .m5_rx_same_network_repeat_count(m5_rx_same_network_repeat_count), .m5_rx_stale_count(m5_rx_stale_count),
        .m5_rx_sequence_gap_count(m5_rx_sequence_gap_count), .m5_tx_a_frame_count(m5_tx_a_frame_count),
        .m5_tx_b_frame_count(m5_tx_b_frame_count), .m5_tx_a_active_byte_count(m5_tx_a_active_byte_count),
        .m5_tx_b_active_byte_count(m5_tx_b_active_byte_count), .m5_tx_byte_mismatch_count(m5_tx_byte_mismatch_count),
        .m5_tx_frame_skew_cycle_count(m5_tx_frame_skew_cycle_count), .m5_tx_frame_done_skew_count(m5_tx_frame_done_skew_count),
        .m5_tx_er_mismatch_count(m5_tx_er_mismatch_count), .m5_tx_a_error_cycle_count(m5_tx_a_error_cycle_count),
        .m5_tx_b_error_cycle_count(m5_tx_b_error_cycle_count), .m5_tx_a_underrun_count(m5_tx_a_underrun_count),
        .m5_tx_b_underrun_count(m5_tx_b_underrun_count)
    );

    afdx_snmp_transaction #(.MAX_VB_BYTES(MAX_VB_BYTES)) u_transaction (
        .clk(clk), .rst(!rst_n), .req(transaction_req), .req_op(txn_op_q),
        .req_object_id(txn_object_id_q), .m6b_req_valid(m6b_req_valid),
        .m6b_req_op(m6b_req_op), .m6b_req_object_id(m6b_req_object_id),
        .m6b_rsp_valid(m6b_rsp_valid), .m6b_rsp_error(m6b_rsp_error),
        .m6b_rsp_error_code(m6b_rsp_error_code), .m6b_rsp_object_id(m6b_rsp_object_id),
        .m6b_rsp_asn1_type(m6b_rsp_asn1_type), .m6b_rsp_value(m6b_rsp_value),
        .m6c_req(m6c_req), .m6c_object_id(m6c_object_id), .m6c_asn1_type(m6c_asn1_type),
        .m6c_value(m6c_value), .m6c_response_status(m6c_response_status),
        .m6c_done(m6c_done), .m6c_error(m6c_error), .m6c_varbind_length(m6c_varbind_length),
        .m6c_varbind_bytes(m6c_varbind_bytes), .rsp_valid(txn_rsp_valid),
        .rsp_error(txn_rsp_error), .rsp_error_code(txn_rsp_error_code),
        .rsp_object_id(txn_rsp_object_id), .rsp_length(txn_rsp_length), .rsp_bytes(txn_rsp_bytes)
    );

    afdx_m6c_integration #(.MAX_VB_BYTES(MAX_VB_BYTES)) u_m6c (
        .clk(clk), .rst(!rst_n), .req(m6c_req), .object_id(m6c_object_id),
        .asn1_type(m6c_asn1_type), .value(m6c_value), .response_status(m6c_response_status),
        .done(m6c_done), .error(m6c_error), .varbind_length(m6c_varbind_length),
        .varbind_bytes(m6c_varbind_bytes)
    );

    afdx_snmp_response_builder #(.MAX_VARBIND_BYTES(MAX_VB_BYTES), .MAX_MSG_BYTES(MAX_RESPONSE_BYTES)) u_builder (
        .clk(clk), .rst_n(rst_n), .req(builder_req), .request_id(request_id_q),
        .varbind_data(builder_vb_data), .varbind_length(builder_vb_length),
        .done(builder_done), .valid(builder_valid), .error_code(builder_error_code),
        .msg_data(builder_msg_data), .msg_length(builder_msg_length)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE; profile_req<=0;profile_length<=0;profile_bytes<=0; decoder_req <= 0; transaction_req <= 0; builder_req <= 0; snapshot_req_q <= 1'b0;
            response_done <= 0; response_valid <= 0; response_error <= 0;
            response_error_code <= 0; response_length <= 0; response_bytes <= 0;
            request_id_q <= 0; txn_op_q <= 0; txn_object_id_q <= 0;
            before_first_q <= 0; request_object_id_q <= 0;
            request_count_q<=0;request_index_q<=0;
            for(i=0;i<MAX_VARBINDS;i=i+1) request_objects[i]<=0;
            decoder_msg_length_q <= 0; decoder_msg_bytes_q <= 0; decoder_msg_bytes_fire_q <= 0;
            decoder_error_q <= 0; decoder_error_code_q <= 0; decoder_request_id_q <= 0;
            decoder_op_q <= 0; decoder_object_id_q <= 0;
            builder_vb_length <= 0; builder_vb_data <= 0;
        end else begin
            snapshot_req_q <= 1'b0;profile_req<=0;
            decoder_req <= 0; transaction_req <= 0; builder_req <= 0;
            response_done <= 0;
            case (state)
                S_IDLE: if (req) begin
                    response_valid <= 0;
                    response_error <= 0;
                    response_error_code <= 0;
                    response_length <= 0;
                    response_bytes <= 0;
                    profile_length<=msg_length;profile_bytes<=msg_bytes;
                    state<=S_PROFILE_FIRE;
                end
                S_PROFILE_FIRE:begin profile_req<=1;state<=S_PROFILE_WAIT;end
                S_PROFILE_WAIT:if(profile_done)begin
                    if (external_valid) begin
                        request_id_q <= external_request_id;
                        request_count_q<=vb_count_parse;request_index_q<=0;
                        for(i=0;i<MAX_VARBINDS;i=i+1) request_objects[i]<=external_object_ids[i*8+:8];
                        builder_vb_data<=0;builder_vb_length<=0;
                        before_first_q <= (external_object_id == 0);
                        request_object_id_q <= external_object_id;
                        // Reload length in FIRE to refresh the frozen decoder's parser.
                        decoder_msg_length_q <= 0;
                        decoder_msg_bytes_q <= normalized_message;
                        decoder_msg_bytes_fire_q <= normalized_message;
                        state <= S_DEC_FIRE;
                    end else begin
                        response_error <= 1;
                        response_error_code <= external_error_code;
                        state <= S_DONE;
                    end
                end
                S_DEC_FIRE: begin
                    decoder_msg_length_q <= 44;
                    decoder_req <= 1;
                    state <= S_WAIT_DEC;
                end
                S_WAIT_DEC: if (decoder_done) begin
                    decoder_error_q <= decoder_error;
                    decoder_error_code_q <= decoder_error_code;
                    decoder_request_id_q <= decoder_request_id;
                    decoder_op_q <= decoder_op;
                    decoder_object_id_q <= decoder_object_id;
                    state <= S_DEC_CHECK;
                end
                S_DEC_CHECK: begin
                    if (decoder_error_q) begin
                        response_error <= 1;
                        response_error_code <= {4'd0, decoder_error_code_q};
                        state <= S_DONE;
                    end else begin
                        txn_op_q <= decoder_op_q;
                        txn_object_id_q <= request_object_id_q;
                        state <= S_SNAPSHOT_FIRE;
                    end
                end
                S_SNAPSHOT_FIRE: begin
                    snapshot_req_q <= 1'b1;
                    state <= S_SNAPSHOT_WAIT;
                end
                S_SNAPSHOT_WAIT: begin
                    if (m6b_snapshot_ack)
                        state <= S_TXN_FIRE;
                end
                S_TXN_FIRE: begin
                    transaction_req <= 1;
                    state <= S_WAIT_TXN;
                end
                S_WAIT_TXN: if (txn_rsp_valid) begin
                    if (!txn_rsp_error || txn_rsp_error_code==1 || txn_rsp_error_code==ERR_END_OF_MIB_VIEW) begin
                        vb_offset=builder_vb_length;
                        if(vb_offset+(txn_rsp_error?17:txn_rsp_length)>MAX_VB_BYTES) begin
                            response_error<=1;response_error_code<=ERR_INTERNAL;state<=S_DONE;
                        end else begin
                            // Shift one masked packed VarBind, rather than a cascade of
                            // variable-index writes. Same byte order, bounded barrel shifter.
                            if(!txn_rsp_error) begin
                                builder_vb_data<=builder_vb_data | (transaction_high >> {builder_vb_length,3'b000});
                                builder_vb_length<=builder_vb_length+txn_rsp_length;
                            end else begin
                                builder_vb_data<=builder_vb_data | (exception_high >> {builder_vb_length,3'b000});
                                builder_vb_length<=builder_vb_length+8'd17;
                            end
                            if(request_index_q+1<request_count_q) begin
                                request_index_q<=request_index_q+1;
                                txn_object_id_q<=request_objects[request_index_q+1];state<=S_TXN_FIRE;
                            end else state<=S_BLD_FIRE;
                        end
                    end else begin
                        response_error<=1;response_error_code<={5'd0,txn_rsp_error_code};state<=S_DONE;
                    end
                end
                S_BLD_FIRE: begin
                    builder_req <= 1;
                    state <= S_WAIT_BLD;
                end
                S_WAIT_BLD: if (builder_done) begin
                    if (builder_valid) begin
                        response_valid <= 1; response_error <= 0;
                        response_error_code <= 0; response_length <= builder_msg_length;
                        response_bytes <= builder_msg_data;
                    end else begin
                        response_error <= 1; response_error_code <= builder_error_code;
                    end
                    state <= S_DONE;
                end
                S_DONE: begin response_done <= 1; state <= S_IDLE; end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
