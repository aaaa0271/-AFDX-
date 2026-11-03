`timescale 1ns/1ps
// Generic single-job harness: input.mem contains metadata then 144 int16 beats.
module tb_hw_infer;
    parameter WEIGHTS_FILE="rtl/weights.mem", BIASES_FILE="rtl/biases.mem",
              THRESHOLDS_FILE="rtl/thresholds.mem", SHIFTS_FILE="rtl/shifts.mem";
    `include "ai_model_params.vh"
    reg clk=0;
    always #40 clk=~clk;
    reg rst_n=0, job_valid=0, feature_valid=0, feature_last=0, result_ready=0;
    wire job_ready, feature_ready, result_valid;
    reg [31:0] mem [0:146];
    reg [15:0] data=0;
    wire [31:0] id, tag, cycles;
    wire [143:0] logits;
    wire [7:0] mask;
    wire [15:0] status;
    wire [2:0] saturation;
    integer i;
    afdx_ai_tcn_plugin #(.WEIGHTS_FILE(WEIGHTS_FILE),.BIASES_FILE(BIASES_FILE),
        .THRESHOLDS_FILE(THRESHOLDS_FILE),.SHIFTS_FILE(SHIFTS_FILE)) dut (
        .clk(clk),.rst_n(rst_n),.job_valid(job_valid),.job_ready(job_ready),
        .job_id(mem[0]),.job_model_tag(mem[1]),.job_feature_mask(18'h3ffff),.job_flags(mem[2][15:0]),
        .feature_valid(feature_valid),.feature_ready(feature_ready),.feature_data(data),.feature_last(feature_last),
        .result_valid(result_valid),.result_ready(result_ready),.result_job_id(id),.result_model_tag(tag),
        .result_logits(logits),.result_candidate_mask(mask),.result_status(status),
        .result_saturation(saturation),.result_compute_cycles(cycles)
    );
    initial begin
        $readmemh("input.mem",mem);
        repeat(3) @(negedge clk); rst_n=1;
        @(negedge clk); job_valid=1;
        @(negedge clk); job_valid=0;
        for(i=0;i<144;i=i+1) begin
            if (!feature_ready) $fatal(1,"FAIL feature not ready");
            data=mem[i+3][15:0]; feature_valid=1; feature_last=i==143;
            @(negedge clk);
        end
        feature_valid=0; feature_last=0;
        wait(result_valid); @(negedge clk);
        $write("RESULT %0d %08h %0d %0d %0d %0d",id,tag,status,saturation,cycles,mask);
        for(i=0;i<9;i=i+1) $write(" %0d",$signed(logits[i*16 +: 16]));
        $display("");
        $finish;
    end
    initial begin #2000000; $fatal(1,"FAIL watchdog"); end
endmodule
