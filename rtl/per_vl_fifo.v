`timescale 1ns / 1ps
// LEGACY (M4 TX path): not instantiated by AFDX_competition_top or the
// competition AFDX_top; retained only for legacy ModelSim regression
// coverage. Do not use for new work.


module per_vl_fifo (
    input  wire        clk,
    input  wire        rst_n,

    // Application write interface
    input  wire        wr_en,
    input  wire [1:0]  wr_vl_id,
    input  wire [7:0]  wr_data,
    input  wire [15:0] wr_len,

    // Scheduler read interface
    input  wire        rd_en,
    input  wire [1:0]  rd_vl_id,

    output reg  [7:0]  rd_data,
    output reg  [15:0] rd_len,

    output wire [3:0]  fifo_empty,
    output wire [3:0]  fifo_full,

    output wire [2:0]  fifo_count0,
    output wire [2:0]  fifo_count1,
    output wire [2:0]  fifo_count2,
    output wire [2:0]  fifo_count3
);

    wire wr0;
    wire wr1;
    wire wr2;
    wire wr3;

    wire rd0;
    wire rd1;
    wire rd2;
    wire rd3;

    wire [7:0]  data0;
    wire [7:0]  data1;
    wire [7:0]  data2;
    wire [7:0]  data3;

    wire [15:0] len0;
    wire [15:0] len1;
    wire [15:0] len2;
    wire [15:0] len3;

    assign wr0 = wr_en && (wr_vl_id == 2'd0);
    assign wr1 = wr_en && (wr_vl_id == 2'd1);
    assign wr2 = wr_en && (wr_vl_id == 2'd2);
    assign wr3 = wr_en && (wr_vl_id == 2'd3);

    assign rd0 = rd_en && (rd_vl_id == 2'd0);
    assign rd1 = rd_en && (rd_vl_id == 2'd1);
    assign rd2 = rd_en && (rd_vl_id == 2'd2);
    assign rd3 = rd_en && (rd_vl_id == 2'd3);

    vl_fifo fifo0 (
        .clk     (clk),
        .rst_n   (rst_n),
        .wr_en   (wr0),
        .wr_data (wr_data),
        .wr_len  (wr_len),
        .rd_en   (rd0),
        .rd_data (data0),
        .rd_len  (len0),
        .empty   (fifo_empty[0]),
        .full    (fifo_full[0]),
        .count   (fifo_count0)
    );

    vl_fifo fifo1 (
        .clk     (clk),
        .rst_n   (rst_n),
        .wr_en   (wr1),
        .wr_data (wr_data),
        .wr_len  (wr_len),
        .rd_en   (rd1),
        .rd_data (data1),
        .rd_len  (len1),
        .empty   (fifo_empty[1]),
        .full    (fifo_full[1]),
        .count   (fifo_count1)
    );

    vl_fifo fifo2 (
        .clk     (clk),
        .rst_n   (rst_n),
        .wr_en   (wr2),
        .wr_data (wr_data),
        .wr_len  (wr_len),
        .rd_en   (rd2),
        .rd_data (data2),
        .rd_len  (len2),
        .empty   (fifo_empty[2]),
        .full    (fifo_full[2]),
        .count   (fifo_count2)
    );

    vl_fifo fifo3 (
        .clk     (clk),
        .rst_n   (rst_n),
        .wr_en   (wr3),
        .wr_data (wr_data),
        .wr_len  (wr_len),
        .rd_en   (rd3),
        .rd_data (data3),
        .rd_len  (len3),
        .empty   (fifo_empty[3]),
        .full    (fifo_full[3]),
        .count   (fifo_count3)
    );

    always @(*) begin
        case (rd_vl_id)

            2'd0: begin
                rd_data = data0;
                rd_len  = len0;
            end

            2'd1: begin
                rd_data = data1;
                rd_len  = len1;
            end

            2'd2: begin
                rd_data = data2;
                rd_len  = len2;
            end

            2'd3: begin
                rd_data = data3;
                rd_len  = len3;
            end

            default: begin
                rd_data = 8'd0;
                rd_len  = 16'd0;
            end

        endcase
    end

endmodule
