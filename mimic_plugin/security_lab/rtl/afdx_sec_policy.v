`timescale 1ns/1ps
// Trusted local control plane. Signature verification is performed by the
// accompanying host authorizer before grant words are written here.
module afdx_sec_policy #(parameter integer RULES=16,GRANTS=16,BOOT_MODE=2)(
 input wire clk,rst,safe,input wire write,read,input wire [15:0] address,input wire [31:0] wdata,
 output wire ready,output reg error,pending,commit_pulse,output reg [31:0] rdata,
 output reg [1:0] mode,output reg [31:0] epoch,ab_window,ntp_rtt_limit,
 output reg [63:0] time_jump_limit,
 output reg [RULES*512-1:0] rules,output reg [GRANTS*1024-1:0] grants,
 output reg [RULES*32-1:0] floors,output reg [RULES-1:0] floor_loaded,
 output reg [63:0] committed_at,input wire [63:0] cycle
);
reg [RULES*512-1:0] shadow_rules,previous_rules;
reg [GRANTS*1024-1:0] shadow_grants;
reg [1:0] shadow_mode,previous_mode;
reg [31:0] shadow_window,shadow_rtt,previous_window,previous_rtt;
reg [63:0] shadow_jump,previous_jump;reg rollback,previous_valid;
integer i,k,word_index,rule_index;reg invalid;
assign ready=!rst&&!pending;
always @*begin
 rule_index=0;invalid=shadow_mode>2||shadow_window==0||shadow_rtt==0;
 for(i=0;i<RULES;i=i+1)if(shadow_rules[i*512])begin
  if(shadow_rules[i*512+2+:3]>3||shadow_rules[i*512+9*32+:16]<64||shadow_rules[i*512+9*32+:16]>1518||shadow_rules[i*512+11*32+:32]==0||shadow_rules[i*512+10*32+:8]>16||shadow_rules[i*512+15*32+16+:16]!=0)invalid=1;
 end
 for(i=0;i<GRANTS;i=i+1)if(shadow_grants[i*1024])begin
  rule_index=shadow_grants[i*1024+4+:4];
  if(shadow_grants[i*1024+16+:6]==0||shadow_grants[i*1024+16+:6]>32||shadow_grants[i*1024+2*32+:32]>4096||shadow_grants[i*1024+3*32+:32]==0||!floor_loaded[rule_index]||shadow_grants[i*1024+32+:32]<floors[rule_index*32+:32])invalid=1;
 end
 rdata=0;
 if(address==0)rdata={30'd0,mode};
 if(address==4)rdata={29'd0,previous_valid,pending,ready};
 if(address==8)rdata=epoch;
 if(address==12)rdata=ab_window;
 if(address==24)rdata=time_jump_limit[31:0];
 if(address==28)rdata=time_jump_limit[63:32];
 if(address==32)rdata=ntp_rtt_limit;
 if(address>=16'h80&&address<16'h80+RULES*4)rdata=floors[((address-16'h80)>>2)*32+:32];
 if(address>=16'h100&&address<16'h100+RULES*64)rdata=rules[((address-16'h100)>>2)*32+:32];
 if(address>=16'h1000&&address<16'h1000+GRANTS*128)rdata=grants[((address-16'h1000)>>2)*32+:32];
end
always @(posedge clk)begin
 if(rst)begin mode<=BOOT_MODE;epoch<=0;ab_window<=1250000;ntp_rtt_limit<=12500000;time_jump_limit<=64'h0000000200000000;rules<=0;grants<=0;floors<=0;floor_loaded<=0;shadow_rules<=0;shadow_grants<=0;shadow_mode<=BOOT_MODE;shadow_window<=1250000;shadow_rtt<=12500000;shadow_jump<=64'h0000000200000000;previous_rules<=0;previous_mode<=0;previous_window<=1250000;previous_rtt<=12500000;previous_jump<=64'h0000000200000000;previous_valid<=0;rollback<=0;pending<=0;error<=0;commit_pulse<=0;committed_at<=0;end
 else begin
  error<=0;commit_pulse<=0;
  if(write)begin
   if(!ready||address[1:0]!=0)error<=1;
   else if(address==0)begin if(wdata>2)error<=1;else shadow_mode<=wdata[1:0];end
   else if(address==12)shadow_window<=wdata;
   else if(address==24)shadow_jump[31:0]<=wdata;
   else if(address==28)shadow_jump[63:32]<=wdata;
   else if(address==32)shadow_rtt<=wdata;
   else if(address==16)begin if(wdata!=32'h53454331||invalid)error<=1;else begin pending<=1;rollback<=0;end end
   else if(address==20)begin if(wdata!=32'h524f4c4c||!previous_valid)error<=1;else begin pending<=1;rollback<=1;end end
   else if(address>=16'h80&&address<16'h80+RULES*4)begin
    word_index=(address-16'h80)>>2;
    if(wdata<floors[word_index*32+:32])error<=1;else begin floors[word_index*32+:32]<=wdata;floor_loaded[word_index]<=1;end
   end else if(address>=16'h100&&address<16'h100+RULES*64)shadow_rules[((address-16'h100)>>2)*32+:32]<=wdata;
   else if(address>=16'h1000&&address<16'h1000+GRANTS*128)shadow_grants[((address-16'h1000)>>2)*32+:32]<=wdata;
   else error<=1;
  end
  if(pending&&safe)begin
   previous_rules<=rules;previous_mode<=mode;previous_window<=ab_window;previous_rtt<=ntp_rtt_limit;previous_jump<=time_jump_limit;previous_valid<=1;
   if(rollback)begin rules<=previous_rules;mode<=previous_mode;ab_window<=previous_window;ntp_rtt_limit<=previous_rtt;time_jump_limit<=previous_jump;grants<=0;shadow_grants<=0;shadow_rules<=previous_rules;shadow_mode<=previous_mode;shadow_window<=previous_window;shadow_rtt<=previous_rtt;shadow_jump<=previous_jump;end
   else begin rules<=shadow_rules;mode<=shadow_mode;ab_window<=shadow_window;ntp_rtt_limit<=shadow_rtt;time_jump_limit<=shadow_jump;grants<=shadow_grants;end
   epoch<=epoch+1'b1;committed_at<=cycle;pending<=0;commit_pulse<=1;
  end
 end
end
endmodule
