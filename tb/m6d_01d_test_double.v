`timescale 1ns/1ps
// 仅在mechanics独立库编译，绝不代替真实M6D回归；请求字节控制长度/延迟。
module afdx_m6d_integration #(
 parameter MAX_MSG_BYTES=128, MAX_VB_BYTES=64, MAX_RESPONSE_BYTES=96, CLK_HZ=1000
)(
 input wire clk,rst_n,req,
 input wire [7:0] msg_length,
 input wire [MAX_MSG_BYTES*8-1:0] msg_bytes,
 output reg response_done,response_valid,response_error,
 output reg [7:0] response_error_code,response_length,
 output reg [MAX_RESPONSE_BYTES*8-1:0] response_bytes,
 input wire m5_network_a_enable,m5_network_b_enable,m5_degraded_mode,m5_redundancy_ok,
 input wire m5_frame_count_match,m5_active_byte_count_match,m5_fault_applied_event,
 input wire [31:0] m5_rx_accepted_count,m5_rx_accepted_a_count,m5_rx_accepted_b_count,
 input wire [31:0] m5_rx_duplicate_count,m5_rx_cross_network_duplicate_count,m5_rx_same_network_repeat_count,
 input wire [31:0] m5_rx_stale_count,m5_rx_sequence_gap_count,m5_tx_a_frame_count,m5_tx_b_frame_count,
 input wire [31:0] m5_tx_a_active_byte_count,m5_tx_b_active_byte_count,m5_tx_byte_mismatch_count,
 input wire [31:0] m5_tx_frame_skew_cycle_count,m5_tx_frame_done_skew_count,m5_tx_er_mismatch_count,
 input wire [31:0] m5_tx_a_error_cycle_count,m5_tx_b_error_cycle_count,m5_tx_a_underrun_count,m5_tx_b_underrun_count
);
 integer timer,k;
 reg [7:0] len,seed;
 always @(posedge clk) begin
  if(!rst_n) begin
   timer<=0; response_done<=0; response_valid<=0; response_error<=0;
   response_error_code<=0; response_length<=0; response_bytes<=0; len<=0; seed<=0;
  end else begin
   response_done<=0;
   // done采样后立即扰动输出，证明发送只依赖capture而非实时M6D输出。
   response_bytes<=~response_bytes; response_length<=8'he7; response_valid<=0;
   if(req) begin timer<=msg_bytes[15:8]+1; len<=msg_bytes[7:0]; seed<=msg_bytes[23:16]; end
   else if(timer>1) timer<=timer-1;
   else if(timer==1) begin
    timer<=0; response_done<=1; response_valid<=(len!=0); response_length<=len;
    for(k=0;k<96;k=k+1) response_bytes[767-k*8 -: 8]<=seed+k;
   end
  end
 end
endmodule
