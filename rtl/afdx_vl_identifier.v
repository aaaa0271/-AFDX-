// ============================================================
// afdx_vl_identifier.v
//
// M3-C : Virtual Link Identification + Whitelist
//
// Consumes validated Ethernet/IPv4/UDP metadata from M3-B
// (afdx_eth_ipv4_udp_parser) and resolves it to a configured
// Virtual Link (VL).
//
// This stage performs NO protocol parsing and NO integrity
// checking. Ethernet CRC, IPv4 checksum, UDP length and
// payload parsing are all owned by earlier stages (M3-A/M3-B).
//
// Responsibilities:
//   1. Resolve destination MAC into a VL (lookup).
//   2. Validate the full L2/L3/L4 tuple against that VL's
//      whitelist (source/dest IP, UDP ports, payload length).
//   3. Emit vl_index / vl_id / vl_lmax for downstream
//      sequence-integrity checking (M3-D).
//   4. Reject any frame that is not an authorized VL, and
//      distinguish "unknown VL" from "configured but disabled
//      VL".
//
// The AFDX VL identifier is the low 16 bits of the
// destination MAC, therefore dst_mac[15:0] is the lookup key.
//
// The lookup is combinational; the result is latched on the
// meta_valid pulse emitted by M3-B after the UDP header has
// been parsed (at which point every metadata field is stable).
//
// ============================================================

module afdx_vl_identifier #(parameter integer CONFIGURABLE=0) (
    input wire [671:0] cfg_table,
    input  wire        clk,
    input  wire        rst,

    // ========================================================
    // Metadata from M3-B
    // ========================================================

    input  wire        meta_valid,

    input  wire [47:0] dst_mac,

    input  wire [31:0] src_ip,
    input  wire [31:0] dst_ip,

    input  wire [15:0] udp_src_port,
    input  wire [15:0] udp_dst_port,

    input  wire [10:0] payload_length,


    // ========================================================
    // VL result
    // ========================================================

    output reg         result_valid,

    output reg         vl_accept,
    output reg         vl_reject,

    output reg  [1:0]  vl_index,
    output reg  [15:0] vl_id,
    output reg  [10:0] vl_lmax,


    // ========================================================
    // Reject reason (single-cycle pulses)
    // ========================================================

    output reg         unknown_vl_error,
    output reg         disabled_vl_error,

    output reg         ip_whitelist_error,
    output reg         udp_whitelist_error,
    output reg         length_whitelist_error
);


// ============================================================
// Lookup result
// ============================================================

reg        lookup_hit;
reg        lookup_enable;

reg [1:0]  lookup_index;
reg [15:0] lookup_id;

reg [31:0] lookup_src_ip;
reg [31:0] lookup_dst_ip;

reg [15:0] lookup_udp_src;
reg [15:0] lookup_udp_dst;

reg [10:0] lookup_lmax;


// ============================================================
// VL configuration table
//
// VL0 / VL1 are enabled.
// VL2 / VL3 are configured but intentionally disabled so that
// the disabled-VL rejection path can be verified.
// ============================================================

generate if(CONFIGURABLE==0) begin : legacy_configuration
always @(*) begin

    // Default: lookup miss

    lookup_hit     = 1'b0;
    lookup_enable  = 1'b0;

    lookup_index   = 2'd0;
    lookup_id      = 16'd0;

    lookup_src_ip  = 32'd0;
    lookup_dst_ip  = 32'd0;

    lookup_udp_src = 16'd0;
    lookup_udp_dst = 16'd0;

    lookup_lmax    = 11'd0;


    case (dst_mac[15:0])

        // ----------------------------------------------------
        // VL0
        //
        // Dst MAC : 02:00:00:00:00:02
        // Src IP  : 10.0.0.1
        // Dst IP  : 10.0.0.2
        // UDP     : 10000 -> 10001
        // LMAX    : 512 bytes
        // ----------------------------------------------------

        16'h0002: begin

            lookup_hit     = 1'b1;
            lookup_enable  = 1'b1;

            lookup_index   = 2'd0;
            lookup_id      = 16'h0002;

            lookup_src_ip  = 32'h0A000001;
            lookup_dst_ip  = 32'h0A000002;

            lookup_udp_src = 16'd10000;
            lookup_udp_dst = 16'd10001;

            lookup_lmax    = 11'd512;

        end


        // ----------------------------------------------------
        // VL1
        //
        // Dst MAC : 02:00:00:00:00:03
        // Src IP  : 10.0.0.1
        // Dst IP  : 10.0.0.3
        // UDP     : 10000 -> 20001
        // LMAX    : 256 bytes
        // ----------------------------------------------------

        16'h0003: begin

            lookup_hit     = 1'b1;
            lookup_enable  = 1'b1;

            lookup_index   = 2'd1;
            lookup_id      = 16'h0003;

            lookup_src_ip  = 32'h0A000001;
            lookup_dst_ip  = 32'h0A000003;

            lookup_udp_src = 16'd10000;
            lookup_udp_dst = 16'd20001;

            lookup_lmax    = 11'd256;

        end


        // ----------------------------------------------------
        // VL2 - configured but disabled
        // ----------------------------------------------------

        16'h0004: begin

            lookup_hit     = 1'b1;
            lookup_enable  = 1'b0;

            lookup_index   = 2'd2;
            lookup_id      = 16'h0004;

            lookup_src_ip  = 32'h0A000001;
            lookup_dst_ip  = 32'h0A000004;

            lookup_udp_src = 16'd10000;
            lookup_udp_dst = 16'd30001;

            lookup_lmax    = 11'd128;

        end


        // ----------------------------------------------------
        // VL3 - configured but disabled
        // ----------------------------------------------------

        16'h0005: begin

            lookup_hit     = 1'b1;
            lookup_enable  = 1'b0;

            lookup_index   = 2'd3;
            lookup_id      = 16'h0005;

            lookup_src_ip  = 32'h0A000001;
            lookup_dst_ip  = 32'h0A000005;

            lookup_udp_src = 16'd10000;
            lookup_udp_dst = 16'd40001;

            lookup_lmax    = 11'd128;

        end


        default: begin

            lookup_hit     = 1'b0;
            lookup_enable  = 1'b0;

        end

    endcase

end


end else begin : programmable_configuration
 integer n;
 reg [15:0] max_frame;
 always @* begin
  lookup_hit=0;lookup_enable=0;lookup_index=0;lookup_id=0;
  lookup_src_ip=0;lookup_dst_ip=0;lookup_udp_src=0;lookup_udp_dst=0;lookup_lmax=0;max_frame=0;
  for(n=0;n<4;n=n+1)begin
   if(!lookup_hit && cfg_table[n*168] && cfg_table[n*168+8+:48]==dst_mac)begin
    lookup_hit=1;lookup_enable=cfg_table[n*168+1];lookup_index=n[1:0];lookup_id=dst_mac[15:0];
    lookup_src_ip=cfg_table[n*168+56+:32];lookup_dst_ip=cfg_table[n*168+88+:32];
    lookup_udp_src=cfg_table[n*168+120+:16];lookup_udp_dst=cfg_table[n*168+136+:16];
    max_frame=cfg_table[n*168+152+:16];
    if(max_frame>=64 && max_frame<=1518)lookup_lmax=max_frame-16'd47;
    else lookup_enable=0;
   end
  end
 end
end endgenerate

// ============================================================
// Decision logic
//
// Priority:
//   1. Unknown VL
//   2. Configured but disabled VL
//   3. IP whitelist
//   4. UDP whitelist
//   5. LMAX
//   6. Accept
//
// All result/error outputs are single-cycle pulses associated
// with the meta_valid pulse.
// ============================================================

always @(posedge clk) begin

    if (rst) begin

        result_valid <= 1'b0;

        vl_accept <= 1'b0;
        vl_reject <= 1'b0;

        vl_index <= 2'd0;
        vl_id    <= 16'd0;
        vl_lmax  <= 11'd0;

        unknown_vl_error       <= 1'b0;
        disabled_vl_error      <= 1'b0;

        ip_whitelist_error     <= 1'b0;
        udp_whitelist_error    <= 1'b0;
        length_whitelist_error <= 1'b0;

    end
    else begin

        // ----------------------------------------------------
        // Default: deassert all single-cycle outputs
        // ----------------------------------------------------

        result_valid <= 1'b0;

        vl_accept <= 1'b0;
        vl_reject <= 1'b0;

        unknown_vl_error       <= 1'b0;
        disabled_vl_error      <= 1'b0;

        ip_whitelist_error     <= 1'b0;
        udp_whitelist_error    <= 1'b0;
        length_whitelist_error <= 1'b0;


        // ----------------------------------------------------
        // One metadata transaction
        // ----------------------------------------------------

        if (meta_valid) begin

            result_valid <= 1'b1;

            vl_index <= lookup_index;
            vl_id    <= lookup_id;
            vl_lmax  <= lookup_lmax;


            // =================================================
            // 1. Unknown VL
            // =================================================

            if (!lookup_hit) begin

                vl_reject <= 1'b1;

                unknown_vl_error <= 1'b1;

            end


            // =================================================
            // 2. Configured but disabled VL
            // =================================================

            else if (!lookup_enable) begin

                vl_reject <= 1'b1;

                disabled_vl_error <= 1'b1;

            end


            // =================================================
            // 3. IP whitelist
            // =================================================

            else if ((src_ip != lookup_src_ip) ||
                     (dst_ip != lookup_dst_ip)) begin

                vl_reject <= 1'b1;

                ip_whitelist_error <= 1'b1;

            end


            // =================================================
            // 4. UDP whitelist
            // =================================================

            else if ((udp_src_port != lookup_udp_src) ||
                     (udp_dst_port != lookup_udp_dst)) begin

                vl_reject <= 1'b1;

                udp_whitelist_error <= 1'b1;

            end


            // =================================================
            // 5. Payload length / LMAX
            // =================================================

            else if (payload_length > lookup_lmax) begin

                vl_reject <= 1'b1;

                length_whitelist_error <= 1'b1;

            end


            // =================================================
            // 6. Valid VL
            // =================================================

            else begin

                vl_accept <= 1'b1;

            end

        end

    end

end


endmodule
