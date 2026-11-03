`timescale 1ns/1ps
module tb_arithmetic;
    `include "tb_math.vh"
    reg clk=0;
    reg rst_n=0;
    reg signed [47:0] values [0:MATH_COUNT-1];
    reg [7:0] shifts [0:MATH_COUNT-1];
    reg signed [47:0] expected [0:MATH_COUNT-1];
    wire [31:0] tag;
    integer i;
    afdx_ai_tcn_plugin dut(.clk(clk),.rst_n(rst_n),.job_valid(1'b0),.job_ready(),
        .job_id(32'd0),.job_model_tag(32'd0),.job_feature_mask(18'd0),.job_flags(16'd0),
        .feature_valid(1'b0),.feature_ready(),.feature_data(16'd0),.feature_last(1'b0),
        .result_valid(),.result_ready(1'b0),.result_job_id(),.result_model_tag(tag),
        .result_logits(),.result_candidate_mask(),.result_status(),.result_saturation(),.result_compute_cycles());
    initial begin
        $readmemh("reports/vectors/math_values.mem",values);
        $readmemh("reports/vectors/math_shifts.mem",shifts);
        $readmemh("reports/vectors/math_expected.mem",expected);
        #1;
        for(i=0;i<MATH_COUNT;i=i+1)
            if (dut.round_shift(values[i],shifts[i]) !== expected[i])
                $fatal(1,"FAIL rounding case=%0d value=%0d shift=%0d",i,values[i],shifts[i]);
        if (dut.clip_signed(-48'sd32769) !== 16'h8000 || dut.clip_signed(48'sd32768) !== 16'h7fff ||
            dut.clip_relu(-48'sd1) !== 16'h0000 || dut.clip_relu(48'sd32768) !== 16'h7fff)
            $fatal(1,"FAIL clipping");
        $display("ARITHMETIC_ALL_PASS cases=%0d",MATH_COUNT);
        $finish;
    end
endmodule
