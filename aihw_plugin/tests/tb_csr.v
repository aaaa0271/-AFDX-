`timescale 1ns/1ps
module tb_csr;
    `include "ai_model_params.vh"
    reg clk=0;
    always #40 clk=~clk;
    reg rst_n=0, valid=0, wr=0;
    reg [7:0] addr=0;
    reg [31:0] wdata=0;
    wire ready, error;
    wire [31:0] rdata;
    reg [31:0] value;
    reg [15:0] inputs [0:143];
    reg [15:0] logits [0:8];
    reg [15:0] flags [0:0];
    reg [15:0] statuses [0:0];
    reg [7:0] masks [0:0];
    reg [7:0] saturations [0:0];
    integer i, polls;
    afdx_ai_csr dut(.clk(clk),.rst_n(rst_n),.cfg_valid(valid),.cfg_write(wr),
        .cfg_addr(addr),.cfg_wdata(wdata),.cfg_ready(ready),.cfg_error(error),.cfg_rdata(rdata));

    task access;
        input write_enable;
        input [7:0] address;
        input [31:0] data;
        input expected_error;
        integer timeout;
        begin
            @(negedge clk); valid=1; wr=write_enable; addr=address; wdata=data;
            #1; timeout=0;
            while(!ready && timeout<15000) begin @(negedge clk); #1; timeout=timeout+1; end
            if (!ready || error !== expected_error) $fatal(1,"FAIL CSR access addr=%h error=%b",addr,error);
            value=rdata;
            @(negedge clk); valid=0;
        end
    endtask

    initial begin
        // Load only the first vector; end indices avoid misleading truncation warnings.
        $readmemh("reports/csr_vectors/inputs.mem",inputs);
        $readmemh("reports/csr_vectors/logits.mem",logits);
        $readmemh("reports/csr_vectors/flags.mem",flags);
        $readmemh("reports/csr_vectors/status.mem",statuses);
        $readmemh("reports/csr_vectors/mask.mem",masks);
        $readmemh("reports/csr_vectors/saturation.mem",saturations);
        repeat(3) @(negedge clk); rst_n=1;
        access(0,0,0,0); if(value!==32'h41494831) $fatal(1,"FAIL CSR magic");
        access(0,4,0,0); if(value!==MODEL_TAG) $fatal(1,"FAIL CSR model tag");
        access(0,8,0,0); if(value!==1) $fatal(1,"FAIL CSR idle");
        access(1,0,0,1); access(0,1,0,1); access(0,8'hfc,0,1);
        access(1,8'h1c,2,1); access(1,8'h14,32'h80000000,1); access(1,8'h20,32'h80000000,1);
        access(1,8'h0c,32'habcdef01,0);
        access(1,8'h10,MODEL_TAG,0);
        access(1,8'h14,18'h3ffff,0);
        access(1,8'h18,flags[0],0);
        access(1,8'h1c,1,0);
        for(i=0;i<144;i=i+1) access(1,8'h20,{15'd0,(i==143),inputs[i]},0);
        // Pending-job metadata writes must not corrupt the in-flight job.
        access(1,8'h0c,32'h11111111,0);
        polls=0;
        access(0,8,0,0);
        while(!value[2] && polls<15000) begin access(0,8,0,0); polls=polls+1; end
        if (!value[2]) $fatal(1,"FAIL CSR result deadline");
        access(0,8'h28,0,0); if(value!==32'habcdef01) $fatal(1,"FAIL CSR job id");
        access(0,8'h2c,0,0);
        if(value!=={masks[0],5'd0,saturations[0][2:0],statuses[0]}) $fatal(1,"FAIL CSR status");
        access(0,8'h30,0,0); if(value!==14035) $fatal(1,"FAIL CSR cycles");
        for(i=0;i<9;i=i+1) begin
            access(0,8'h34+i*4,0,0);
            if(value!=={16'd0,logits[i]}) $fatal(1,"FAIL CSR logit %0d",i);
        end
        access(1,8'h24,1,0);
        access(0,8,0,0); if(value!==1) $fatal(1,"FAIL CSR ack");
        $display("CSR_ALL_PASS normal_jobs=1 illegal_accesses=6");
        $finish;
    end
    initial begin #2000000; $fatal(1,"FAIL CSR watchdog"); end
endmodule
