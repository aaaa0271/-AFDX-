`timescale 1ns/1ps
// Standalone transaction-level adjudicator, not a MAC stream adapter.
// The trusted upstream must hash the complete canonical semantic result,
// attach the captured input identity, and supply the ORIGINAL engine decision.
module afdx_mimic_quorum_gate #(
 parameter integer DEADLINE_CYCLES=32
)(
 input wire clk,rst,start,
 input wire [63:0] request_id,
 input wire [31:0] policy_epoch,schedule_generation,
 input wire [3:0] active_mask,
 input wire [3:0] response_valid,response_allow,
 input wire [255:0] response_request_id,
 input wire [127:0] response_epoch,response_generation,
 input wire [1023:0] response_semantic_sha256,
 input wire baseline_valid,baseline_allow,
 input wire [63:0] baseline_request_id,
 input wire [31:0] baseline_epoch,
 output reg busy,done,quorum_valid,allow,
 output reg [1:0] result_reason,
 output reg [63:0] result_request_id,
 output reg [31:0] result_epoch,result_generation
);
// reason: 0=allow, 1=quorum/baseline denied, 2=deadline/no quorum,
// 3=invalid active set. At most one result is published per start.
reg [63:0] req_q;reg [31:0] epoch_q,generation_q;reg [3:0] mask_q,seen_q,allows_q;
reg [1023:0] digests_q;reg base_seen_q,base_allow_q;integer age;
reg [3:0] seen_n,allows_n;reg [1023:0] digests_n;reg base_seen_n,base_allow_n;
reg winner,winner_allow;integer i,j,k,pop;
always @*begin
 seen_n=seen_q;allows_n=allows_q;digests_n=digests_q;
 base_seen_n=base_seen_q;base_allow_n=base_allow_q;
 for(i=0;i<4;i=i+1)begin
  if(response_valid[i]&&mask_q[i]&&!seen_q[i]&&response_request_id[i*64+:64]==req_q&&response_epoch[i*32+:32]==epoch_q&&response_generation[i*32+:32]==generation_q)begin
   seen_n[i]=1;allows_n[i]=response_allow[i];digests_n[i*256+:256]=response_semantic_sha256[i*256+:256];
  end
 end
 if(!base_seen_q&&baseline_valid&&baseline_request_id==req_q&&baseline_epoch==epoch_q)begin base_seen_n=1;base_allow_n=baseline_allow;end
 winner=0;winner_allow=0;
 for(i=0;i<4;i=i+1)for(j=i+1;j<4;j=j+1)begin
  if(seen_n[i]&&seen_n[j]&&allows_n[i]==allows_n[j]&&digests_n[i*256+:256]==digests_n[j*256+:256])begin winner=1;winner_allow=allows_n[i];end
 end
end
always @(posedge clk)begin
 if(rst)begin
  busy<=0;done<=0;quorum_valid<=0;allow<=0;result_reason<=0;result_request_id<=0;result_epoch<=0;result_generation<=0;
  req_q<=0;epoch_q<=0;generation_q<=0;mask_q<=0;seen_q<=0;allows_q<=0;digests_q<=0;base_seen_q<=0;base_allow_q<=0;age<=0;
 end else begin
  done<=0;
  if(start&&!busy)begin
   pop=0;for(k=0;k<4;k=k+1)if(active_mask[k])pop=pop+1;
   req_q<=request_id;epoch_q<=policy_epoch;generation_q<=schedule_generation;mask_q<=active_mask;
   result_request_id<=request_id;result_epoch<=policy_epoch;result_generation<=schedule_generation;
   seen_q<=0;allows_q<=0;digests_q<=0;base_seen_q<=0;base_allow_q<=0;age<=0;allow<=0;quorum_valid<=0;
   if(pop!=3||DEADLINE_CYCLES<1)begin done<=1;busy<=0;result_reason<=3;end
   else busy<=1;
  end else if(busy)begin
   seen_q<=seen_n;allows_q<=allows_n;digests_q<=digests_n;base_seen_q<=base_seen_n;base_allow_q<=base_allow_n;
   // Include results arriving on the final permitted cycle before timing out.
   if(winner&&base_seen_n)begin
    quorum_valid<=1;allow<=winner_allow&&base_allow_n;result_reason<=winner_allow&&base_allow_n?0:1;done<=1;busy<=0;
   end else if(age==DEADLINE_CYCLES-1)begin
    quorum_valid<=winner;allow<=0;result_reason<=2;done<=1;busy<=0;
   end else age<=age+1;
  end
 end
end
endmodule
