`timescale 1ns/1ps
// Whole-frame host/RTL adjudication boundary. Only a matching, timely quorum
// AND the upstream security decision may release an immutable queued frame.
module afdx_defense_gate #(
 parameter integer MAX_WIRE=1536,QUEUE_SLOTS=4,DEADLINE_CYCLES=65536
)(
 input wire clk,rst,input wire [63:0] cycle,input wire [31:0] policy_epoch,
 input wire [7:0] a_data,b_data,input wire a_valid,b_valid,a_error,b_error,
 input wire [63:0] a_delay,b_delay,input wire ai_block,
 output wire [7:0] out_a,out_b,output wire out_av,out_bv,out_ae,out_be,
 output wire [63:0] out_a_delay,out_b_delay,
 input wire cfg_valid,cfg_write,input wire [15:0] cfg_addr,input wire [31:0] cfg_wdata,
 output reg cfg_ready,cfg_error,output reg [31:0] cfg_rdata,
 output wire idle,request_valid,output reg [31:0] forwarded,blocked,timeouts,ai_blocked,stale_responses,
 output wire [31:0] overflows,output reg [63:0] last_request,last_latency,
 output reg [2:0] last_reason
);
wire [1:0] requests,goods,takes,qidle,replay_ready,replay_start,replay_idle;
wire [MAX_WIRE*8-1:0] packets[0:1];wire [10:0] lengths[0:1];wire [63:0] stamps[0:1];wire [31:0] lost[0:1];
wire [7:0] inputs_data[0:1];wire [1:0] inputs_valid={b_valid,a_valid},inputs_error={b_error,a_error};
assign inputs_data[0]=a_data;assign inputs_data[1]=b_data;
wire [63:0] input_delays[0:1];assign input_delays[0]=a_delay;assign input_delays[1]=b_delay;
localparam IDLE=0,START=1,VOTE=2,RESULT=3;
reg [1:0] state;reg owner,last_owner;reg [31:0] retire_age;
reg [63:0] next_id,request_id,stamp_q,replay_stamp[0:1];
reg [31:0] epoch_q,generation,generation_q,next_generation;
reg [3:0] active_mask,mask_q,next_mask;
reg [MAX_WIRE*8-1:0] packet_q;reg [10:0] length_q;reg good_q;
reg result_allow,result_quorum;reg [31:0] rows[0:63];reg [3:0] response_valid;
wire [3:0] response_allow;wire [255:0] response_ids;wire [127:0] response_epochs,response_generations;
wire [1023:0] response_digests;
wire [15:0] replay_data;wire [1:0] replay_valid,replay_error;
assign out_a=replay_data[7:0];assign out_b=replay_data[15:8];
assign out_av=replay_valid[0];assign out_bv=replay_valid[1];assign out_ae=replay_error[0];assign out_be=replay_error[1];
wire vote_busy,vote_done,vote_quorum,vote_allow;wire [1:0] vote_reason;
wire transfer=cfg_valid&&cfg_ready&&!cfg_error;
wire choice=requests==3?!last_owner:requests[1];
assign request_valid=state==VOTE;
assign overflows=lost[0]+lost[1];
assign idle=state==IDLE&&(&qidle)&&(&replay_idle)&&!a_valid&&!b_valid;
assign takes[0]=state==VOTE&&vote_done&&!owner;
assign takes[1]=state==VOTE&&vote_done&&owner;
assign replay_start[0]=takes[0]&&vote_allow&&!ai_block&&good_q;
assign replay_start[1]=takes[1]&&vote_allow&&!ai_block&&good_q;
assign out_a_delay=cycle-replay_stamp[0];assign out_b_delay=cycle-replay_stamp[1];
genvar g;
generate for(g=0;g<2;g=g+1)begin:LANES
 afdx_sec_frame_queue #(.SLOTS(QUEUE_SLOTS),.MAX_WIRE(MAX_WIRE)) queue(
  .clk(clk),.rst(rst),.cycle(cycle-input_delays[g]),.data(inputs_data[g]),.valid(inputs_valid[g]),.error(inputs_error[g]),
  .request(requests[g]),.packet(packets[g]),.length(lengths[g]),.stamp(stamps[g]),.good(goods[g]),.take(takes[g]),.idle(qidle[g]),.overflows(lost[g]));
 afdx_sec_replay #(.MAX_WIRE(MAX_WIRE)) replay(.clk(clk),.rst(rst),.start(replay_start[g]),.packet(packet_q),.length(length_q),
  .ready(replay_ready[g]),.data(replay_data[g*8+:8]),.valid(replay_valid[g]),.error(replay_error[g]),.idle(replay_idle[g]));
end
for(g=0;g<4;g=g+1)begin:RESPONSES
 assign response_ids[g*64+:64]={rows[g*16+1],rows[g*16]};
 assign response_epochs[g*32+:32]=rows[g*16+2];assign response_generations[g*32+:32]=rows[g*16+3];
 assign response_allow[g]=rows[g*16+4][0];
 assign response_digests[g*256+:256]={rows[g*16+12],rows[g*16+11],rows[g*16+10],rows[g*16+9],rows[g*16+8],rows[g*16+7],rows[g*16+6],rows[g*16+5]};
end endgenerate
afdx_mimic_quorum_gate #(.DEADLINE_CYCLES(DEADLINE_CYCLES)) voter(
 .clk(clk),.rst(rst),.start(state==START),.request_id(request_id),.policy_epoch(epoch_q),.schedule_generation(generation_q),.active_mask(mask_q),
 .response_valid(response_valid),.response_allow(response_allow),.response_request_id(response_ids),.response_epoch(response_epochs),.response_generation(response_generations),.response_semantic_sha256(response_digests),
 .baseline_valid(state==VOTE),.baseline_allow(good_q),.baseline_request_id(request_id),.baseline_epoch(epoch_q),
 .busy(vote_busy),.done(vote_done),.quorum_valid(vote_quorum),.allow(vote_allow),.result_reason(vote_reason),.result_request_id(),.result_epoch(),.result_generation());
integer i,ci,word_index,response_index,population;reg next_mask_valid;
always @*begin
 population=0;for(ci=0;ci<4;ci=ci+1)if(next_mask[ci])population=population+1;
 next_mask_valid=population==3;
 cfg_ready=1;cfg_error=cfg_addr[1:0]!=0;cfg_rdata=0;word_index=(cfg_addr-16'h1100)>>2;response_index=0;
 if(cfg_write)begin
  case(cfg_addr)
   16'h1040:if(state!=VOTE||cfg_wdata[31:4]!=0)cfg_error=1;
   16'h1044:if(state!=RESULT||cfg_wdata!=1||!next_mask_valid||next_generation<generation||(next_mask!=active_mask&&next_generation<=generation))cfg_error=1;
   16'h1048:if(state!=RESULT||cfg_wdata[31:4]!=0)cfg_error=1;
   16'h104c:if(state!=RESULT||cfg_wdata<generation)cfg_error=1;
   default:if(cfg_addr<16'h1100||cfg_addr>=16'h1200||state!=VOTE)cfg_error=1;
  endcase
 end else begin
  case(cfg_addr)
   16'h1000:cfg_rdata=32'h4d494d31;
   16'h1004:cfg_rdata={27'd0,owner,result_quorum,result_allow,state==RESULT,state==VOTE};
   16'h1008:cfg_rdata=request_id[31:0];16'h100c:cfg_rdata=request_id[63:32];
   16'h1010:cfg_rdata=epoch_q;16'h1014:cfg_rdata=generation_q;16'h1018:cfg_rdata={28'd0,mask_q};
   16'h101c:cfg_rdata={15'd0,owner,5'd0,length_q};16'h1020:cfg_rdata=stamp_q[31:0];16'h1024:cfg_rdata=stamp_q[63:32];
   16'h1028:cfg_rdata={31'd0,good_q};16'h102c:cfg_rdata={29'd0,last_reason};
   16'h1030:cfg_rdata=cycle[31:0];16'h1034:cfg_rdata=cycle[63:32];
   16'h1050:cfg_rdata=forwarded;16'h1054:cfg_rdata=blocked;16'h1058:cfg_rdata=timeouts;
   16'h105c:cfg_rdata=overflows;16'h1060:cfg_rdata=ai_blocked;16'h1064:cfg_rdata=stale_responses;
   16'h1068:cfg_rdata=last_request[31:0];16'h106c:cfg_rdata=last_request[63:32];
   16'h1070:cfg_rdata=last_latency[31:0];16'h1074:cfg_rdata=last_latency[63:32];
   default:if(cfg_addr>=16'h1800&&cfg_addr<16'h1800+MAX_WIRE)begin
    if(state!=VOTE&&state!=RESULT)cfg_error=1;else cfg_rdata=packet_q[((cfg_addr-16'h1800)>>2)*32+:32];
   end else cfg_error=1;
  endcase
 end
end
always @(posedge clk)begin
 if(rst)begin
  state<=IDLE;owner<=0;last_owner<=1;retire_age<=0;next_id<=1;request_id<=0;stamp_q<=0;epoch_q<=0;generation<=1;generation_q<=1;next_generation<=1;
  active_mask<=7;mask_q<=7;next_mask<=7;packet_q<=0;length_q<=0;good_q<=0;response_valid<=0;result_allow<=0;result_quorum<=0;
  forwarded<=0;blocked<=0;timeouts<=0;ai_blocked<=0;stale_responses<=0;last_request<=0;last_latency<=0;last_reason<=0;
  replay_stamp[0]<=0;replay_stamp[1]<=0;for(i=0;i<64;i=i+1)rows[i]<=0;
 end else begin
  response_valid<=0;
  if(state==IDLE&&requests!=0&&replay_ready[choice]&&next_id!=0)begin
   owner<=choice;last_owner<=choice;packet_q<=packets[choice];length_q<=lengths[choice];stamp_q<=stamps[choice];good_q<=goods[choice];
   request_id<=next_id;next_id<=next_id+1'b1;epoch_q<=policy_epoch;generation_q<=generation;mask_q<=active_mask;
   next_mask<=active_mask;next_generation<=generation;result_allow<=0;result_quorum<=0;for(i=0;i<64;i=i+1)rows[i]<=0;state<=START;
  end else if(state==START)state<=VOTE;
  else if(state==VOTE&&vote_done)begin
   state<=RESULT;retire_age<=0;result_allow<=vote_allow&&!ai_block&&good_q;result_quorum<=vote_quorum;
   last_request<=request_id;last_latency<=cycle-stamp_q;
   last_reason<=vote_allow&&good_q&&ai_block?3'd4:{1'b0,vote_reason};
   if(vote_allow&&!ai_block&&good_q)begin forwarded<=forwarded+1'b1;replay_stamp[owner]<=stamp_q;end
   else begin blocked<=blocked+1'b1;if(vote_reason==2)timeouts<=timeouts+1'b1;if(vote_allow&&ai_block)ai_blocked<=ai_blocked+1'b1;end
  end else if(state==RESULT)begin
   if(retire_age>=DEADLINE_CYCLES-1)state<=IDLE;else retire_age<=retire_age+1'b1;
  end
  if(transfer&&cfg_write)begin
   case(cfg_addr)
    16'h1040:begin
     response_valid<=cfg_wdata[3:0];
     for(i=0;i<4;i=i+1)if(cfg_wdata[i]&&(!mask_q[i]||response_ids[i*64+:64]!=request_id||response_epochs[i*32+:32]!=epoch_q||response_generations[i*32+:32]!=generation_q))stale_responses<=stale_responses+1'b1;
    end
    16'h1044:begin active_mask<=next_mask;generation<=next_generation;state<=IDLE;end
    16'h1048:next_mask<=cfg_wdata[3:0];16'h104c:next_generation<=cfg_wdata;
    default:rows[(cfg_addr-16'h1100)>>2]<=cfg_wdata;
   endcase
  end
 end
end
endmodule
