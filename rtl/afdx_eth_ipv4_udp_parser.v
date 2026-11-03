module afdx_eth_ipv4_udp_parser #(
    parameter integer MAX_PAYLOAD_BYTES = 1471
)(
    input  wire        clk,
    input  wire        rst,

    // ========================================================
    // Input stream from gmii_rx_adapter
    //
    // Preamble / SFD / FCS have already been removed.
    // FCS has already been verified by M3-A.
    // ========================================================

    input  wire [7:0]  s_data,
    input  wire        s_valid,
    output wire        s_ready,

    input  wire        s_sof,
    input  wire        s_eof,

    input  wire [10:0] s_frame_length,


    // ========================================================
    // Parsed Ethernet metadata
    // ========================================================

    output reg  [47:0] dst_mac,
    output reg  [47:0] src_mac,
    output reg  [15:0] ether_type,


    // ========================================================
    // Parsed IPv4 metadata
    // ========================================================

    output reg  [15:0] ip_total_length,
    output reg  [7:0]  ip_ttl,
    output reg  [7:0]  ip_protocol,

    output reg  [15:0] ip_header_checksum,

    output reg  [31:0] src_ip,
    output reg  [31:0] dst_ip,


    // ========================================================
    // Parsed UDP metadata
    // ========================================================

    output reg  [15:0] udp_src_port,
    output reg  [15:0] udp_dst_port,
    output reg  [15:0] udp_length,
    output reg  [15:0] udp_checksum,

    output reg  [10:0] payload_length,
    output reg  [4:0]  padding_length,


    // ========================================================
    // AFDX metadata
    //
    // Sequence integrity is NOT checked here.
    // M3-D will perform that function.
    // ========================================================

    output reg  [7:0]  afdx_sequence,


    // ========================================================
    // Header metadata is complete.
    //
    // One-clock pulse after UDP header has been parsed.
    // ========================================================

    output reg         meta_valid,


    // ========================================================
    // Streaming UDP payload output
    //
    // This is still an INTERNAL stream.
    // Final application commit occurs after VL and
    // sequence-integrity checks in later stages.
    // ========================================================

    output wire [7:0]  payload_data,
    output wire        payload_valid,
    input  wire        payload_ready,

    output wire        payload_sof,
    output wire        payload_eof,


    // ========================================================
    // Frame result
    //
    // frame_done:
    //   pulse for every received frame.
    //
    // frame_valid:
    //   pulse only when Ethernet/IP/UDP structural
    //   parsing succeeded.
    // ========================================================

    output reg         frame_done,
    output reg         frame_valid,


    // ========================================================
    // Error pulses
    // ========================================================

    output reg         ether_type_error,
    output reg         ip_version_error,
    output reg         ip_ihl_error,
    output reg         ip_checksum_error,
    output reg         ip_protocol_error,
    output reg         ip_length_error,
    output reg         udp_length_error,
    output reg         udp_checksum_error,
    output reg         structure_error
);


// ============================================================
// State
// ============================================================

localparam [0:0]
    ST_IDLE = 1'b0,
    ST_RECV = 1'b1;

reg state;


// ============================================================
// Receive position
// ============================================================

reg [10:0] byte_index;

reg [10:0] frame_length_latched;


// ============================================================
// Payload tracking
// ============================================================

reg [10:0] payload_count;


// ============================================================
// Frame error latch
//
// Once any header/structure error occurs, payload delivery
// for that frame is suppressed.
// ============================================================

reg frame_bad_latched;


// ============================================================
// IPv4 checksum accumulation
//
// IPv4 checksum validation:
//
// Sum all ten 16-bit header words including the checksum.
// After end-around carry folding, result must equal FFFF.
// ============================================================

reg [31:0] ip_sum;
reg [7:0]  ip_word_high;

// UDP checksum accumulation covers the IPv4 pseudo-header, UDP header, and payload.
reg [31:0] udp_sum;
reg [7:0]  udp_word_high;
reg        udp_word_high_valid;


function [15:0] fold_sum16;

    input [31:0] sum_in;

    reg [31:0] temp;

    begin

        temp =
            {16'd0, sum_in[15:0]}
            +
            {16'd0, sum_in[31:16]};

        temp =
            {16'd0, temp[15:0]}
            +
            {16'd0, temp[31:16]};

        fold_sum16 = temp[15:0];

    end

endfunction


wire [31:0] ip_sum_with_current_word;

assign ip_sum_with_current_word =
    ip_sum
    +
    {16'd0, ip_word_high, s_data};


wire [15:0] ip_sum_folded;

assign ip_sum_folded =
    fold_sum16(
        ip_sum_with_current_word
    );


// ============================================================
// Candidate UDP length
//
// Meaningful when byte_index == 39.
// ============================================================

wire [15:0] udp_length_candidate;

assign udp_length_candidate =
    {
        udp_length[15:8],
        s_data
    };

wire [31:0] udp_initial_sum;
wire [31:0] udp_final_sum;
wire [15:0] udp_final_folded;
wire        udp_checksum_bad;

assign udp_initial_sum =
    {16'd0, src_ip[31:16]} + {16'd0, src_ip[15:0]} +
    {16'd0, dst_ip[31:16]} + {16'd0, dst_ip[15:0]} +
    32'h0000_0011 + {16'd0, udp_length_candidate} +
    {16'd0, udp_src_port} + {16'd0, udp_dst_port} +
    {16'd0, udp_length_candidate};

assign udp_final_sum = udp_sum +
    (udp_word_high_valid ? {16'd0, udp_word_high, 8'h00} : 32'd0);
assign udp_final_folded = fold_sum16(udp_final_sum);
assign udp_checksum_bad = (udp_checksum != 16'h0000) &&
                          (udp_final_folded != 16'hFFFF);


// ============================================================
// Structural calculations
//
// Current project AFDX body:
//
// Ethernet Header       14
// IPv4 packet           ip_total_length
// Padding               0..16
// Sequence               1
//
// Therefore:
//
// minimum body length
// = 14 + IP total length + 1
// = 15 + IP total length
// ============================================================

wire [16:0] frame_length_ext;

assign frame_length_ext =
    {6'd0, frame_length_latched};


wire [16:0] minimum_body_length;

assign minimum_body_length =
    17'd15
    +
    {1'b0, ip_total_length};


wire [16:0] padding_candidate;

assign padding_candidate =
    frame_length_ext
    -
    minimum_body_length;


// ============================================================
// AFDX Ethernet-body structural limits
//
// Body after FCS removal:
//
//   14 bytes Ethernet header
// + ip_total_length
// + padding
// + 1 byte AFDX sequence
//
// Therefore:
//
// Minimum body:
//   14 + IP + 0  + 1
// = IP + 15
//
// Maximum body:
//   14 + IP + 16 + 1
// = IP + 31
// ============================================================

wire [16:0] maximum_body_length;

assign maximum_body_length =
    17'd31
    +
    {1'b0, ip_total_length};


wire body_length_structure_ok;

assign body_length_structure_ok =

    (frame_length_latched >= 11'd60)

    &&

    (frame_length_latched <= 11'd1514)

    &&

    (frame_length_ext >= minimum_body_length)

    &&

    (frame_length_ext <= maximum_body_length);


// ============================================================
// Payload range
//
// Fixed IPv4 header profile:
//
// Ethernet Header = 14
// IPv4 Header     = 20
// UDP Header      = 8
//
// UDP Payload starts at body byte 42.
// ============================================================

wire [11:0] payload_end_exclusive;

assign payload_end_exclusive =
    12'd42
    +
    {1'b0, payload_length};


wire in_payload_region;

assign in_payload_region =
    (state == ST_RECV)
    &&
    ({1'b0, byte_index} >= 12'd42)
    &&
    ({1'b0, byte_index} < payload_end_exclusive)
    &&
    !frame_bad_latched;


// ============================================================
// Payload streaming interface
// ============================================================

assign payload_data =
    s_data;


assign payload_valid =
    s_valid
    &&
    in_payload_region;


assign payload_sof =
    payload_valid
    &&
    (payload_count == 11'd0);


assign payload_eof =
    payload_valid
    &&
    (payload_length != 11'd0)
    &&
    (
        payload_count
        ==
        payload_length - 11'd1
    );


// ============================================================
// Input backpressure
//
// Headers, padding and sequence are always consumed.
//
// During payload transmission, backpressure from the next
// stage propagates upstream to gmii_rx_adapter.
// ============================================================

assign s_ready =
    (state == ST_IDLE)
    ?
        1'b1
    :
    (
        in_payload_region
        ?
            payload_ready
        :
            1'b1
    );


// ============================================================
// Main parser
// ============================================================

always @(posedge clk) begin

    if (rst) begin

        state <= ST_IDLE;

        byte_index <= 11'd0;

        frame_length_latched <= 11'd0;

        payload_count <= 11'd0;

        frame_bad_latched <= 1'b0;


        dst_mac <= 48'd0;
        src_mac <= 48'd0;
        ether_type <= 16'd0;


        ip_total_length <= 16'd0;
        ip_ttl <= 8'd0;
        ip_protocol <= 8'd0;
        ip_header_checksum <= 16'd0;

        src_ip <= 32'd0;
        dst_ip <= 32'd0;


        udp_src_port <= 16'd0;
        udp_dst_port <= 16'd0;
        udp_length <= 16'd0;
        udp_checksum <= 16'd0;

        payload_length <= 11'd0;
        padding_length <= 5'd0;

        afdx_sequence <= 8'd0;


        ip_sum <= 32'd0;
        ip_word_high <= 8'd0;
        udp_sum <= 32'd0;
        udp_word_high <= 8'd0;
        udp_word_high_valid <= 1'b0;


        meta_valid <= 1'b0;

        frame_done <= 1'b0;
        frame_valid <= 1'b0;


        ether_type_error <= 1'b0;
        ip_version_error <= 1'b0;
        ip_ihl_error <= 1'b0;
        ip_checksum_error <= 1'b0;
        ip_protocol_error <= 1'b0;
        ip_length_error <= 1'b0;
        udp_length_error <= 1'b0;
        udp_checksum_error <= 1'b0;
        structure_error <= 1'b0;

    end
    else begin

        // ====================================================
        // Pulse outputs default low
        // ====================================================

        meta_valid <= 1'b0;

        frame_done <= 1'b0;
        frame_valid <= 1'b0;


        ether_type_error <= 1'b0;
        ip_version_error <= 1'b0;
        ip_ihl_error <= 1'b0;
        ip_checksum_error <= 1'b0;
        ip_protocol_error <= 1'b0;
        ip_length_error <= 1'b0;
        udp_length_error <= 1'b0;
        udp_checksum_error <= 1'b0;
        structure_error <= 1'b0;


        // ====================================================
        // IDLE
        //
        // First accepted byte must also carry SOF.
        // ====================================================

        if (state == ST_IDLE) begin

            if (s_valid && s_ready) begin

                if (!s_sof) begin

                    structure_error <= 1'b1;

                end
                else begin

                    // ----------------------------------------
                    // Start new frame
                    // ----------------------------------------

                    state <= ST_RECV;

                    byte_index <= 11'd1;

                    frame_length_latched <=
                        s_frame_length;

                    payload_count <= 11'd0;

                    frame_bad_latched <= 1'b0;


                    // Clear metadata for new transaction.

                    dst_mac <= 48'd0;
                    src_mac <= 48'd0;
                    ether_type <= 16'd0;


                    ip_total_length <= 16'd0;
                    ip_ttl <= 8'd0;
                    ip_protocol <= 8'd0;
                    ip_header_checksum <= 16'd0;

                    src_ip <= 32'd0;
                    dst_ip <= 32'd0;


                    udp_src_port <= 16'd0;
                    udp_dst_port <= 16'd0;
                    udp_length <= 16'd0;
                    udp_checksum <= 16'd0;

                    payload_length <= 11'd0;
                    padding_length <= 5'd0;


                    afdx_sequence <= 8'd0;


                    ip_sum <= 32'd0;
                    ip_word_high <= 8'd0;
                    udp_sum <= 32'd0;
                    udp_word_high <= 8'd0;
                    udp_word_high_valid <= 1'b0;


                    // Body byte 0:
                    // Destination MAC [47:40]

                    dst_mac[47:40] <= s_data;


                    // A one-byte Ethernet frame is impossible.

                    if (s_eof) begin

                        structure_error <= 1'b1;

                        frame_done <= 1'b1;

                        state <= ST_IDLE;

                    end

                end

            end

        end


        // ====================================================
        // RECEIVE
        // ====================================================

        else begin

            if (s_valid && s_ready) begin

                // Unexpected SOF in middle of frame.

                if (s_sof) begin

                    structure_error <= 1'b1;
                    frame_bad_latched <= 1'b1;

                end


                // =================================================
                // IPv4 checksum accumulation
                //
                // Bytes 14..33.
                // =================================================

                if (
                    (byte_index >= 11'd14)
                    &&
                    (byte_index <= 11'd33)
                ) begin

                    if (byte_index[0] == 1'b0) begin

                        ip_word_high <= s_data;

                    end
                    else begin

                        ip_sum <=
                            ip_sum_with_current_word;


                        if (byte_index == 11'd33) begin

                            if (
                                ip_sum_folded
                                !=
                                16'hFFFF
                            ) begin

                                ip_checksum_error <= 1'b1;

                                frame_bad_latched <= 1'b1;

                            end

                        end

                    end

                end


                // =================================================
                // Field parsing
                // =================================================

                case (byte_index)


                    // =============================================
                    // Destination MAC
                    // =============================================

                    11'd1:
                        dst_mac[39:32] <= s_data;

                    11'd2:
                        dst_mac[31:24] <= s_data;

                    11'd3:
                        dst_mac[23:16] <= s_data;

                    11'd4:
                        dst_mac[15:8] <= s_data;

                    11'd5:
                        dst_mac[7:0] <= s_data;


                    // =============================================
                    // Source MAC
                    // =============================================

                    11'd6:
                        src_mac[47:40] <= s_data;

                    11'd7:
                        src_mac[39:32] <= s_data;

                    11'd8:
                        src_mac[31:24] <= s_data;

                    11'd9:
                        src_mac[23:16] <= s_data;

                    11'd10:
                        src_mac[15:8] <= s_data;

                    11'd11:
                        src_mac[7:0] <= s_data;


                    // =============================================
                    // EtherType
                    // =============================================

                    11'd12:
                        ether_type[15:8] <= s_data;

                    11'd13: begin

                        ether_type[7:0] <= s_data;

                        if (
                            {
                                ether_type[15:8],
                                s_data
                            }
                            !=
                            16'h0800
                        ) begin

                            ether_type_error <= 1'b1;

                            frame_bad_latched <= 1'b1;

                        end

                    end


                    // =============================================
                    // IPv4 Version / IHL
                    // =============================================

                    11'd14: begin

                        if (s_data[7:4] != 4'd4) begin

                            ip_version_error <= 1'b1;

                            frame_bad_latched <= 1'b1;

                        end


                        if (s_data[3:0] != 4'd5) begin

                            ip_ihl_error <= 1'b1;

                            frame_bad_latched <= 1'b1;

                        end

                    end


                    // =============================================
                    // IPv4 Total Length
                    // =============================================

                    11'd16:
                        ip_total_length[15:8] <= s_data;

                    11'd17:
                        ip_total_length[7:0] <= s_data;

                    // Unfragmented IPv4 profile. A nonzero fragment offset or
                    // MF/reserved flag must never be interpreted as a UDP header.
                    // DF alone is allowed; reassembly is not implemented.
                    11'd20: if ((s_data & 8'hBF) != 0) begin
                        structure_error <= 1'b1;
                        frame_bad_latched <= 1'b1;
                    end
                    11'd21: if (s_data != 0) begin
                        structure_error <= 1'b1;
                        frame_bad_latched <= 1'b1;
                    end



                    // =============================================
                    // TTL
                    // =============================================

                    11'd22:
                        ip_ttl <= s_data;


                    // =============================================
                    // Protocol
                    // =============================================

                    11'd23: begin

                        ip_protocol <= s_data;

                        if (s_data != 8'h11) begin

                            ip_protocol_error <= 1'b1;

                            frame_bad_latched <= 1'b1;

                        end

                    end


                    // =============================================
                    // IPv4 header checksum field
                    // =============================================

                    11'd24:
                        ip_header_checksum[15:8]
                            <= s_data;

                    11'd25:
                        ip_header_checksum[7:0]
                            <= s_data;


                    // =============================================
                    // Source IP
                    // =============================================

                    11'd26:
                        src_ip[31:24] <= s_data;

                    11'd27:
                        src_ip[23:16] <= s_data;

                    11'd28:
                        src_ip[15:8] <= s_data;

                    11'd29:
                        src_ip[7:0] <= s_data;


                    // =============================================
                    // Destination IP
                    // =============================================

                    11'd30:
                        dst_ip[31:24] <= s_data;

                    11'd31:
                        dst_ip[23:16] <= s_data;

                    11'd32:
                        dst_ip[15:8] <= s_data;

                    11'd33:
                        dst_ip[7:0] <= s_data;


                    // =============================================
                    // UDP Source Port
                    // =============================================

                    11'd34:
                        udp_src_port[15:8] <= s_data;

                    11'd35:
                        udp_src_port[7:0] <= s_data;


                    // =============================================
                    // UDP Destination Port
                    // =============================================

                    11'd36:
                        udp_dst_port[15:8] <= s_data;

                    11'd37:
                        udp_dst_port[7:0] <= s_data;


                    // =============================================
                    // UDP Length
                    // =============================================

                    11'd38:
                        udp_length[15:8] <= s_data;

                    11'd39: begin

                        udp_length[7:0] <= s_data;

                        // Start the pseudo-header + UDP-header checksum sum.
                        udp_sum <= udp_initial_sum;
                        udp_word_high_valid <= 1'b0;


                        // -----------------------------------------
                        // AFDX application payload:
                        //
                        // 1 .. 1471 bytes
                        //
                        // UDP length:
                        //
                        // 8 + payload
                        //
                        // Therefore:
                        //
                        // 9 .. 1479 bytes
                        // -----------------------------------------

                        if (
                            (udp_length_candidate < 16'd9)
                            ||
                            (
                                udp_length_candidate
                                >
                                (MAX_PAYLOAD_BYTES + 8)
                            )
                        ) begin

                            udp_length_error <= 1'b1;

                            frame_bad_latched <= 1'b1;

                            payload_length <= 11'd0;

                        end
                        else begin

                            payload_length <=
                                udp_length_candidate
                                -
                                16'd8;

                        end


                        // -----------------------------------------
                        // Fixed IHL=5 profile:
                        //
                        // IP total length must equal:
                        //
                        // 20-byte IP header
                        // +
                        // complete UDP datagram
                        // -----------------------------------------

                        if (
                            {
                                1'b0,
                                ip_total_length
                            }
                            !=
                            (
                                17'd20
                                +
                                {
                                    1'b0,
                                    udp_length_candidate
                                }
                            )
                        ) begin

                            ip_length_error <= 1'b1;

                            frame_bad_latched <= 1'b1;

                        end


                        // -----------------------------------------
                        // Ethernet-body / padding consistency
                        //
                        // Valid padding range:
                        // 0 .. 16 bytes
                        // -----------------------------------------

                        if (!body_length_structure_ok) begin

                            structure_error <= 1'b1;

                            frame_bad_latched <= 1'b1;

                        end
                        else begin

                            padding_length <=
                                padding_candidate[4:0];

                        end

                    end


                    // =============================================
                    // UDP Checksum
                    //
                    // Current TX profile uses 0000.
                    // Non-zero checksums are verified over the pseudo-header,
                    // UDP header and payload; odd payloads are zero-extended.
                    // =============================================

                    11'd40: begin
                        udp_checksum[15:8] <= s_data;
                        udp_word_high <= s_data;
                        udp_word_high_valid <= 1'b1;
                    end

                    11'd41: begin
                        udp_checksum[7:0] <= s_data;
                        udp_sum <= udp_sum + {16'd0, udp_word_high, s_data};
                        udp_word_high_valid <= 1'b0;


                        // At this point all Ethernet/IP/UDP
                        // metadata required before payload is
                        // available.

                        if (!frame_bad_latched)
                            meta_valid <= 1'b1;

                    end


                    default:
                        ;

                endcase


                // =================================================
                // Payload transfer accounting
                // =================================================

                if (in_payload_region) begin

                    payload_count <=
                        payload_count + 11'd1;

                    if (!udp_word_high_valid) begin
                        udp_word_high <= s_data;
                        udp_word_high_valid <= 1'b1;
                    end else begin
                        udp_sum <= udp_sum + {16'd0, udp_word_high, s_data};
                        udp_word_high_valid <= 1'b0;
                    end

                end


                // =================================================
                // End of validated Ethernet body
                //
                // Last byte is raw AFDX Sequence.
                // =================================================

                if (s_eof) begin

                    frame_done <= 1'b1;

                    afdx_sequence <= s_data;


                    // ---------------------------------------------
                    // Final stream consistency checks
                    // ---------------------------------------------

                    if (
                        !body_length_structure_ok
                        ||
                        (
                            byte_index
                            !=
                            frame_length_latched - 11'd1
                        )
                        ||
                        (
                            payload_count
                            !=
                            payload_length
                        )
                    ) begin

                        // Do not generate a second structure-error pulse
                        // if the same structural problem was already
                        // detected earlier in this frame.

                        if (!frame_bad_latched)
                            structure_error <= 1'b1;

                        frame_bad_latched <= 1'b1;

                    end


                    // A non-zero UDP checksum is mandatory to validate.
                    // Checksum zero retains the standard UDP disabled mode.
                    if (!frame_bad_latched && udp_checksum_bad) begin
                        udp_checksum_error <= 1'b1;
                        if (!frame_bad_latched)
                            structure_error <= 1'b1;
                        frame_bad_latched <= 1'b1;
                    end

                    
                    //
                    // Note:
                    // VL and sequence-integrity checks happen
                    // later in M3-C / M3-D.
                    // ---------------------------------------------

                    if (
                        !frame_bad_latched

                        && !udp_checksum_bad

                        &&

                        body_length_structure_ok

                        &&

                        (
                            byte_index
                            ==
                            frame_length_latched - 11'd1
                        )

                        &&

                        (
                            payload_count
                            ==
                            payload_length
                        )
                    ) begin

                        frame_valid <= 1'b1;

                    end


                    state <= ST_IDLE;

                    byte_index <= 11'd0;

                end
                else begin

                    byte_index <=
                        byte_index + 11'd1;

                end

            end

        end

    end

end


endmodule
