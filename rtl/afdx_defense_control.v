`timescale 1ns/1ps
// Trusted local AI interface, raw traffic measurements, and a bounded response
// actuator. AI may only add a temporary RX block, never relax security policy.
module afdx_defense_control #(
 parameter integer CLK_HZ=12500000,AI_BLOCK_CYCLES=125000,
 parameter WEIGHTS_FILE="aihw_plugin/rtl/weights.mem",BIASES_FILE="aihw_plugin/rtl/biases.mem",
 parameter THRESHOLDS_FILE="aihw_plugin/rtl/thresholds.mem",SHIFTS_FILE="aihw_plugin/rtl/shifts.mem"
)(
 input wire clk,rst,input wire [63:0] cycle,utc,
 input wire [31:0] policy_epoch,input wire [31:0] sec_allow,sec_block,sec_overflow,ab_conflicts,hash_failures,time_alarms,
 input wire [7:0] a_rx,b_rx,input wire a_valid,b_valid,a_error,b_error,
 input wire loading,load_complete,load_failed,rtc_locked,input wire [31:0] package_generation,
 input wire [31:0] mimic_forwarded,mimic_blocked,mimic_overflow,input wire [63:0] mimic_latency,
 input wire [255:0] service_telemetry,input wire [159:0] security_telemetry,
 input wire cfg_valid,cfg_write,input wire [15:0] cfg_addr,input wire [31:0] cfg_wdata,
 output wire cfg_ready,cfg_error,output reg [31:0] cfg_rdata,
 output reg ai_block,ai_alarm,output reg [7:0] ai_candidates,output reg [15:0] ai_status,
 output reg [31:0] ai_results,ai_actions,output wire ai_idle
);
wire ai_bus=cfg_addr<16'h0100;
wire ai_ready,ai_error,ai_result;wire [31:0] ai_rdata,ai_job;wire [143:0] ai_logits;wire [7:0] ai_mask;wire [15:0] result_status;
reg actuator_enabled,seen_result;reg [7:0] action_mask;reg [31:0] block_left;reg [31:0] snapshot[0:63];
reg [63:0] snap_cycle;reg [31:0] snapshot_id;reg previous_a,previous_b;
reg [31:0] frame_count[0:1],bad_count[0:1];reg [15:0] length[0:1];reg [31:0] crc[0:1];reg [1:0] bad;
reg [63:0] bytes_total,bytes_squared,gap_total,gap_squared,last_start[0:1];reg [31:0] gap_count;
reg [1:0] seen_start;reg [63:0] observed_cycle;
wire [1:0] valids={b_valid,a_valid},errors={b_error,a_error},previous={previous_b,previous_a};
wire [7:0] data[0:1];assign data[0]=a_rx;assign data[1]=b_rx;
wire local_transfer=cfg_valid&&!ai_bus&&cfg_ready&&!cfg_error;
reg local_error;integer i,k;reg [63:0] increment_bytes,increment_square,increment_gap,increment_gap_square;
reg [31:0] increment_gaps;
function [31:0] crcbyte;input [31:0] c;input [7:0] b;reg [31:0] v;integer n;begin
 v=c^b;for(n=0;n<8;n=n+1)v=v[0]?(v>>1)^32'hedb88320:v>>1;crcbyte=v;
end endfunction
afdx_defense_ai_csr #(.WEIGHTS_FILE(WEIGHTS_FILE),.BIASES_FILE(BIASES_FILE),.THRESHOLDS_FILE(THRESHOLDS_FILE),.SHIFTS_FILE(SHIFTS_FILE)) ai(
 .clk(clk),.rst_n(!rst),.cfg_valid(cfg_valid&&ai_bus),.cfg_write(cfg_write),.cfg_addr(cfg_addr[7:0]),.cfg_wdata(cfg_wdata),
 .cfg_ready(ai_ready),.cfg_error(ai_error),.cfg_rdata(ai_rdata),.tap_valid(ai_result),.tap_idle(ai_idle),.tap_mask(ai_mask),.tap_status(result_status),.tap_job_id(ai_job),.tap_logits(ai_logits));
assign cfg_ready=ai_bus?ai_ready:1'b1;
assign cfg_error=ai_bus?ai_error:local_error;
always @*begin
 local_error=cfg_addr[1:0]!=0;cfg_rdata=0;
 if(ai_bus)cfg_rdata=ai_rdata;
 else if(cfg_write)begin
  case(cfg_addr)
   16'h0100:if(cfg_wdata!=1)local_error=1;
   16'h0200:if(cfg_wdata[31:1]!=0)local_error=1;
   16'h0204:if(cfg_wdata[31:8]!=0)local_error=1;
   16'h0208:if(cfg_wdata!=1)local_error=1;
   default:local_error=1;
  endcase
 end else begin
  if(cfg_addr>=16'h0100&&cfg_addr<16'h0200)cfg_rdata=snapshot[(cfg_addr-16'h0100)>>2];
  else case(cfg_addr)
   16'h0200:cfg_rdata={31'd0,actuator_enabled};16'h0204:cfg_rdata={24'd0,action_mask};
   16'h0208:cfg_rdata={30'd0,ai_alarm,ai_block};16'h020c:cfg_rdata=block_left;
   16'h0210:cfg_rdata=ai_results;16'h0214:cfg_rdata=ai_actions;
   16'h0218:cfg_rdata={8'd0,ai_candidates,ai_status};
   16'h021c:cfg_rdata=ai_job;
   default:local_error=1;
  endcase
 end
end
always @(posedge clk)begin
 if(rst)begin
  actuator_enabled<=0;action_mask<=8'hff;block_left<=0;seen_result<=0;ai_block<=0;ai_alarm<=0;ai_candidates<=0;ai_status<=0;ai_results<=0;ai_actions<=0;
  snapshot_id<=0;snap_cycle<=0;previous_a<=0;previous_b<=0;bad<=0;seen_start<=0;bytes_total<=0;bytes_squared<=0;gap_total<=0;gap_squared<=0;gap_count<=0;observed_cycle<=0;
  for(i=0;i<2;i=i+1)begin frame_count[i]<=0;bad_count[i]<=0;length[i]<=0;crc[i]<=32'hffffffff;last_start[i]<=0;end
  for(i=0;i<64;i=i+1)snapshot[i]<=0;
 end else begin
  previous_a<=a_valid;previous_b<=b_valid;observed_cycle<=cycle;
  increment_bytes=0;increment_square=0;increment_gap=0;increment_gap_square=0;increment_gaps=0;
  for(i=0;i<2;i=i+1)begin
   if(valids[i])begin
    if(!previous[i])begin
     length[i]<=1;crc[i]<=32'hffffffff;bad[i]<=errors[i]||data[i]!=8'h55;
     if(seen_start[i])begin increment_gap=increment_gap+cycle-last_start[i];increment_gap_square=increment_gap_square+(cycle-last_start[i])*(cycle-last_start[i]);increment_gaps=increment_gaps+1'b1;end
     last_start[i]<=cycle;seen_start[i]<=1;
    end else begin
     if(length[i]!=65535)length[i]<=length[i]+1'b1;else bad[i]<=1;
     if(length[i]>=8)crc[i]<=crcbyte(crc[i],data[i]);
     if(errors[i]||(length[i]<7&&data[i]!=8'h55)||(length[i]==7&&data[i]!=8'hd5))bad[i]<=1;
    end
   end else if(previous[i])begin
    frame_count[i]<=frame_count[i]+1'b1;
    if(bad[i]||length[i]<72||length[i]>1526||crc[i]!=32'hdebb20e3)bad_count[i]<=bad_count[i]+1'b1;
    increment_bytes=increment_bytes+(length[i]>=8?length[i]-8:0);
    increment_square=increment_square+(length[i]>=8?(length[i]-8)*(length[i]-8):0);
   end
  end
  bytes_total<=bytes_total+increment_bytes;bytes_squared<=bytes_squared+increment_square;
  gap_total<=gap_total+increment_gap;gap_squared<=gap_squared+increment_gap_square;gap_count<=gap_count+increment_gaps;
  if(!ai_result)seen_result<=0;
  if(block_left!=0)begin block_left<=block_left-1'b1;if(block_left==1)ai_block<=0;end
  if(ai_result&&!seen_result)begin
   seen_result<=1;ai_results<=ai_results+1'b1;ai_candidates<=ai_mask;ai_status<=result_status;
   if(result_status==0&&ai_mask!=0)begin
    ai_alarm<=1;
    if(actuator_enabled&&(ai_mask&action_mask)!=0)begin ai_block<=1;block_left<=AI_BLOCK_CYCLES>0?AI_BLOCK_CYCLES:1;ai_actions<=ai_actions+1'b1;end
   end
  end
  if(local_transfer&&cfg_write)case(cfg_addr)
   16'h0200:begin actuator_enabled<=cfg_wdata[0];if(!cfg_wdata[0])begin ai_block<=0;block_left<=0;end end
   16'h0204:action_mask<=cfg_wdata[7:0];
   16'h0208:ai_alarm<=0;
   16'h0100:begin
    snapshot_id<=snapshot_id+1'b1;snap_cycle<=cycle;
    snapshot[0]<=32'h44454631;snapshot[1]<=snapshot_id+1'b1;snapshot[2]<=cycle[31:0];snapshot[3]<=cycle[63:32];
    snapshot[4]<=utc[31:0];snapshot[5]<=utc[63:32];snapshot[6]<=policy_epoch;snapshot[7]<=CLK_HZ;
    snapshot[8]<=frame_count[0];snapshot[9]<=frame_count[1];snapshot[10]<=bad_count[0];snapshot[11]<=bad_count[1];
    snapshot[12]<=bytes_total[31:0];snapshot[13]<=bytes_total[63:32];snapshot[14]<=bytes_squared[31:0];snapshot[15]<=bytes_squared[63:32];
    snapshot[16]<=gap_count;snapshot[17]<=gap_total[31:0];snapshot[18]<=gap_total[63:32];snapshot[19]<=gap_squared[31:0];snapshot[20]<=gap_squared[63:32];
    snapshot[21]<=sec_allow;snapshot[22]<=sec_block;snapshot[23]<=sec_overflow;snapshot[24]<=ab_conflicts;snapshot[25]<=hash_failures;snapshot[26]<=time_alarms;
    snapshot[27]<=mimic_forwarded;snapshot[28]<=mimic_blocked;snapshot[29]<=mimic_overflow;snapshot[30]<=mimic_latency[31:0];snapshot[31]<=mimic_latency[63:32];
    snapshot[32]<={28'd0,rtc_locked,load_failed,load_complete,loading};snapshot[33]<=package_generation;
    snapshot[34]<=ai_results;snapshot[35]<=ai_actions;
    for(k=0;k<8;k=k+1)snapshot[36+k]<=service_telemetry[k*32+:32];
    for(k=0;k<5;k=k+1)snapshot[44+k]<=security_telemetry[k*32+:32];
   end
  endcase
 end
end
endmodule
