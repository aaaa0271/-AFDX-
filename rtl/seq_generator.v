module seq_generator (
// LEGACY (M4 TX path): not instantiated by AFDX_competition_top or the
// competition AFDX_top; retained only for legacy ModelSim regression
// coverage. Do not use for new work.
    input  wire       clk,
    input  wire       rst,

    input  wire       advance,

    output reg  [7:0] seq_num
);

always @(posedge clk) begin

    if (rst) begin

        seq_num <= 8'h00;

    end
    else if (advance) begin

        if (seq_num == 8'hFF)
            seq_num <= 8'h01;
        else
            seq_num <= seq_num + 1'b1;

    end

end

endmodule
