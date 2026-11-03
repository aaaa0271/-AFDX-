module afdx_m6e_udp_rx_buffer #(
    parameter integer MAX_SNMP_BYTES = 96
)(
    input  wire                         clk,
    input  wire                         rst,
    input  wire                         m6e_busy,
    input  wire                         meta_valid,
    input  wire [31:0]                  src_ip,
    input  wire [15:0]                  udp_src_port,
    input  wire [15:0]                  udp_dst_port,
    input  wire [10:0]                  payload_length,
    input  wire [7:0]                   payload_data,
    input  wire                         payload_valid,
    output wire                         payload_ready,
    input  wire                         payload_sof,
    input  wire                         payload_eof,
    input  wire                         frame_done,
    input  wire                         frame_valid,
    output reg                          rx_commit,
    output reg [MAX_SNMP_BYTES*8-1:0]   active_msg_bytes,
    output reg [10:0]                   active_msg_length,
    output reg [31:0]                   active_requester_ip,
    output reg [15:0]                   active_requester_port
);

localparam [15:0] SNMP_PORT = 16'd161;
assign payload_ready = 1'b1;

reg admitted;
reg in_frame;
reg saw_sof;
reg saw_eof;
reg bad_stream;
reg [10:0] capture_count;
reg [MAX_SNMP_BYTES*8-1:0] capture_buf;
reg [10:0] admitted_length;
reg [31:0] admitted_ip;
reg [15:0] admitted_port;
integer i;

always @(posedge clk) begin
    if (rst) begin
        admitted <= 1'b0;
        in_frame <= 1'b0;
        saw_sof <= 1'b0;
        saw_eof <= 1'b0;
        bad_stream <= 1'b0;
        capture_count <= 11'd0;
        capture_buf <= {MAX_SNMP_BYTES*8{1'b0}};
        admitted_length <= 11'd0;
        admitted_ip <= 32'd0;
        admitted_port <= 16'd0;
        rx_commit <= 1'b0;
        active_msg_bytes <= {MAX_SNMP_BYTES*8{1'b0}};
        active_msg_length <= 11'd0;
        active_requester_ip <= 32'd0;
        active_requester_port <= 16'd0;
    end else begin
        rx_commit <= 1'b0;

        if (meta_valid && !in_frame) begin
            in_frame <= 1'b1;
            admitted <= (udp_dst_port == SNMP_PORT) && !m6e_busy &&
                        (payload_length != 11'd0) &&
                        (payload_length <= MAX_SNMP_BYTES);
            admitted_length <= payload_length;
            admitted_ip <= src_ip;
            admitted_port <= udp_src_port;
            capture_count <= 11'd0;
            saw_sof <= 1'b0;
            saw_eof <= 1'b0;
            bad_stream <= 1'b0;
            capture_buf <= {MAX_SNMP_BYTES*8{1'b0}};
        end

        if (in_frame && payload_valid) begin
            if (payload_sof && !saw_sof && (capture_count == 11'd0))
                saw_sof <= 1'b1;
            else if (payload_sof)
                bad_stream <= 1'b1;
            if (payload_eof)
                saw_eof <= 1'b1;

            if (admitted) begin
                if (capture_count < MAX_SNMP_BYTES)
                    capture_buf[capture_count*8 +: 8] <= payload_data;
                else
                    bad_stream <= 1'b1;
            end
            capture_count <= capture_count + 11'd1;
        end

        if (in_frame && frame_done) begin
            if (admitted && frame_valid && !bad_stream && (saw_sof || (payload_valid && payload_sof)) &&
                (saw_eof || (payload_valid && payload_eof)) &&
                ((capture_count + (payload_valid ? 11'd1 : 11'd0)) == admitted_length) &&
                (admitted_length != 11'd0)) begin
                active_msg_bytes <= capture_buf;
                if (payload_valid && (capture_count < MAX_SNMP_BYTES))
                    active_msg_bytes[capture_count*8 +: 8] <= payload_data;
                active_msg_length <= admitted_length;
                active_requester_ip <= admitted_ip;
                active_requester_port <= admitted_port;
                rx_commit <= 1'b1;
            end
            in_frame <= 1'b0;
            admitted <= 1'b0;
            capture_count <= 11'd0;
            saw_sof <= 1'b0;
            bad_stream <= 1'b0;
        end
    end
end
endmodule
