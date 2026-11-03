`timescale 1ns/1ps
// Four complete-frame slots per network. Only validated addressed frames enter
// the queue; immutable queued metadata cannot be overwritten by a later RX.
module afdx_shared_rx_demux #(
 parameter [31:0] MANAGER_IP=32'hc0a80173,
 parameter integer SPLIT_CLOCK=0,
 parameter [47:0] SERVICE_MAC=48'h030000000010,CLOCK_MAC=SERVICE_MAC,
 parameter integer SKEW_MAX_CYCLES=16000000,DUAL_TIMESTAMPS=0
)(
 input wire clk,rst,input wire [31:0] loader_ip,time_server_ip,
 input wire [7:0] a_data,b_data,input wire a_valid,b_valid,a_error,b_error,
 output reg [7:0] management_data,service_data,output reg management_valid,service_valid,
 output wire [31:0] accepted,duplicates,output reg [31:0] dropped,
 output wire idle,
 input wire [63:0] timestamp_now,output reg [63:0] service_timestamp,
 input wire [63:0] timestamp_b_now
);
reg [7:0] memory[0:12287];
reg [63:0] timestamps[0:7];
reg [10:0] count[0:1],length[0:7];reg [31:0] crc[0:1];reg [47:0] destination[0:1];
reg [1:0] wp[0:1],rp[0:1];reg [2:0] used[0:1];reg [7:0] service_slot;
reg [1:0] prev,bad,discard,push,pop;reg [3:0] drop_inc;
reg [2:0] state;localparam IDLE=0,PARSE=1,WAIT_PARSE=2,CHECK=3,WAIT_CHECK=4,REPLAY=5;
reg owner,rr;reg [2:0] slot;reg [10:0] index;reg packet_service;integer n;
wire [7:0] inputs_data[0:1];wire [1:0] inputs_valid={b_valid,a_valid},inputs_error={b_error,a_error};assign inputs_data[0]=a_data;assign inputs_data[1]=b_data;
function [31:0] crcbyte;input [31:0] c;input [7:0] x;reg [31:0] v;integer k;begin v=c^x;for(k=0;k<8;k=k+1)v=v[0]?(v>>1)^32'hedb88320:v>>1;crcbyte=v;end endfunction
wire [7:0] p_data=memory[slot*1536+8+index];wire [10:0] body_len=length[slot]-12;
wire p_valid=state==PARSE;wire p_ready,p_done,p_good;wire [7:0] seq_number;
wire [47:0] src_mac;wire [31:0] dst_ip,src_ip;wire [15:0] dst_port,src_port;wire [10:0] payload_length;

wire [47:0] destination_unused;
wire clock_route=SPLIT_CLOCK&&destination_unused==CLOCK_MAC;
wire protocol_admitted=p_good&&!src_mac[40]&&((packet_service&&dst_ip==32'h0a000010&&
 (((!SPLIT_CLOCK||clock_route)&&dst_port==40001&&src_ip==time_server_ip&&src_port==123)||
 ((!SPLIT_CLOCK||!clock_route)&&src_ip==loader_ip&&(dst_port==69||dst_port==41000||dst_port==40002||dst_port>=42000))))||
 (!packet_service&&dst_ip==32'hc0a80101&&src_ip==MANAGER_IP&&dst_port==161&&payload_length<=512));
wire check_ready,accept_event,duplicate_event,stale_event,out_valid;wire check_valid=state==CHECK;
afdx_eth_ipv4_udp_parser #(.MAX_PAYLOAD_BYTES(516)) parser(.clk(clk),.rst(rst),.s_data(p_data),.s_valid(p_valid),.s_ready(p_ready),.s_sof(index==0),.s_eof(index==body_len-1),.s_frame_length(body_len),
.dst_mac(destination_unused),.src_mac(src_mac),.ether_type(),.ip_total_length(),.ip_ttl(),.ip_protocol(),.ip_header_checksum(),.src_ip(src_ip),.dst_ip(dst_ip),.udp_src_port(src_port),.udp_dst_port(dst_port),.udp_length(),.udp_checksum(),.payload_length(payload_length),.padding_length(),.afdx_sequence(seq_number),.meta_valid(),.payload_data(),.payload_valid(),.payload_ready(1'b1),.payload_sof(),.payload_eof(),.frame_done(p_done),.frame_valid(p_good),.ether_type_error(),.ip_version_error(),.ip_ihl_error(),.ip_checksum_error(),.ip_protocol_error(),.ip_length_error(),.udp_length_error(),.udp_checksum_error(),.structure_error());
afdx_rx_redundancy_eliminator #(.HISTORY_TIMEOUT_CYCLES(SKEW_MAX_CYCLES)) integrity(.clk(clk),.rst_n(!rst),.clear(1'b0),.rx_valid(check_valid),.rx_ready(check_ready),.rx_network(owner),.rx_vl_id(packet_service?(clock_route?2'd2:2'd1):2'd0),.rx_seq(seq_number),.rx_payload(32'd0),
.out_valid(out_valid),.out_ready(1'b1),.out_vl_id(),.out_seq(),.out_payload(),.out_network(),.accept_event(accept_event),.duplicate_event(duplicate_event),.stale_event(stale_event),.gap_event(),.accepted_count(accepted),.accepted_a_count(),.accepted_b_count(),.duplicate_count(duplicates),.cross_network_duplicate_count(),.same_network_repeat_count(),.stale_count(),.sequence_gap_count(),.last_valid0_dbg(),.last_valid1_dbg(),.last_valid2_dbg(),.last_valid3_dbg(),.last_seq0_dbg(),.last_seq1_dbg(),.last_seq2_dbg(),.last_seq3_dbg(),.seen_mask0_dbg(),.seen_mask1_dbg(),.seen_mask2_dbg(),.seen_mask3_dbg());
assign idle=state==IDLE&&used[0]==0&&used[1]==0&&prev==0&&
 !a_valid&&!b_valid&&!management_valid&&!service_valid;
wire choice=used[0]!=0&&used[1]!=0?!rr:used[1]!=0;
always @(posedge clk)begin
 if(rst)begin
  prev<=0;bad<=0;discard<=0;state<=IDLE;owner<=0;slot<=0;rr<=1;index<=0;packet_service<=0;service_slot<=0;
  management_data<=0;service_data<=0;management_valid<=0;service_valid<=0;service_timestamp<=0;dropped<=0;push=0;pop=0;drop_inc=0;
  for(n=0;n<2;n=n+1)begin count[n]<=0;crc[n]<=32'hffffffff;destination[n]<=0;wp[n]<=0;rp[n]<=0;used[n]<=0;end
  for(n=0;n<8;n=n+1)begin length[n]<=0;timestamps[n]<=0;end
 end else begin
  management_valid<=0;service_valid<=0;prev<=inputs_valid;push=0;pop=0;drop_inc=0;
  for(n=0;n<2;n=n+1)begin
   if(inputs_valid[n])begin
    if(!prev[n])begin
     discard[n]<=used[n]==4;bad[n]<=inputs_error[n]||inputs_data[n]!=8'h55;count[n]<=1;crc[n]<=32'hffffffff;destination[n]<=0;
     if(used[n]<4)begin memory[(n*4+wp[n])*1536]<=inputs_data[n];timestamps[n*4+wp[n]]<=(DUAL_TIMESTAMPS&&n==1)?timestamp_b_now:timestamp_now;end
    end else begin
     if(count[n]<1536)begin
      if(!discard[n])memory[(n*4+wp[n])*1536+count[n]]<=inputs_data[n];count[n]<=count[n]+1'b1;
      if(count[n]>=8)crc[n]<=crcbyte(crc[n],inputs_data[n]);
      if(count[n]>=8&&count[n]<=13)destination[n]<={destination[n][39:0],inputs_data[n]};
      if(inputs_error[n]||(count[n]<7&&inputs_data[n]!=8'h55)||(count[n]==7&&inputs_data[n]!=8'hd5))bad[n]<=1;
     end else bad[n]<=1;
    end
   end else if(prev[n]&&(destination[n]==48'h030000000001||(destination[n]==SERVICE_MAC||(SPLIT_CLOCK&&destination[n]==CLOCK_MAC))))begin
    if(!discard[n]&&!bad[n]&&count[n]>=72&&crc[n]==32'hdebb20e3)begin
     length[n*4+wp[n]]<=count[n];service_slot[n*4+wp[n]]<=(destination[n]==SERVICE_MAC||(SPLIT_CLOCK&&destination[n]==CLOCK_MAC));wp[n]<=wp[n]+1'b1;push[n]=1;
    end else drop_inc=drop_inc+1'b1;
   end
  end
  case(state)
   IDLE:if(used[0]!=0||used[1]!=0)begin
    owner<=choice;slot<={choice,rp[choice]};rr<=choice;index<=0;packet_service<=service_slot[{choice,rp[choice]}];state<=PARSE;
   end
   PARSE:if(p_ready)begin if(index==body_len-1)state<=WAIT_PARSE;else index<=index+1'b1;end
   WAIT_PARSE:if(p_done)begin
    if(protocol_admitted)state<=CHECK;else begin pop[owner]=1;drop_inc=drop_inc+1'b1;state<=IDLE;end
   end
   CHECK:if(check_ready)state<=WAIT_CHECK;
   WAIT_CHECK:begin
    if(accept_event)begin index<=0;state<=REPLAY;end
    else if(duplicate_event||stale_event)begin pop[owner]=1;state<=IDLE;end
   end
   REPLAY:begin
    if(packet_service)begin service_data<=memory[slot*1536+index];service_valid<=1;service_timestamp<=timestamps[slot];end
    else begin management_data<=memory[slot*1536+index];management_valid<=1;end
    if(index==length[slot]-1)begin pop[owner]=1;state<=IDLE;end else index<=index+1'b1;
   end
  endcase
  for(n=0;n<2;n=n+1)begin
   if(pop[n])rp[n]<=rp[n]+1'b1;
   case({push[n],pop[n]})2'b10:used[n]<=used[n]+1'b1;2'b01:used[n]<=used[n]-1'b1;default:;endcase
  end
  if(drop_inc!=0)dropped<=dropped+drop_inc;
 end
end
endmodule
