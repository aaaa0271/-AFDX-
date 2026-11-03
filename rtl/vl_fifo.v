`timescale 1ns / 1ps
// LEGACY (M4 TX path): not instantiated by AFDX_competition_top or the
// competition AFDX_top; retained only for legacy ModelSim regression
// coverage. Do not use for new work.


module vl_fifo #(
    parameter DATA_WIDTH = 8,
    parameter LEN_WIDTH  = 16,
    parameter DEPTH      = 4,
    parameter PTR_WIDTH  = 2
)(
    input  wire                  clk,
    input  wire                  rst_n,

    // Write side
    input  wire                  wr_en,
    input  wire [DATA_WIDTH-1:0] wr_data,
    input  wire [LEN_WIDTH-1:0]  wr_len,

    // Read side
    input  wire                  rd_en,

    output wire [DATA_WIDTH-1:0] rd_data,
    output wire [LEN_WIDTH-1:0]  rd_len,

    output wire                  empty,
    output wire                  full,
    output reg  [PTR_WIDTH:0]    count
);

    reg [DATA_WIDTH-1:0] data_mem [0:DEPTH-1];
    reg [LEN_WIDTH-1:0]  len_mem  [0:DEPTH-1];

    reg [PTR_WIDTH-1:0] wr_ptr;
    reg [PTR_WIDTH-1:0] rd_ptr;

    assign empty = (count == 0);
    assign full  = (count == DEPTH);

    assign rd_data = data_mem[rd_ptr];
    assign rd_len  = len_mem[rd_ptr];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= 0;
            rd_ptr <= 0;
            count  <= 0;
        end
        else begin

            case ({wr_en && !full, rd_en && !empty})

                2'b10: begin
                    data_mem[wr_ptr] <= wr_data;
                    len_mem[wr_ptr]  <= wr_len;
                    wr_ptr           <= wr_ptr + 1'b1;
                    count            <= count + 1'b1;
                end

                2'b01: begin
                    rd_ptr <= rd_ptr + 1'b1;
                    count  <= count - 1'b1;
                end

                2'b11: begin
                    data_mem[wr_ptr] <= wr_data;
                    len_mem[wr_ptr]  <= wr_len;

                    wr_ptr <= wr_ptr + 1'b1;
                    rd_ptr <= rd_ptr + 1'b1;

                    count <= count;
                end

                default: begin
                    count <= count;
                end

            endcase
        end
    end

endmodule
