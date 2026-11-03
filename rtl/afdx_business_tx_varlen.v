`timescale 1ns/1ps
// M6 business TX: byte-stream ingress, two complete frames per VL, four VLs.
// A slot is not released until its entire redundant transmission and IFG finish.
module afdx_business_tx_varlen #(
    parameter integer MAX_PAYLOAD_BYTES=1471,
    parameter integer CONFIGURABLE_NETWORK=0
)(
 input wire [671:0] network_cfg,
 input wire clk,rst,tx_enable,network_a_enable,network_b_enable,
 input wire cfg_we,input wire [1:0] cfg_vl_id,
 input wire [31:0] cfg_bag,input wire [15:0] cfg_lmax,input wire [7:0] cfg_destination,
 input wire app_wr_en,input wire [1:0] app_wr_vl_id,input wire [7:0] app_wr_data,
 input wire [15:0] app_wr_len,input wire app_wr_sof,app_wr_eof,
 output wire app_wr_ready,app_wr_accept,output reg app_len_error,
 output wire [7:0] gmii_a_txd,gmii_b_txd,
 output wire gmii_a_tx_en,gmii_b_tx_en,gmii_a_tx_er,gmii_b_tx_er,
 output wire gmii_a_frame_done,gmii_b_frame_done,gmii_a_underrun,gmii_b_underrun,
 output wire network_a_active,network_b_active,degraded_mode,
 output wire busy,output reg frame_start,output reg [1:0] selected_vl,
 output reg [7:0] selected_seq
);
reg [7:0] memory [0:16383]; // 4 VL x 2 slots x 2048 bytes; no reset on payload RAM
reg [10:0] lengths [0:7];reg [7:0] destinations [0:7];
reg [1:0] count [0:3];reg [3:0] wp=0,rp=0,enabled=0;
reg [31:0] bag_cfg[0:3],bag_left[0:3];reg [15:0] lmax_cfg[0:3];reg [7:0] dest_cfg[0:3],seq[0:3];
reg capture=0;reg [1:0] cap_vl;reg cap_slot;reg [10:0] cap_len,cap_index;reg [7:0] cap_destination;
function [15:0] frame_bytes;input [15:0] n;begin frame_bytes=n<=17?16'd64:n+16'd47;end endfunction
wire length_ok=app_wr_len>=1 && app_wr_len<=MAX_PAYLOAD_BYTES &&
               lmax_cfg[app_wr_vl_id]>=64 && lmax_cfg[app_wr_vl_id]<=1518 &&
               frame_bytes(app_wr_len)<=lmax_cfg[app_wr_vl_id];
assign app_wr_ready=!rst && (capture || (app_wr_sof && enabled[app_wr_vl_id] && count[app_wr_vl_id]<2 && length_ok));
assign app_wr_accept=app_wr_en && app_wr_ready;
wire cap_bad=capture && (app_wr_sof || app_wr_vl_id!=cap_vl);
wire final_byte=capture ? cap_index==cap_len-1'b1 : app_wr_len==1;
wire enqueue=app_wr_accept && !cap_bad && app_wr_eof && final_byte;
wire [1:0] enqueue_vl=capture?cap_vl:app_wr_vl_id;
wire enqueue_slot=capture?cap_slot:wp[app_wr_vl_id];
wire [13:0] wr_address=capture?{cap_vl,cap_slot,cap_index}:{app_wr_vl_id,wp[app_wr_vl_id],11'd0};
// RAM write is gated by the accepted ingress handshake, including backpressure.
always @(posedge clk) if(app_wr_accept && !cap_bad) memory[wr_address]<=app_wr_data;
localparam IDLE=0,BODY=1,WAIT_FCS=2,IFG=3;
reg [1:0] state=IDLE,rr=3;reg [3:0] ifg_left;reg active_a,active_b;
reg [10:0] tx_length,body_index,seq_index;reg tx_slot;reg [7:0] destination;
reg [47:0] tx_dst_mac;reg [31:0] tx_src_ip,tx_dst_ip;reg [15:0] tx_src_port,tx_dst_port;
reg [7:0] read_data;reg choose_valid;reg [1:0] choice;integer i,j;
reg [1:0] probe;
always @* begin
 choose_valid=0;choice=0;probe=0;
 for(j=1;j<=4;j=j+1) begin
  probe=rr+j;
  if(!choose_valid && count[probe]!=0 && enabled[probe] && bag_left[probe]==0)begin choose_valid=1;choice=probe;end
 end
end
wire launch=state==IDLE && tx_enable && (network_a_enable||network_b_enable) && choose_valid;
wire dequeue=state==IFG && ifg_left==0;
wire [2:0] head={choice,rp[choice]};
wire a_ready,b_ready;
wire body_ready=(!active_a||a_ready) && (!active_b||b_ready);
wire body_valid=state==BODY;
wire body_eof=body_index==seq_index;
// Registered payload RAM read. Header byte 41 prefetches payload byte zero;
// each accepted payload beat fetches the next byte. A stall holds read_data.
wire [10:0] read_index=(body_index>=41 && body_index<41+tx_length)?body_index-11'd41:11'd0;
always @(posedge clk) if(body_valid && body_ready)
 read_data<=memory[{selected_vl,tx_slot,read_index}];
wire [31:0] dst_ip=CONFIGURABLE_NETWORK?tx_dst_ip:{24'h0a0000,destination};
wire [31:0] src_ip=CONFIGURABLE_NETWORK?tx_src_ip:32'h0a000001;
wire [15:0] dst_port=CONFIGURABLE_NETWORK?tx_dst_port:(destination==2?16'd10001:(destination==3?16'd20001:16'd20000+destination));
wire [15:0] ip_length=16'd28+tx_length;
wire [15:0] udp_length=16'd8+tx_length;
wire [15:0] ip_checksum;
ipv4_checksum u_checksum(.src_ip(src_ip),.dst_ip(dst_ip),.total_length(ip_length),.checksum(ip_checksum));
reg [7:0] body_data;
always @* begin
 body_data=0;
 case(body_index)
  0,6:body_data=2;5:body_data=destination;11:body_data=1;
  12:body_data=8'h08;14:body_data=8'h45;
  16:body_data=ip_length[15:8];17:body_data=ip_length[7:0];
  22:body_data=64;23:body_data=17;24:body_data=ip_checksum[15:8];25:body_data=ip_checksum[7:0];
  26,30:body_data=10;29:body_data=1;33:body_data=destination;
  34:body_data=8'h27;35:body_data=8'h10;
  36:body_data=dst_port[15:8];37:body_data=dst_port[7:0];
  38:body_data=udp_length[15:8];39:body_data=udp_length[7:0];
  default:if(body_index>=42 && body_index<42+tx_length)body_data=read_data;
 endcase
 if(CONFIGURABLE_NETWORK)begin
  case(body_index)
   0:body_data=tx_dst_mac[47:40];1:body_data=tx_dst_mac[39:32];2:body_data=tx_dst_mac[31:24];
   3:body_data=tx_dst_mac[23:16];4:body_data=tx_dst_mac[15:8];5:body_data=tx_dst_mac[7:0];
   26:body_data=tx_src_ip[31:24];27:body_data=tx_src_ip[23:16];28:body_data=tx_src_ip[15:8];29:body_data=tx_src_ip[7:0];
   30:body_data=tx_dst_ip[31:24];31:body_data=tx_dst_ip[23:16];32:body_data=tx_dst_ip[15:8];33:body_data=tx_dst_ip[7:0];
   34:body_data=tx_src_port[15:8];35:body_data=tx_src_port[7:0];default:;
  endcase
 end
 if(body_eof)body_data=selected_seq;
end
gmii_tx_adapter_varlen u_a(.clk(clk),.rst(rst),.s_data(body_data),.s_valid(body_valid&&active_a),.s_eof(body_eof),.s_ready(a_ready),
.gmii_txd(gmii_a_txd),.gmii_tx_en(gmii_a_tx_en),.gmii_tx_er(gmii_a_tx_er),.frame_done(gmii_a_frame_done),.underrun(gmii_a_underrun));
gmii_tx_adapter_varlen u_b(.clk(clk),.rst(rst),.s_data(body_data),.s_valid(body_valid&&active_b),.s_eof(body_eof),.s_ready(b_ready),
.gmii_txd(gmii_b_txd),.gmii_tx_en(gmii_b_tx_en),.gmii_tx_er(gmii_b_tx_er),.frame_done(gmii_b_frame_done),.underrun(gmii_b_underrun));
assign busy=state!=IDLE;
assign network_a_active=busy?active_a:network_a_enable;
assign network_b_active=busy?active_b:network_b_enable;
assign degraded_mode=network_a_active^network_b_active;
always @(posedge clk) begin
 if(rst)begin
  tx_dst_mac<=0;tx_src_ip<=0;tx_dst_ip<=0;tx_src_port<=0;tx_dst_port<=0;
  capture<=0;cap_vl<=0;cap_slot<=0;cap_len<=0;cap_index<=0;cap_destination<=0;
  wp<=0;rp<=0;enabled<=0;app_len_error<=0;state<=IDLE;rr<=3;ifg_left<=0;
  active_a<=0;active_b<=0;selected_vl<=0;selected_seq<=0;tx_slot<=0;tx_length<=0;destination<=0;body_index<=0;seq_index<=0;frame_start<=0;
  for(i=0;i<4;i=i+1)begin count[i]<=0;seq[i]<=0;bag_cfg[i]<=0;bag_left[i]<=0;lmax_cfg[i]<=0;dest_cfg[i]<=0;end
  for(i=0;i<8;i=i+1)begin lengths[i]<=0;destinations[i]<=0;end
 end else begin
  app_len_error<=0;frame_start<=0;
  if(cfg_we)begin enabled[cfg_vl_id]<=1;bag_cfg[cfg_vl_id]<=cfg_bag;lmax_cfg[cfg_vl_id]<=cfg_lmax;dest_cfg[cfg_vl_id]<=cfg_destination;end
  for(i=0;i<4;i=i+1)begin
   if(bag_left[i]!=0)bag_left[i]<=bag_left[i]-1'b1;
   case({enqueue&&enqueue_vl==i,dequeue&&selected_vl==i})
    2'b10:count[i]<=count[i]+1'b1;
    2'b01:count[i]<=count[i]-1'b1;
    default:;
   endcase
  end
  if(app_wr_en && !capture && app_wr_sof && !length_ok)app_len_error<=1;
  if(app_wr_accept)begin
   if(cap_bad || app_wr_eof!=final_byte)begin
    // A missing early EOF is not an error unless the declared final byte
    // has actually arrived; otherwise capture continues below.
    if(cap_bad || app_wr_eof || final_byte)begin capture<=0;app_len_error<=1;end
    else begin
     if(!capture)begin capture<=1;cap_vl<=app_wr_vl_id;cap_slot<=wp[app_wr_vl_id];cap_len<=app_wr_len[10:0];cap_index<=1;cap_destination<=dest_cfg[app_wr_vl_id];end
     else cap_index<=cap_index+1'b1;
    end
   end else if(final_byte)capture<=0;
   else if(!capture)begin capture<=1;cap_vl<=app_wr_vl_id;cap_slot<=wp[app_wr_vl_id];cap_len<=app_wr_len[10:0];cap_index<=1;cap_destination<=dest_cfg[app_wr_vl_id];end
   else cap_index<=cap_index+1'b1;
  end
  if(enqueue)begin
   lengths[{enqueue_vl,enqueue_slot}]<=capture?cap_len:app_wr_len[10:0];
   destinations[{enqueue_vl,enqueue_slot}]<=capture?cap_destination:dest_cfg[app_wr_vl_id];wp[enqueue_vl]<=!wp[enqueue_vl];
  end
  case(state)
   IDLE:if(launch)begin
    tx_dst_mac<=network_cfg[choice*168+8+:48];tx_src_ip<=network_cfg[choice*168+56+:32];tx_dst_ip<=network_cfg[choice*168+88+:32];
    tx_src_port<=network_cfg[choice*168+120+:16];tx_dst_port<=network_cfg[choice*168+136+:16];
    selected_vl<=choice;selected_seq<=seq[choice];seq[choice]<=seq[choice]==255?8'd1:seq[choice]+1'b1;
    tx_length<=lengths[head];destination<=destinations[head];tx_slot<=rp[choice];
    seq_index<=lengths[head]<=17?11'd59:11'd42+lengths[head];body_index<=0;
    active_a<=network_a_enable;active_b<=network_b_enable;rr<=choice;frame_start<=1;
    bag_left[choice]<=bag_cfg[choice]>0?bag_cfg[choice]-1'b1:0;state<=BODY;
   end
   BODY:if(body_ready)begin if(body_eof)state<=WAIT_FCS;else body_index<=body_index+1'b1;end
   WAIT_FCS:if((!active_a||gmii_a_frame_done)&&(!active_b||gmii_b_frame_done))begin state<=IFG;ifg_left<=12;end
   IFG:if(ifg_left!=0)ifg_left<=ifg_left-1'b1;else begin rp[selected_vl]<=!rp[selected_vl];state<=IDLE;end
  endcase
 end
end
endmodule
