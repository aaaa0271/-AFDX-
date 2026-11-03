// ============================================================
// afdx_service_frame_builder.v
//
// M6E-01B: variable-length Ethernet/IPv4/UDP/AFDX body builder.
//
// Scope:
//   - 1..MAX_SNMP_BYTES payload bytes (default 96)
//   - LSB-first packed payload convention:
//       payload_bytes[n*8 +: 8] is payload byte n
//   - IPv4 header checksum uses the existing ipv4_checksum block
//   - UDP checksum remains 16'h0000, matching the frozen M2 TX path
//   - Ethernet padding is inserted so that the AFDX sequence byte is
//     the final byte of a minimum 60-byte body when payload <= 17 bytes
//   - tx_eof marks the AFDX sequence byte and remains asserted during
//     backpressure until that final byte is accepted
//
// This module does NOT emit preamble/SFD/FCS/IFG.  That is M6E-01C.
// ============================================================

module afdx_service_frame_builder #(
    parameter integer MAX_SNMP_BYTES = 516
)(
    input  wire                           clk,
    input  wire                           rst,

    // Start one frame.  start is accepted only while !busy and when
    // payload_length is in the supported range 1..MAX_SNMP_BYTES.
    input  wire                           start,

    // AFDX sequence number appended as the final body byte.
    input  wire [7:0]                     seq_num,

    // Frame configuration.
    input  wire [47:0]                    cfg_dst_mac,
    input  wire [47:0]                    cfg_src_mac,
    input  wire [31:0]                    cfg_src_ip,
    input  wire [31:0]                    cfg_dst_ip,
    input  wire [15:0]                    cfg_src_port,
    input  wire [15:0]                    cfg_dst_port,

    // Variable payload.  Byte n is payload_bytes[n*8 +: 8].
    input  wire [10:0]                    payload_length,
    input  wire [MAX_SNMP_BYTES*8-1:0]    payload_bytes,

    // Output Ethernet body byte stream (no preamble/SFD/FCS/IFG).
    output reg  [7:0]                     tx_data,
    output reg                            tx_valid,
    output reg                            tx_eof,
    input  wire                           tx_ready,

    output reg                            busy,
    output reg                            done
);


// ------------------------------------------------------------
// Latched frame context.
// External changes after start must not affect the active frame.
// ------------------------------------------------------------

reg [47:0] dst_mac_latched;
reg [47:0] src_mac_latched;
reg [31:0] src_ip_latched;
reg [31:0] dst_ip_latched;
reg [15:0] src_port_latched;
reg [15:0] dst_port_latched;
reg [10:0] payload_length_latched;
reg [MAX_SNMP_BYTES*8-1:0] payload_latched;
reg [7:0]  seq_latched;

// Derived lengths, latched at frame start.
reg [15:0] udp_length_latched;
reg [15:0] ip_total_length_latched;
reg [10:0] seq_index_latched;

// Current Ethernet-body byte index.
reg [10:0] byte_index;

integer payload_byte_index;


// ------------------------------------------------------------
// IPv4 header checksum.
// ------------------------------------------------------------

wire [15:0] ip_checksum;

ipv4_checksum u_ipv4_checksum (
    .src_ip       (src_ip_latched),
    .dst_ip       (dst_ip_latched),
    .total_length (ip_total_length_latched),
    .checksum     (ip_checksum)
);


// ------------------------------------------------------------
// Combinational byte generation.
//
// Body layout:
//   0..13                    Ethernet header
//   14..33                   IPv4 header
//   34..41                   UDP header
//   42..(41+N)               payload, N bytes
//   optional zero padding
//   seq_index_latched         AFDX sequence, final body byte
//
// N <= 17: sequence index is 59, body length is 60.
// N >= 18: sequence immediately follows payload.
// ------------------------------------------------------------

always @(*) begin

    tx_data = 8'h00;
    tx_eof  = 1'b0;

    payload_byte_index = 0;

    // Ethernet destination MAC.
    case (byte_index)
        8'd0:  tx_data = dst_mac_latched[47:40];
        8'd1:  tx_data = dst_mac_latched[39:32];
        8'd2:  tx_data = dst_mac_latched[31:24];
        8'd3:  tx_data = dst_mac_latched[23:16];
        8'd4:  tx_data = dst_mac_latched[15:8];
        8'd5:  tx_data = dst_mac_latched[7:0];

        // Ethernet source MAC.
        8'd6:  tx_data = src_mac_latched[47:40];
        8'd7:  tx_data = src_mac_latched[39:32];
        8'd8:  tx_data = src_mac_latched[31:24];
        8'd9:  tx_data = src_mac_latched[23:16];
        8'd10: tx_data = src_mac_latched[15:8];
        8'd11: tx_data = src_mac_latched[7:0];

        // EtherType = IPv4.
        8'd12: tx_data = 8'h08;
        8'd13: tx_data = 8'h00;

        // IPv4 header.
        8'd14: tx_data = 8'h45;  // Version 4, IHL 5
        8'd15: tx_data = 8'h00;  // DSCP / ECN
        8'd16: tx_data = ip_total_length_latched[15:8];
        8'd17: tx_data = ip_total_length_latched[7:0];
        8'd18: tx_data = 8'h00;  // Identification
        8'd19: tx_data = 8'h00;
        8'd20: tx_data = 8'h00;  // Flags + Fragment Offset
        8'd21: tx_data = 8'h00;
        8'd22: tx_data = 8'h40;  // TTL = 64
        8'd23: tx_data = 8'h11;  // Protocol = UDP
        8'd24: tx_data = ip_checksum[15:8];
        8'd25: tx_data = ip_checksum[7:0];
        8'd26: tx_data = src_ip_latched[31:24];
        8'd27: tx_data = src_ip_latched[23:16];
        8'd28: tx_data = src_ip_latched[15:8];
        8'd29: tx_data = src_ip_latched[7:0];
        8'd30: tx_data = dst_ip_latched[31:24];
        8'd31: tx_data = dst_ip_latched[23:16];
        8'd32: tx_data = dst_ip_latched[15:8];
        8'd33: tx_data = dst_ip_latched[7:0];

        // UDP header.
        8'd34: tx_data = src_port_latched[15:8];
        8'd35: tx_data = src_port_latched[7:0];
        8'd36: tx_data = dst_port_latched[15:8];
        8'd37: tx_data = dst_port_latched[7:0];
        8'd38: tx_data = udp_length_latched[15:8];
        8'd39: tx_data = udp_length_latched[7:0];
        8'd40: tx_data = 8'h00;  // UDP checksum = disabled for IPv4
        8'd41: tx_data = 8'h00;

        default: begin

            // Payload bytes are replayed exactly in LSB-first packed order.
            if ((byte_index >= 8'd42) &&
                (byte_index < (8'd42 + payload_length_latched))) begin

                payload_byte_index = byte_index - 8'd42;
                tx_data = payload_latched[payload_byte_index*8 +: 8];

            end
            else if (byte_index == seq_index_latched) begin

                tx_data = seq_latched;

            end
            else begin

                // Ethernet padding region is all zero.
                tx_data = 8'h00;

            end

        end
    endcase

    // EOF belongs to the sequence byte.  Qualifying with tx_valid keeps
    // eof low while idle and makes it stable during a final-byte stall.
    if (tx_valid && (byte_index == seq_index_latched)) begin
        tx_eof = 1'b1;
    end

end


// ------------------------------------------------------------
// Transmission control.
// ------------------------------------------------------------

always @(posedge clk) begin

    if (rst) begin

        dst_mac_latched        <= 48'd0;
        src_mac_latched        <= 48'd0;
        src_ip_latched         <= 32'd0;
        dst_ip_latched         <= 32'd0;
        src_port_latched       <= 16'd0;
        dst_port_latched       <= 16'd0;
        payload_length_latched <= 8'd0;
        payload_latched        <= {MAX_SNMP_BYTES*8{1'b0}};
        seq_latched            <= 8'd0;

        udp_length_latched      <= 16'd0;
        ip_total_length_latched <= 16'd0;
        seq_index_latched       <= 8'd0;

        byte_index <= 8'd0;
        tx_valid   <= 1'b0;
        busy       <= 1'b0;
        done       <= 1'b0;

    end
    else begin

        done <= 1'b0;

        // Accept a new frame only while idle and only for the bounded
        // M6E message length range.  Invalid start requests are ignored.
        if (!busy && start &&
            (payload_length >= 8'd1) &&
            (payload_length <= MAX_SNMP_BYTES)) begin

            dst_mac_latched        <= cfg_dst_mac;
            src_mac_latched        <= cfg_src_mac;
            src_ip_latched         <= cfg_src_ip;
            dst_ip_latched         <= cfg_dst_ip;
            src_port_latched       <= cfg_src_port;
            dst_port_latched       <= cfg_dst_port;
            payload_length_latched <= payload_length;
            payload_latched        <= payload_bytes;
            seq_latched            <= seq_num;

            udp_length_latched      <= 16'd8  + payload_length;
            ip_total_length_latched <= 16'd28 + payload_length;

            if (payload_length <= 8'd17) begin
                seq_index_latched <= 8'd59;
            end
            else begin
                seq_index_latched <= 8'd42 + payload_length;
            end

            byte_index <= 8'd0;
            tx_valid   <= 1'b1;
            busy       <= 1'b1;

        end
        else if (busy && tx_valid && tx_ready) begin

            if (byte_index == seq_index_latched) begin

                byte_index <= 8'd0;
                tx_valid   <= 1'b0;
                busy       <= 1'b0;
                done       <= 1'b1;

            end
            else begin

                byte_index <= byte_index + 1'b1;

            end

        end

    end

end

endmodule
