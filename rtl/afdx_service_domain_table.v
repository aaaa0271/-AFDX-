`timescale 1ns/1ps
// Multi-domain service profile table used by the simulation-only AFDX service plane.
// Loader and time-server profiles are independent: each has its own VL, endpoint,
// TID, timeout/retry policy and sequence domain. Writes are shadowed until commit.
module afdx_service_domain_table #(
 parameter integer DOMAINS=8,
 // Include a representable invalid selector even for power-of-two domain counts.
 parameter integer DOMAIN_WIDTH=$clog2(DOMAINS+1)
)(
 input wire clk,input wire rst,
 input wire cfg_we,input wire [DOMAIN_WIDTH-1:0] cfg_domain,input wire cfg_kind,
 input wire [3:0] cfg_vl,input wire [7:0] cfg_sequence_domain,
 input wire [47:0] cfg_mac,input wire [31:0] cfg_ip,input wire [15:0] cfg_udp,
 input wire [15:0] cfg_tid,input wire [31:0] cfg_timeout,input wire [7:0] cfg_retry,
 input wire cfg_enable,input wire cfg_commit,
 output wire cfg_ready,output reg cfg_error,output reg commit_pulse,
 input wire select_valid,input wire select_kind,input wire [DOMAIN_WIDTH-1:0] select_domain,
 output reg selected_valid,output reg [3:0] selected_vl,output reg [7:0] selected_sequence_domain,
 output reg [47:0] selected_mac,output reg [31:0] selected_ip,output reg [15:0] selected_udp,
 output reg [15:0] selected_tid,output reg [31:0] selected_timeout,output reg [7:0] selected_retry,
 output reg [7:0] selected_sequence,input wire tx_event
);
 integer i;
 reg [3:0] sh_vl_l[0:DOMAINS-1],sh_vl_t[0:DOMAINS-1],act_vl_l[0:DOMAINS-1],act_vl_t[0:DOMAINS-1];
 reg [7:0] sh_sd_l[0:DOMAINS-1],sh_sd_t[0:DOMAINS-1],act_sd_l[0:DOMAINS-1],act_sd_t[0:DOMAINS-1];
 reg [47:0] sh_mac_l[0:DOMAINS-1],sh_mac_t[0:DOMAINS-1],act_mac_l[0:DOMAINS-1],act_mac_t[0:DOMAINS-1];
 reg [31:0] sh_ip_l[0:DOMAINS-1],sh_ip_t[0:DOMAINS-1],act_ip_l[0:DOMAINS-1],act_ip_t[0:DOMAINS-1];
 reg [15:0] sh_udp_l[0:DOMAINS-1],sh_udp_t[0:DOMAINS-1],act_udp_l[0:DOMAINS-1],act_udp_t[0:DOMAINS-1];
 reg [15:0] sh_tid_l[0:DOMAINS-1],sh_tid_t[0:DOMAINS-1],act_tid_l[0:DOMAINS-1],act_tid_t[0:DOMAINS-1];
 reg [31:0] sh_to_l[0:DOMAINS-1],sh_to_t[0:DOMAINS-1],act_to_l[0:DOMAINS-1],act_to_t[0:DOMAINS-1];
 reg [7:0] sh_retry_l[0:DOMAINS-1],sh_retry_t[0:DOMAINS-1],act_retry_l[0:DOMAINS-1],act_retry_t[0:DOMAINS-1];
 reg sh_en_l[0:DOMAINS-1],sh_en_t[0:DOMAINS-1],act_en_l[0:DOMAINS-1],act_en_t[0:DOMAINS-1];
 reg [7:0] seq_l[0:DOMAINS-1],seq_t[0:DOMAINS-1];
 reg duplicate_shadow,shadow_conflict; integer j,k,l;
 assign cfg_ready=(cfg_domain<DOMAINS)===1'b1;
 always @* begin
  duplicate_shadow=1'b0; shadow_conflict=1'b0;
  for(j=0;j<DOMAINS;j=j+1) begin
   if(j!=cfg_domain && cfg_enable) begin
    if((cfg_kind==1'b0 && sh_en_l[j] && sh_ip_l[j]==cfg_ip && sh_udp_l[j]==cfg_udp && sh_tid_l[j]==cfg_tid) ||
       (cfg_kind==1'b1 && sh_en_t[j] && sh_ip_t[j]==cfg_ip && sh_udp_t[j]==cfg_udp && sh_tid_t[j]==cfg_tid) ||
       (cfg_kind==1'b0 && sh_en_t[j] && sh_ip_t[j]==cfg_ip && sh_udp_t[j]==cfg_udp && sh_tid_t[j]==cfg_tid) ||
       (cfg_kind==1'b1 && sh_en_l[j] && sh_ip_l[j]==cfg_ip && sh_udp_l[j]==cfg_udp && sh_tid_l[j]==cfg_tid)) duplicate_shadow=1'b1;
   end
  end
  for(k=0;k<DOMAINS;k=k+1) begin
   for(l=k+1;l<DOMAINS;l=l+1) begin
    if(sh_en_l[k] && sh_en_l[l] && sh_ip_l[k]==sh_ip_l[l] && sh_udp_l[k]==sh_udp_l[l] && sh_tid_l[k]==sh_tid_l[l]) shadow_conflict=1'b1;
    if(sh_en_t[k] && sh_en_t[l] && sh_ip_t[k]==sh_ip_t[l] && sh_udp_t[k]==sh_udp_t[l] && sh_tid_t[k]==sh_tid_t[l]) shadow_conflict=1'b1;
    if(sh_en_l[k] && sh_en_t[l] && sh_ip_l[k]==sh_ip_t[l] && sh_udp_l[k]==sh_udp_t[l] && sh_tid_l[k]==sh_tid_t[l]) shadow_conflict=1'b1;
    if(sh_en_t[k] && sh_en_l[l] && sh_ip_t[k]==sh_ip_l[l] && sh_udp_t[k]==sh_udp_l[l] && sh_tid_t[k]==sh_tid_l[l]) shadow_conflict=1'b1;
   end
  end
 end
 always @* begin
  selected_valid=1'b0;selected_vl=0;selected_sequence_domain=0;selected_mac=0;selected_ip=0;selected_udp=0;selected_tid=0;selected_timeout=0;selected_retry=0;selected_sequence=0;
  if(select_valid && select_domain<DOMAINS) begin
   if(!select_kind) begin selected_valid=act_en_l[select_domain];selected_vl=act_vl_l[select_domain];selected_sequence_domain=act_sd_l[select_domain];selected_mac=act_mac_l[select_domain];selected_ip=act_ip_l[select_domain];selected_udp=act_udp_l[select_domain];selected_tid=act_tid_l[select_domain];selected_timeout=act_to_l[select_domain];selected_retry=act_retry_l[select_domain];selected_sequence=seq_l[select_domain];end
   else begin selected_valid=act_en_t[select_domain];selected_vl=act_vl_t[select_domain];selected_sequence_domain=act_sd_t[select_domain];selected_mac=act_mac_t[select_domain];selected_ip=act_ip_t[select_domain];selected_udp=act_udp_t[select_domain];selected_tid=act_tid_t[select_domain];selected_timeout=act_to_t[select_domain];selected_retry=act_retry_t[select_domain];selected_sequence=seq_t[select_domain];end
  end
 end
 always @(posedge clk) begin
  if(rst) begin
   cfg_error<=0;commit_pulse<=0;
   for(i=0;i<DOMAINS;i=i+1) begin
    sh_vl_l[i]<=0;sh_vl_t[i]<=0;act_vl_l[i]<=0;act_vl_t[i]<=0;sh_sd_l[i]<=0;sh_sd_t[i]<=0;act_sd_l[i]<=0;act_sd_t[i]<=0;sh_mac_l[i]<=0;sh_mac_t[i]<=0;act_mac_l[i]<=0;act_mac_t[i]<=0;sh_ip_l[i]<=0;sh_ip_t[i]<=0;act_ip_l[i]<=0;act_ip_t[i]<=0;sh_udp_l[i]<=0;sh_udp_t[i]<=0;act_udp_l[i]<=0;act_udp_t[i]<=0;sh_tid_l[i]<=0;sh_tid_t[i]<=0;act_tid_l[i]<=0;act_tid_t[i]<=0;sh_to_l[i]<=0;sh_to_t[i]<=0;act_to_l[i]<=0;act_to_t[i]<=0;sh_retry_l[i]<=0;sh_retry_t[i]<=0;act_retry_l[i]<=0;act_retry_t[i]<=0;sh_en_l[i]<=0;sh_en_t[i]<=0;act_en_l[i]<=0;act_en_t[i]<=0;seq_l[i]<=0;seq_t[i]<=0;
   end
  end else begin
   cfg_error<=0;commit_pulse<=0;
   if(cfg_we) begin
    if(!cfg_ready || duplicate_shadow) cfg_error<=1;
    else if(!cfg_kind) begin sh_vl_l[cfg_domain]<=cfg_vl;sh_sd_l[cfg_domain]<=cfg_sequence_domain;sh_mac_l[cfg_domain]<=cfg_mac;sh_ip_l[cfg_domain]<=cfg_ip;sh_udp_l[cfg_domain]<=cfg_udp;sh_tid_l[cfg_domain]<=cfg_tid;sh_to_l[cfg_domain]<=cfg_timeout;sh_retry_l[cfg_domain]<=cfg_retry;sh_en_l[cfg_domain]<=cfg_enable;end
    else begin sh_vl_t[cfg_domain]<=cfg_vl;sh_sd_t[cfg_domain]<=cfg_sequence_domain;sh_mac_t[cfg_domain]<=cfg_mac;sh_ip_t[cfg_domain]<=cfg_ip;sh_udp_t[cfg_domain]<=cfg_udp;sh_tid_t[cfg_domain]<=cfg_tid;sh_to_t[cfg_domain]<=cfg_timeout;sh_retry_t[cfg_domain]<=cfg_retry;sh_en_t[cfg_domain]<=cfg_enable;end
   end
   if(cfg_commit) begin
    if(shadow_conflict) cfg_error<=1;
    else begin
     for(i=0;i<DOMAINS;i=i+1) begin act_vl_l[i]<=sh_vl_l[i];act_vl_t[i]<=sh_vl_t[i];act_sd_l[i]<=sh_sd_l[i];act_sd_t[i]<=sh_sd_t[i];act_mac_l[i]<=sh_mac_l[i];act_mac_t[i]<=sh_mac_t[i];act_ip_l[i]<=sh_ip_l[i];act_ip_t[i]<=sh_ip_t[i];act_udp_l[i]<=sh_udp_l[i];act_udp_t[i]<=sh_udp_t[i];act_tid_l[i]<=sh_tid_l[i];act_tid_t[i]<=sh_tid_t[i];act_to_l[i]<=sh_to_l[i];act_to_t[i]<=sh_to_t[i];act_retry_l[i]<=sh_retry_l[i];act_retry_t[i]<=sh_retry_t[i];act_en_l[i]<=sh_en_l[i];act_en_t[i]<=sh_en_t[i];end
     commit_pulse<=1;
    end
   end
   if(tx_event && select_valid && select_domain<DOMAINS && selected_valid) begin
    if(!select_kind) seq_l[select_domain] <= (seq_l[select_domain] == 8'hff) ? 8'h01 : seq_l[select_domain]+1'b1;
    else seq_t[select_domain] <= (seq_t[select_domain] == 8'hff) ? 8'h01 : seq_t[select_domain]+1'b1;
   end
  end
 end
endmodule

// Runtime endpoint bank for the production service plane. Lane zero is in the
// least significant slice. A commit locks the shadow bank until safe_to_commit;
// writes/another commit while pending and write+commit collisions are rejected.
module afdx_service_domain_config #(
 parameter integer DOMAINS=1,DOMAIN_WIDTH=$clog2(DOMAINS+1)
)(
 input wire clk,rst,
 input wire [DOMAINS*32-1:0] initial_loader_ips,initial_clock_ips,
 input wire cfg_we,input wire [DOMAIN_WIDTH-1:0] cfg_domain,
 input wire [31:0] cfg_loader_ip,cfg_clock_ip,input wire cfg_enable,cfg_commit,
 output wire cfg_ready,output reg cfg_error,output reg cfg_pending,commit_pulse,
 input wire safe_to_commit,output wire commit_apply,
 output wire [DOMAINS-1:0] changed,
 output reg [DOMAINS*32-1:0] loader_ips,clock_ips,
 output reg [DOMAINS-1:0] enabled
);
 reg [DOMAINS*32-1:0] shadow_loader,shadow_clock;
 reg [DOMAINS-1:0] shadow_enabled;
 wire write_request=cfg_we===1'b1;
 wire commit_request=cfg_commit===1'b1;
 wire valid_domain=(cfg_domain<DOMAINS)===1'b1;
 assign cfg_ready=!rst&&!cfg_pending&&!commit_request&&valid_domain;
 assign commit_apply=!rst&&cfg_pending&&safe_to_commit;
 genvar d;
 generate for(d=0;d<DOMAINS;d=d+1)begin:CHANGED
  assign changed[d]=shadow_loader[d*32+:32]!=loader_ips[d*32+:32] ||
   shadow_clock[d*32+:32]!=clock_ips[d*32+:32] || shadow_enabled[d]!=enabled[d];
 end endgenerate
 always @(posedge clk)begin
  if(rst)begin
   loader_ips<=initial_loader_ips;clock_ips<=initial_clock_ips;enabled<={DOMAINS{1'b1}};
   shadow_loader<=initial_loader_ips;shadow_clock<=initial_clock_ips;shadow_enabled<={DOMAINS{1'b1}};
   cfg_error<=0;cfg_pending<=0;commit_pulse<=0;
  end else begin
   cfg_error<=0;commit_pulse<=0;
   if(write_request||commit_request)begin
    if(cfg_pending||(write_request&&commit_request)||(write_request&&!valid_domain))cfg_error<=1;
    else if(write_request)begin
     shadow_loader[cfg_domain*32+:32]<=cfg_loader_ip;
     shadow_clock[cfg_domain*32+:32]<=cfg_clock_ip;
     shadow_enabled[cfg_domain]<=cfg_enable;
    end else cfg_pending<=1;
   end
   if(commit_apply)begin
    loader_ips<=shadow_loader;clock_ips<=shadow_clock;enabled<=shadow_enabled;
    cfg_pending<=0;commit_pulse<=1;
   end
  end
 end
endmodule
