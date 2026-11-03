`timescale 1ns/1ps
module tb_mimic_quorum;
reg clk=0;always #5 clk=~clk;
reg rst=1,start=0;reg [63:0] request_id=0;reg [31:0] policy_epoch=3,schedule_generation=1;reg [3:0] active_mask=7;
reg [3:0] response_valid=0,response_allow=0;reg [255:0] response_request_id=0;reg [127:0] response_epoch=0,response_generation=0;reg [1023:0] response_semantic_sha256=0;
reg baseline_valid=0,baseline_allow=0;reg [63:0] baseline_request_id=0;reg [31:0] baseline_epoch=3;
wire busy,done,quorum_valid,allow;wire [1:0] result_reason;wire [63:0] result_request_id;wire [31:0] result_epoch,result_generation;
integer failures=0,passed=0,cycles=0,done_count=0;
afdx_mimic_quorum_gate #(.DEADLINE_CYCLES(6)) dut(.*);
always @(posedge clk)begin #1;if(done)done_count=done_count+1;end
task tick;begin @(posedge clk);#2;end endtask
task clear_inputs;begin response_valid=0;baseline_valid=0;start=0;end endtask
task begin_request;input [3:0] mask;begin
 @(negedge clk);clear_inputs;request_id=request_id+1;active_mask=mask;start=1;tick;@(negedge clk);start=0;
end endtask
task response;input integer eid;input verdict;input [255:0] digest;input integer epoch_delta;input integer gen_delta;input integer id_delta;begin
 response_valid[eid]=1;response_allow[eid]=verdict;response_request_id[eid*64+:64]=request_id+id_delta;response_epoch[eid*32+:32]=policy_epoch+epoch_delta;response_generation[eid*32+:32]=schedule_generation+gen_delta;response_semantic_sha256[eid*256+:256]=digest;
end endtask
task baseline;input verdict;input integer id_delta;begin baseline_valid=1;baseline_allow=verdict;baseline_request_id=request_id+id_delta;baseline_epoch=policy_epoch;end endtask
task expect_result;input integer label;input exp_allow;input exp_quorum;input [1:0] exp_reason;begin
 cycles=0;while(!done&&cycles<10)begin tick;cycles=cycles+1;end
 if(!done||allow!==exp_allow||quorum_valid!==exp_quorum||result_reason!==exp_reason||result_request_id!==request_id||result_epoch!==policy_epoch||result_generation!==schedule_generation)begin $display("MIMIC_FAIL case=%0d allow=%b quorum=%b reason=%0d",label,allow,quorum_valid,result_reason);failures=failures+1;end
 else begin passed=passed+1;$display("MIMIC_CASE_PASS %0d allow=%b quorum=%b reason=%0d",label,allow,quorum_valid,result_reason);end
 @(negedge clk);clear_inputs;tick;
end endtask
initial begin
 tick;tick;@(negedge clk);rst=0;
 // Two valid allows plus a disagreeing third.
 begin_request(7);response(0,1,256'h11,0,0,0);response(1,1,256'h11,0,0,0);response(2,0,256'h22,0,0,0);baseline(1,0);expect_result(1,1,1,0);
 // Original engine denial cannot be overridden.
 begin_request(7);response(0,1,256'h11,0,0,0);response(1,1,256'h11,0,0,0);baseline(0,0);expect_result(2,0,1,1);
 // Matching semantic denial remains a denial.
 begin_request(7);response(0,0,256'h33,0,0,0);response(1,0,256'h33,0,0,0);baseline(1,0);expect_result(3,0,1,1);
 // No quorum when every semantic digest differs.
 begin_request(7);response(0,1,256'h11,0,0,0);response(1,1,256'h22,0,0,0);response(2,1,256'h33,0,0,0);baseline(1,0);expect_result(4,0,0,2);
 // Old epoch and generation cannot supply a second vote.
 begin_request(7);response(0,1,256'h11,0,0,0);response(1,1,256'h11,-1,0,0);response(2,1,256'h11,0,-1,0);baseline(1,0);expect_result(5,0,0,2);
 // Inactive executor cannot vote.
 begin_request(7);response(0,1,256'h11,0,0,0);response(3,1,256'h11,0,0,0);baseline(1,0);expect_result(6,0,0,2);
 // Repeated replies from one identity cannot create quorum.
 begin_request(7);response(0,1,256'h11,0,0,0);baseline(1,0);tick;@(negedge clk);response(0,1,256'h11,0,0,0);expect_result(7,0,0,2);
 // Final permitted cycle is included in adjudication.
 begin_request(7);baseline(1,0);response(0,1,256'h11,0,0,0);tick;@(negedge clk);clear_inputs;
 repeat(4)begin tick;@(negedge clk);end
 response(1,1,256'h11,0,0,0);expect_result(8,1,1,0);
 // Quorum without matching original-engine decision never releases.
 begin_request(7);response(0,1,256'h11,0,0,0);response(1,1,256'h11,0,0,0);baseline(1,-1);expect_result(9,0,1,2);
 // Active set cannot silently shrink to two replicas.
 begin_request(3);expect_result(10,0,0,3);
 // Same digest but differing allow bit is not agreement.
 begin_request(7);response(0,1,256'h11,0,0,0);response(1,0,256'h11,0,0,0);baseline(1,0);expect_result(11,0,0,2);
 // Stale request number is rejected, even with correct epoch.
 begin_request(7);response(0,1,256'h11,0,0,0);response(1,1,256'h11,0,0,-1);baseline(1,0);expect_result(12,0,0,2);
 // A replacement active mask uses a fresh generation.
 schedule_generation=schedule_generation+1;begin_request(13);response(0,1,256'h44,0,0,0);response(3,1,256'h44,0,0,0);baseline(1,0);expect_result(13,1,1,0);
 if(failures==0&&passed==13&&done_count==13)$display("MIMIC_RTL_PASS cases=%0d done=%0d",passed,done_count);
 else $display("MIMIC_RTL_FAIL failures=%0d passed=%0d done=%0d",failures,passed,done_count);
 $finish;
end
initial begin #100000;$display("MIMIC_RTL_FAIL timeout");$finish;end
endmodule
