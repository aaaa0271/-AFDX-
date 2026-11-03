module afdx_frame_builder (
// LEGACY (M4 TX path): not instantiated by AFDX_competition_top or the
// competition AFDX_top; retained only for legacy ModelSim regression
// coverage. Do not use for new work.
    input  wire       clk,
    input  wire       rst,

    // Start one frame.
    input  wire       start,

    // Sequence number for this frame.
    input  wire [7:0] seq_num,

    // Internal byte-stream interface.
    output reg  [7:0] tx_data,
    output reg        tx_valid,
    input  wire       tx_ready,

    output reg        busy,
    output reg        done
);

reg [7:0] byte_index;
reg [7:0] seq_latched;


// ----------------------------------------------------
// Frame byte generation
//
// Byte  0 ~ 13 : Ethernet header
// Byte 14 ~ 33 : IPv4 header
// Byte 34 ~ 41 : UDP header
// Byte 42 ~ 45 : Payload
// Byte 46 ~ 58 : Padding
// Byte 59      : AFDX sequence number
// ----------------------------------------------------

always @(*) begin

    case (byte_index)

        // ==================================================
        // Ethernet Header
        // ==================================================

        // Destination MAC = 02:00:00:00:00:02
        8'd0:  tx_data = 8'h02;
        8'd1:  tx_data = 8'h00;
        8'd2:  tx_data = 8'h00;
        8'd3:  tx_data = 8'h00;
        8'd4:  tx_data = 8'h00;
        8'd5:  tx_data = 8'h02;

        // Source MAC = 02:00:00:00:00:01
        8'd6:  tx_data = 8'h02;
        8'd7:  tx_data = 8'h00;
        8'd8:  tx_data = 8'h00;
        8'd9:  tx_data = 8'h00;
        8'd10: tx_data = 8'h00;
        8'd11: tx_data = 8'h01;

        // EtherType = IPv4 = 0x0800
        8'd12: tx_data = 8'h08;
        8'd13: tx_data = 8'h00;


        // ==================================================
        // IPv4 Header
        // ==================================================

        // Version = 4, IHL = 5
        8'd14: tx_data = 8'h45;

        // DSCP / ECN
        8'd15: tx_data = 8'h00;

        // Total Length = 32 bytes
        // 20 IP + 8 UDP + 4 Payload
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

        // IPv4 header checksum = 0x66CB
        // Valid for THIS fixed header configuration.
        8'd24: tx_data = 8'h66;
        8'd25: tx_data = 8'hCB;

        // Source IP = 10.0.0.1
        8'd26: tx_data = 8'h0A;
        8'd27: tx_data = 8'h00;
        8'd28: tx_data = 8'h00;
        8'd29: tx_data = 8'h01;

        // Destination IP = 10.0.0.2
        8'd30: tx_data = 8'h0A;
        8'd31: tx_data = 8'h00;
        8'd32: tx_data = 8'h00;
        8'd33: tx_data = 8'h02;


        // ==================================================
        // UDP Header
        // ==================================================

        // Source Port = 10000 = 0x2710
        8'd34: tx_data = 8'h27;
        8'd35: tx_data = 8'h10;

        // Destination Port = 10001 = 0x2711
        8'd36: tx_data = 8'h27;
        8'd37: tx_data = 8'h11;

        // UDP Length = 8 + 4 = 12 = 0x000C
        8'd38: tx_data = 8'h00;
        8'd39: tx_data = 8'h0C;

        // UDP checksum:
        // temporarily zero in this fixed M2 test frame.
        8'd40: tx_data = 8'h00;
        8'd41: tx_data = 8'h00;


        // ==================================================
        // Payload = DE AD BE EF
        // ==================================================

        8'd42: tx_data = 8'hDE;
        8'd43: tx_data = 8'hAD;
        8'd44: tx_data = 8'hBE;
        8'd45: tx_data = 8'hEF;


        // ==================================================
        // Padding
        //
        // Byte 46 ~ 58 are automatically 00 by default.
        // ==================================================


        // ==================================================
        // AFDX Sequence Number
        // ==================================================

        8'd59: tx_data = seq_latched;


        // Padding and unused indexes
        default:
            tx_data = 8'h00;

    endcase

end


// ----------------------------------------------------
// Frame transmission control
// ----------------------------------------------------

always @(posedge clk) begin

    if (rst) begin

        byte_index  <= 8'd0;
        seq_latched <= 8'd0;

        tx_valid    <= 1'b0;
        busy        <= 1'b0;
        done        <= 1'b0;

    end
    else begin

        // done is a one-cycle pulse
        done <= 1'b0;


        // ----------------------------------------------
        // Start a new frame
        // ----------------------------------------------

        if (!busy && start) begin

            byte_index  <= 8'd0;
            seq_latched <= seq_num;

            busy        <= 1'b1;
            tx_valid    <= 1'b1;

        end


        // ----------------------------------------------
        // A byte transfers ONLY when:
        //
        // tx_valid == 1
        // tx_ready == 1
        //
        // ----------------------------------------------

        else if (busy && tx_valid && tx_ready) begin

            // Last byte transferred
            if (byte_index == 8'd59) begin

                byte_index <= 8'd0;

                busy       <= 1'b0;
                tx_valid   <= 1'b0;
                done       <= 1'b1;

            end
            else begin

                byte_index <= byte_index + 1'b1;

            end

        end

    end

end

endmodule
