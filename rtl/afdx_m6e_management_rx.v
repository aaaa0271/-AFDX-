`timescale 1ns/1ps
// LEGACY (M6E management path): not instantiated by AFDX_competition_top or
// the competition AFDX_top; retained only for legacy ModelSim regression
// coverage. Do not use for new work.
// Independent management RX; never changes the frozen data-plane whitelist.
// L2 only replays CRC-valid bodies. UDP161 and destination MAC/IP admission
// precede the frozen M3-D sequence check. 02A buffers the actual parser stream.
module afdx_m6e_management_rx #(
    parameter [47:0] MANAGEMENT_MAC = 48'h030000000001,
    parameter [31:0] MANAGEMENT_IP = 32'hc0a80101
)(
    input wire clk, rst,
    input wire [7:0] gmii_rxd,
    input wire gmii_rx_dv, gmii_rx_er,
    input wire management_busy,
    output wire meta_valid,
    output wire [31:0] src_ip,
    output wire [15:0] udp_src_port, udp_dst_port,
    output wire [10:0] payload_length,
    output wire [7:0] payload_data,
    output wire payload_valid, payload_sof, payload_eof,
    input wire payload_ready,
    output wire frame_done, frame_valid,
    output wire rx_result_valid, rx_accept, rx_reject,
    output wire crc_error, boundary_busy
);
wire [7:0] body_data, parser_data, sequence_number;
wire body_valid, body_ready, body_sof, body_eof;
wire [10:0] body_length, parser_length;
wire [47:0] destination_mac;
wire [31:0] parser_ip, destination_ip;
wire [15:0] parser_sport, parser_dport;
wire parser_meta, parser_valid, parser_ready, parser_sof, parser_eof;
wire parser_done, parser_good;
wire sequence_result, sequence_accept, sequence_reject;
reg admitted;
wire check_sequence = parser_done && parser_good && admitted;
wire reject_frame = parser_done && !(parser_good && admitted);
assign rx_result_valid = reject_frame || sequence_result;
assign rx_accept = sequence_result && sequence_accept;
assign rx_reject = reject_frame || (sequence_result && sequence_reject);
always @(posedge clk) begin
    if(rst) admitted <= 0;
    else if(parser_meta)
        admitted <= destination_mac == MANAGEMENT_MAC && destination_ip == MANAGEMENT_IP &&
                    parser_dport == 161 && parser_length != 0 && parser_length <= 96 &&
                    !management_busy && !boundary_busy;
    else if(rx_result_valid) admitted <= 0;
end
gmii_rx_adapter u_l2 (
    .clk(clk),.rst(rst),.gmii_rxd(gmii_rxd),.gmii_rx_dv(gmii_rx_dv),.gmii_rx_er(gmii_rx_er),
    .m_data(body_data),.m_valid(body_valid),.m_ready(body_ready),.m_sof(body_sof),.m_eof(body_eof),
    .m_frame_length(body_length),.crc_error(crc_error),.good_frame(),.output_frame_done(),
    .format_error(),.length_error(),.rx_error(),.overflow_error());
afdx_eth_ipv4_udp_parser u_parser (
    .clk(clk),.rst(rst),.s_data(body_data),.s_valid(body_valid),.s_ready(body_ready),
    .s_sof(body_sof),.s_eof(body_eof),.s_frame_length(body_length),
    .dst_mac(destination_mac),.src_ip(parser_ip),.dst_ip(destination_ip),
    .udp_src_port(parser_sport),.udp_dst_port(parser_dport),.payload_length(parser_length),
    .meta_valid(parser_meta),.afdx_sequence(sequence_number),
    .payload_data(parser_data),.payload_valid(parser_valid),.payload_ready(parser_ready),
    .payload_sof(parser_sof),.payload_eof(parser_eof),.frame_done(parser_done),.frame_valid(parser_good),
    .src_mac(),.ether_type(),.ip_total_length(),.ip_ttl(),.ip_protocol(),.ip_header_checksum(),
    .udp_length(),.udp_checksum(),.padding_length(),.ether_type_error(),.ip_version_error(),
    .ip_ihl_error(),.ip_checksum_error(),.ip_protocol_error(),.ip_length_error(),.udp_length_error(), .udp_checksum_error(),.structure_error());
afdx_sequence_integrity u_sequence (
    .clk(clk),.rst(rst),.check_valid(check_sequence),.vl_index(2'd0),.sequence_number(sequence_number),
    .result_valid(sequence_result),.seq_accept(sequence_accept),.seq_reject(sequence_reject),
    .first_frame(),.reset_sequence(),.single_loss(),.duplicate_error(),.sequence_error(),.psn_before(),.psn_after());
afdx_m6e_02a_boundary u_boundary (
    .clk(clk),.rst(rst),.src_ip(parser_ip),.udp_src_port(parser_sport),.udp_dst_port(parser_dport),
    .payload_length(parser_length),.meta_valid(parser_meta),.payload_data(parser_data),
    .payload_valid(parser_valid),.payload_ready(parser_ready),.payload_sof(parser_sof),.payload_eof(parser_eof),
    .rx_result_valid(rx_result_valid),.rx_accept(rx_accept),.rx_reject(rx_reject),
    .meta_valid_out(meta_valid),.src_ip_out(src_ip),.udp_src_port_out(udp_src_port),
    .udp_dst_port_out(udp_dst_port),.payload_length_out(payload_length),
    .payload_data_out(payload_data),.payload_valid_out(payload_valid),.payload_ready_out(payload_ready),
    .payload_sof_out(payload_sof),.payload_eof_out(payload_eof),
    .frame_done(frame_done),.frame_valid(frame_valid),.busy(boundary_busy));
endmodule
