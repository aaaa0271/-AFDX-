module gmii_tx_adapter_60 (
    input  wire       clk,
    input  wire       rst,

    // Input: 60-byte Ethernet frame body
    // The source must provide continuous valid bytes
    // once body transmission begins.

    input  wire [7:0] s_data,
    input  wire       s_valid,
    output wire       s_ready,

    // GMII output
    output reg  [7:0] gmii_txd,
    output reg        gmii_tx_en,
    output reg        gmii_tx_er,

    // Status
    output reg        frame_done,
    output reg        underrun
);

// ====================================================
// State definitions
// ====================================================

localparam [2:0]
    ST_IDLE     = 3'd0,
    ST_PREAMBLE = 3'd1,
    ST_BODY     = 3'd2,
    ST_FCS      = 3'd3,
    ST_IFG      = 3'd4,
    ST_ERROR    = 3'd5;

reg [2:0] state;

// Counters
reg [2:0] pre_count;
reg [5:0] body_count;
reg [1:0] fcs_count;
reg [3:0] ifg_count;

// Ethernet CRC32
reg [31:0] crc_reg;
reg [31:0] fcs_reg;


// ====================================================
// CRC32 calculation
//
// Reflected polynomial: ED B8 83 20
// Initial value: FFFFFFFF
// Final XOR: FFFFFFFF
//
// Input bytes are processed LSB first.
// ====================================================

function [31:0] crc32_byte;

    input [31:0] crc_in;
    input [7:0]  data_in;

    reg [31:0] crc_tmp;
    integer i;

    begin

        crc_tmp = crc_in ^ {24'd0, data_in};

        for (i = 0; i < 8; i = i + 1) begin

            if (crc_tmp[0])
                crc_tmp =
                    (crc_tmp >> 1) ^ 32'hEDB88320;
            else
                crc_tmp = crc_tmp >> 1;

        end

        crc32_byte = crc_tmp;

    end

endfunction


wire [31:0] crc_next;

assign crc_next = crc32_byte(crc_reg, s_data);


// ====================================================
// Input handshake
//
// The source is allowed to advance only during
// the frame body transmission.
// ====================================================

assign s_ready = (state == ST_BODY);


// ====================================================
// Main state machine
// ====================================================

always @(posedge clk) begin

    if (rst) begin

        state <= ST_IDLE;

        pre_count  <= 3'd0;
        body_count <= 6'd0;
        fcs_count  <= 2'd0;
        ifg_count  <= 4'd0;

        crc_reg <= 32'hFFFFFFFF;
        fcs_reg <= 32'd0;

        gmii_txd   <= 8'h00;
        gmii_tx_en <= 1'b0;
        gmii_tx_er <= 1'b0;

        frame_done <= 1'b0;
        underrun   <= 1'b0;

    end
    else begin

        // Default outputs
        gmii_txd   <= 8'h00;
        gmii_tx_en <= 1'b0;
        gmii_tx_er <= 1'b0;

        frame_done <= 1'b0;

        case (state)

            // ========================================
            // IDLE
            // ========================================

            ST_IDLE: begin

                if (s_valid) begin

                    crc_reg <= 32'hFFFFFFFF;

                    pre_count <= 3'd1;

                    // First preamble byte
                    gmii_txd   <= 8'h55;
                    gmii_tx_en <= 1'b1;

                    state <= ST_PREAMBLE;

                end

            end


            // ========================================
            // PREAMBLE + SFD
            //
            // 7 x 55
            // 1 x D5
            // ========================================

            ST_PREAMBLE: begin

                gmii_tx_en <= 1'b1;

                if (pre_count < 3'd7) begin

                    gmii_txd <= 8'h55;

                    pre_count <= pre_count + 1'b1;

                end
                else begin

                    gmii_txd <= 8'hD5;

                    body_count <= 6'd0;

                    state <= ST_BODY;

                end

            end


            // ========================================
            // FRAME BODY
            //
            // Exactly 60 bytes
            // ========================================

            ST_BODY: begin

                if (s_valid) begin

                    gmii_txd   <= s_data;
                    gmii_tx_en <= 1'b1;

                    // Update CRC using current byte
                    crc_reg <= crc_next;

                    if (body_count == 6'd59) begin

                        // Include the final body byte
                        // before generating the FCS.

                        fcs_reg <= ~crc_next;

                        fcs_count <= 2'd0;

                        state <= ST_FCS;

                    end
                    else begin

                        body_count <= body_count + 1'b1;

                    end

                end
                else begin

                    // Input underrun.
                    // Mark the frame as invalid and
                    // stop until the module is reset.

                    gmii_txd   <= 8'h00;
                    gmii_tx_en <= 1'b1;
                    gmii_tx_er <= 1'b1;

                    underrun <= 1'b1;

                    state <= ST_ERROR;

                end

            end


            // ========================================
            // FCS
            //
            // Ethernet sends the least significant
            // FCS byte first.
            // ========================================

            ST_FCS: begin

                gmii_tx_en <= 1'b1;

                case (fcs_count)

                    2'd0:
                        gmii_txd <= fcs_reg[7:0];

                    2'd1:
                        gmii_txd <= fcs_reg[15:8];

                    2'd2:
                        gmii_txd <= fcs_reg[23:16];

                    2'd3:
                        gmii_txd <= fcs_reg[31:24];

                endcase

                if (fcs_count == 2'd3) begin

                    // Last FCS byte has been emitted
                    frame_done <= 1'b1;

                    ifg_count <= 4'd0;

                    state <= ST_IFG;

                end
                else begin

                    fcs_count <= fcs_count + 1'b1;

                end

            end


            // ========================================
            // INTERFRAME GAP
            //
            // 12 clocks with TX_EN = 0
            // ========================================

            ST_IFG: begin

                if (ifg_count == 4'd11) begin

                    state <= ST_IDLE;

                end
                else begin

                    ifg_count <= ifg_count + 1'b1;

                end

            end


            // ========================================
            // ERROR
            //
            // Requires reset to recover.
            // ========================================

            ST_ERROR: begin

                state <= ST_ERROR;

            end


            default: begin

                state <= ST_IDLE;

            end

        endcase

    end

end

endmodule
