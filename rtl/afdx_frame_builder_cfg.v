module afdx_frame_builder_cfg (
// LEGACY (M4 TX path): not instantiated by AFDX_competition_top or the
// competition AFDX_top; retained only for legacy ModelSim regression
// coverage. Do not use for new work.
    input  wire        clk,
    input  wire        rst,

    // Start one frame
    input  wire        start,

    // AFDX sequence number
    input  wire [7:0]  seq_num,

    // ----------------------------------------------
    // Frame configuration
    // ----------------------------------------------

    input  wire [47:0] cfg_dst_mac,
    input  wire [47:0] cfg_src_mac,

    input  wire [31:0] cfg_src_ip,
    input  wire [31:0] cfg_dst_ip,

    input  wire [15:0] cfg_src_port,
    input  wire [15:0] cfg_dst_port,

    // Fixed 4-byte payload in M2-C
    input  wire [31:0] payload_data,

    // ----------------------------------------------
    // Output byte stream
    // ----------------------------------------------

    output reg  [7:0]  tx_data,
    output reg         tx_valid,
    input  wire        tx_ready,

    output reg         busy,
    output reg         done
);


// ----------------------------------------------------
// Internal state
// ----------------------------------------------------

reg [7:0] byte_index;


// ----------------------------------------------------
// Latched configuration
//
// Configuration is captured at frame start.
// External changes during transmission must NOT
// corrupt the current frame.
// ----------------------------------------------------

reg [47:0] dst_mac_latched;
reg [47:0] src_mac_latched;

reg [31:0] src_ip_latched;
reg [31:0] dst_ip_latched;

reg [15:0] src_port_latched;
reg [15:0] dst_port_latched;

reg [31:0] payload_latched;

reg [7:0]  seq_latched;


// ----------------------------------------------------
// IPv4 checksum
//
// IPv4 total length:
//
// 20 bytes IPv4 header
//  8 bytes UDP header
//  4 bytes payload
//
// Total = 32 = 0x0020
// ----------------------------------------------------

wire [15:0] ip_checksum;

ipv4_checksum u_ipv4_checksum (
    .src_ip       (src_ip_latched),
    .dst_ip       (dst_ip_latched),
    .total_length (16'h0020),
    .checksum     (ip_checksum)
);


// ----------------------------------------------------
// Byte generation
//
//  0 ~ 13 : Ethernet Header
// 14 ~ 33 : IPv4 Header
// 34 ~ 41 : UDP Header
// 42 ~ 45 : Payload
// 46 ~ 58 : Ethernet Padding
// 59      : AFDX Sequence Number
// ----------------------------------------------------

always @(*) begin

    case (byte_index)

        // ==================================================
        // Ethernet Destination MAC
        // ==================================================

        8'd0: tx_data = dst_mac_latched[47:40];
        8'd1: tx_data = dst_mac_latched[39:32];
        8'd2: tx_data = dst_mac_latched[31:24];
        8'd3: tx_data = dst_mac_latched[23:16];
        8'd4: tx_data = dst_mac_latched[15:8];
        8'd5: tx_data = dst_mac_latched[7:0];


        // ==================================================
        // Ethernet Source MAC
        // ==================================================

        8'd6:  tx_data = src_mac_latched[47:40];
        8'd7:  tx_data = src_mac_latched[39:32];
        8'd8:  tx_data = src_mac_latched[31:24];
        8'd9:  tx_data = src_mac_latched[23:16];
        8'd10: tx_data = src_mac_latched[15:8];
        8'd11: tx_data = src_mac_latched[7:0];


        // EtherType = IPv4
        8'd12: tx_data = 8'h08;
        8'd13: tx_data = 8'h00;


        // ==================================================
        // IPv4 Header
        // ==================================================

        // Version = 4, IHL = 5
        8'd14: tx_data = 8'h45;

        // DSCP / ECN
        8'd15: tx_data = 8'h00;

        // Total Length = 32
        8'd16: tx_data = 8'h00;
        8'd17: tx_data = 8'h20;

        // Identification
        8'd18: tx_data = 8'h00;
        8'd19: tx_data = 8'h00;

        // Flags + Fragment Offset
        8'd20: tx_data = 8'h00;
        8'd21: tx_data = 8'h00;

        // TTL = 64
        8'd22: tx_data = 8'h40;

        // Protocol = UDP = 17
        8'd23: tx_data = 8'h11;

        // Dynamic IPv4 Header Checksum
        8'd24: tx_data = ip_checksum[15:8];
        8'd25: tx_data = ip_checksum[7:0];


        // Source IP
        8'd26: tx_data = src_ip_latched[31:24];
        8'd27: tx_data = src_ip_latched[23:16];
        8'd28: tx_data = src_ip_latched[15:8];
        8'd29: tx_data = src_ip_latched[7:0];


        // Destination IP
        8'd30: tx_data = dst_ip_latched[31:24];
        8'd31: tx_data = dst_ip_latched[23:16];
        8'd32: tx_data = dst_ip_latched[15:8];
        8'd33: tx_data = dst_ip_latched[7:0];


        // ==================================================
        // UDP Header
        // ==================================================

        // Source Port
        8'd34: tx_data = src_port_latched[15:8];
        8'd35: tx_data = src_port_latched[7:0];

        // Destination Port
        8'd36: tx_data = dst_port_latched[15:8];
        8'd37: tx_data = dst_port_latched[7:0];

        // UDP Length = 12
        8'd38: tx_data = 8'h00;
        8'd39: tx_data = 8'h0C;

        // UDP checksum
        // Temporarily zero in M2-C.
        8'd40: tx_data = 8'h00;
        8'd41: tx_data = 8'h00;


        // ==================================================
        // 4-byte Payload
        // ==================================================

        8'd42: tx_data = payload_latched[31:24];
        8'd43: tx_data = payload_latched[23:16];
        8'd44: tx_data = payload_latched[15:8];
        8'd45: tx_data = payload_latched[7:0];


        // ==================================================
        // Padding
        //
        // byte 46 ~ 58 use default 00
        // ==================================================


        // ==================================================
        // AFDX Sequence Number
        // ==================================================

        8'd59: tx_data = seq_latched;


        default:
            tx_data = 8'h00;

    endcase

end


// ----------------------------------------------------
// Transmission control
// ----------------------------------------------------

always @(posedge clk) begin

    if (rst) begin

        byte_index <= 8'd0;

        tx_valid <= 1'b0;

        busy <= 1'b0;
        done <= 1'b0;


        dst_mac_latched <= 48'd0;
        src_mac_latched <= 48'd0;

        src_ip_latched <= 32'd0;
        dst_ip_latched <= 32'd0;

        src_port_latched <= 16'd0;
        dst_port_latched <= 16'd0;

        payload_latched <= 32'd0;

        seq_latched <= 8'd0;

    end
    else begin

        done <= 1'b0;


        // ==================================================
        // Start new frame
        // ==================================================

        if (!busy && start) begin

            byte_index <= 8'd0;

            // Latch ALL configuration
            dst_mac_latched <= cfg_dst_mac;
            src_mac_latched <= cfg_src_mac;

            src_ip_latched <= cfg_src_ip;
            dst_ip_latched <= cfg_dst_ip;

            src_port_latched <= cfg_src_port;
            dst_port_latched <= cfg_dst_port;

            payload_latched <= payload_data;

            seq_latched <= seq_num;


            busy <= 1'b1;
            tx_valid <= 1'b1;

        end


        // ==================================================
        // Byte transfer
        // ==================================================

        else if (busy && tx_valid && tx_ready) begin

            if (byte_index == 8'd59) begin

                byte_index <= 8'd0;

                busy <= 1'b0;
                tx_valid <= 1'b0;

                done <= 1'b1;

            end
            else begin

                byte_index <= byte_index + 1'b1;

            end

        end

    end

end

endmodule
