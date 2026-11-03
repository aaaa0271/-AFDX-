`timescale 1ns/1ps
module tb_tcn_plugin;
    `include "ai_model_params.vh"
    `include "tb_vectors.vh"
    reg clk=0;
    always #40 clk=~clk;
    reg rst_n=0;
    reg job_valid=0;
    wire job_ready;
    reg [31:0] job_id=0;
    reg [31:0] job_model_tag=MODEL_TAG;
    reg [17:0] job_feature_mask=18'h3ffff;
    reg [15:0] job_flags=0;
    reg feature_valid=0;
    wire feature_ready;
    reg signed [15:0] feature_data=0;
    reg feature_last=0;
    wire result_valid;
    reg result_ready=0;
    wire [31:0] result_job_id;
    wire [31:0] result_model_tag;
    wire [143:0] result_logits;
    wire [7:0] result_candidate_mask;
    wire [15:0] result_status;
    wire [2:0] result_saturation;
    wire [31:0] result_compute_cycles;
    afdx_ai_tcn_plugin #(.INPUT_TIMEOUT_CYCLES(32)) dut (
        .clk(clk), .rst_n(rst_n), .job_valid(job_valid), .job_ready(job_ready),
        .job_id(job_id), .job_model_tag(job_model_tag), .job_feature_mask(job_feature_mask),
        .job_flags(job_flags), .feature_valid(feature_valid), .feature_ready(feature_ready),
        .feature_data(feature_data), .feature_last(feature_last), .result_valid(result_valid),
        .result_ready(result_ready), .result_job_id(result_job_id), .result_model_tag(result_model_tag),
        .result_logits(result_logits), .result_candidate_mask(result_candidate_mask),
        .result_status(result_status), .result_saturation(result_saturation),
        .result_compute_cycles(result_compute_cycles)
    );
    reg [15:0] inputs [0:VECTOR_COUNT*144-1];
    reg [15:0] expected_logits [0:VECTOR_COUNT*9-1];
    reg [15:0] flags [0:VECTOR_COUNT-1];
    reg [15:0] statuses [0:VECTOR_COUNT-1];
    reg [7:0] masks [0:VECTOR_COUNT-1];
    reg [7:0] saturations [0:VECTOR_COUNT-1];
    reg [15:0] expected_trace [0:VECTOR_COUNT*288-1];
    integer vector_index, i, j;
    integer protocol_cases=0;
    reg [143:0] held_logits;
    reg [7:0] held_mask;
    reg [15:0] held_status;
    reg [2:0] held_saturation;
    reg [31:0] held_cycles;
    reg previous_result_valid=0;
    time last_input_time;
    // Independent elapsed-time check, not based on the DUT's own cycle counter.
    always @(posedge clk) begin
        if (rst_n && feature_valid && feature_ready && feature_last) last_input_time=$time;
        #1;
        if (!rst_n) previous_result_valid=0;
        else begin
            if (result_valid && !previous_result_valid && result_compute_cycles!=0)
                if (($time-1-last_input_time) != 14035*80) $fatal(1,"FAIL external compute latency");
            previous_result_valid=result_valid;
        end
    end

    task reset_core;
        begin
            @(negedge clk); rst_n=0; job_valid=0; feature_valid=0; result_ready=0;
            repeat(3) @(negedge clk);
            rst_n=1;
            @(negedge clk);
            if (result_valid || !job_ready || feature_ready) $fatal(1,"FAIL reset interface");
        end
    endtask

    task command;
        input [31:0] id;
        input [31:0] tag;
        input [17:0] feature_mask;
        input [15:0] quality;
        begin
            @(negedge clk);
            if (!job_ready) $fatal(1,"FAIL command not ready");
            job_valid=1; job_id=id; job_model_tag=tag; job_feature_mask=feature_mask; job_flags=quality;
            @(negedge clk); job_valid=0;
        end
    endtask

    task beat;
        input [15:0] value;
        input last;
        begin
            @(negedge clk);
            if (!feature_ready) $fatal(1,"FAIL feature not ready");
            feature_valid=1; feature_data=value; feature_last=last;
            @(negedge clk); feature_valid=0; feature_last=0;
        end
    endtask

    task await_result;
        integer limit;
        begin
            limit=0;
            while (!result_valid && limit<15000) begin @(negedge clk); limit=limit+1; end
            if (!result_valid) $fatal(1,"FAIL result deadline");
        end
    endtask

    task consume;
        begin
            @(negedge clk); result_ready=1;
            @(negedge clk); result_ready=0;
            if (!job_ready || result_valid) $fatal(1,"FAIL consume handshake");
        end
    endtask

    task check_vector;
        input integer n;
        input [31:0] id;
        integer k;
        begin
            await_result;
            if (result_job_id !== id || result_model_tag !== MODEL_TAG ||
                result_status !== statuses[n] || result_candidate_mask !== masks[n] ||
                result_saturation !== saturations[n][2:0] || result_compute_cycles !== 32'd14035)
                $fatal(1,"FAIL metadata vector=%0d status=%h/%h mask=%h/%h sat=%h/%h cycles=%0d",n,
                    result_status,statuses[n],result_candidate_mask,masks[n],result_saturation,saturations[n],result_compute_cycles);
            for (k=0;k<9;k=k+1)
                if (result_logits[k*16 +: 16] !== expected_logits[n*9+k])
                    $fatal(1,"FAIL logit vector=%0d output=%0d got=%h want=%h",n,k,result_logits[k*16 +: 16],expected_logits[n*9+k]);
            for (k=0;k<128;k=k+1) begin
                if (dut.h1[k] !== expected_trace[n*288+k]) $fatal(1,"FAIL conv1 vector=%0d index=%0d got=%h want=%h",n,k,dut.h1[k],expected_trace[n*288+k]);
                if (dut.h2[k] !== expected_trace[n*288+128+k]) $fatal(1,"FAIL conv2 vector=%0d index=%0d",n,k);
            end
            for (k=0;k<32;k=k+1)
                if (dut.rep[k] !== expected_trace[n*288+256+k]) $fatal(1,"FAIL pool vector=%0d index=%0d",n,k);
        end
    endtask

    task check_error;
        input [31:0] id;
        input [15:0] error_code;
        begin
            await_result;
            if (result_job_id !== id || result_status !== error_code || result_candidate_mask !== 0 ||
                result_compute_cycles !== 0 || result_logits !== 0)
                $fatal(1,"FAIL protocol id=%0d status=%h expected=%h",id,result_status,error_code);
            consume;
            protocol_cases=protocol_cases+1;
        end
    endtask

    initial begin
        $readmemh("reports/vectors/inputs.mem", inputs);
        $readmemh("reports/vectors/logits.mem", expected_logits);
        $readmemh("reports/vectors/flags.mem", flags);
        $readmemh("reports/vectors/status.mem", statuses);
        $readmemh("reports/vectors/mask.mem", masks);
        $readmemh("reports/vectors/saturation.mem", saturations);
        $readmemh("reports/vectors/trace.mem", expected_trace);
        reset_core;
        for (vector_index=0;vector_index<VECTOR_COUNT;vector_index=vector_index+1) begin
            command(vector_index, MODEL_TAG, 18'h3ffff, flags[vector_index]);
            for (i=0;i<144;i=i+1) begin
                if (vector_index%5 == 0) repeat ((i*7+vector_index)%4) @(negedge clk);
                beat(inputs[vector_index*144+i], i==143);
            end
            // An unaccepted command and feature beat during compute must have no effect.
            job_valid=1; job_id=32'hdeadbeef; feature_valid=1; feature_data=16'h1234;
            repeat(3) begin
                @(negedge clk);
                if (job_ready || feature_ready) $fatal(1,"FAIL compute isolation");
            end
            job_valid=0; feature_valid=0;
            check_vector(vector_index, vector_index);
            held_logits=result_logits; held_mask=result_candidate_mask; held_status=result_status;
            held_saturation=result_saturation; held_cycles=result_compute_cycles;
            repeat(2+vector_index%7) begin
                @(negedge clk);
                if (!result_valid || job_ready || feature_ready || result_logits !== held_logits ||
                    result_candidate_mask !== held_mask || result_status !== held_status ||
                    result_saturation !== held_saturation || result_compute_cycles !== held_cycles)
                    $fatal(1,"FAIL output backpressure stability");
            end
            consume;
            if (vector_index%64 == 63) $display("RTL_PROGRESS vectors=%0d",vector_index+1);
        end
        $display("RTL_VECTOR_PASS vectors=%0d intermediate_values=%0d fixed_compute_cycles=14035",VECTOR_COUNT,VECTOR_COUNT*288);
        command(10001,MODEL_TAG,18'h00001,0); check_error(10001,16'h0002);
        command(10002,MODEL_TAG^32'h1,18'h3ffff,0); check_error(10002,16'h0004);
        command(10003,MODEL_TAG,18'h3ffff,16'h0004); check_error(10003,16'h0040);
        command(10004,MODEL_TAG,18'h00001,16'h0004); check_error(10004,16'h0042);
        command(10005,MODEL_TAG,18'h3ffff,0); beat(0,1); check_error(10005,16'h0001);
        command(10006,MODEL_TAG,18'h3ffff,0);
        for(i=0;i<144;i=i+1) beat(0,0);
        check_error(10006,16'h0001);
        command(10007,MODEL_TAG,18'h3ffff,0); check_error(10007,16'h0008);
        command(10008,MODEL_TAG,18'h3ffff,0); beat(0,0); check_error(10008,16'h0008);
        // Exactly at timeout boundary, a valid input beat takes priority.
        command(10009,MODEL_TAG,18'h3ffff,flags[0]);
        repeat(31) @(negedge clk);
        feature_valid=1; feature_data=inputs[0]; feature_last=0;
        @(negedge clk); feature_valid=0;
        for(i=1;i<144;i=i+1) beat(inputs[i],i==143);
        check_vector(0,10009); consume; protocol_cases=protocol_cases+1;
        // Reset mid-input, mid-compute, and while a result is held.
        command(10010,MODEL_TAG,18'h3ffff,0); beat(123,0); reset_core;
        command(10011,MODEL_TAG,18'h3ffff,flags[0]);
        for(i=0;i<144;i=i+1) beat(inputs[i],i==143);
        repeat(200) @(negedge clk);
        reset_core;
        command(10012,MODEL_TAG,18'h3ffff,flags[0]);
        for(i=0;i<144;i=i+1) beat(inputs[i],i==143);
        check_vector(0,10012); reset_core;
        command(10013,MODEL_TAG,18'h3ffff,flags[0]);
        for(i=0;i<144;i=i+1) beat(inputs[i],i==143);
        check_vector(0,10013); consume;
        protocol_cases=protocol_cases+3;
        $display("RTL_ALL_PASS protocol_cases=%0d",protocol_cases);
        $finish;
    end
    initial begin #1000000000; $fatal(1,"FAIL global watchdog"); end
endmodule
