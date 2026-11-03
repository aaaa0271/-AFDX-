`timescale 1ns/1ps
// Bounded AFDX receive security engine. TX taps learn sessions but never gate
// the core's transmitter. Packets are complete, CRC-checked queue records.
module afdx_sec_engine #(
 parameter integer MAX_WIRE=1536,RULES=16,GRANTS=16,CONTEXTS=8,HISTORY=16,MAX_FILE=4096,MAX_DATAGRAM=8200,CLK_HZ=12500000
)(
 input wire clk,rst,clear,input wire [1:0] mode,
 input wire [RULES*512-1:0] rules,input wire [GRANTS*1024-1:0] grants,
 input wire [RULES*32-1:0] floors,input wire [RULES-1:0] floor_loaded,
 input wire [31:0] epoch,ab_window,ntp_rtt_limit,input wire [63:0] committed_at,time_jump_limit,cycle,
 input wire [255:0] target_id,input wire [3:0] requests,goods,
 input wire [4*MAX_WIRE*8-1:0] packets,input wire [43:0] lengths,input wire [255:0] stamps,
 output reg [3:0] take,output reg [1:0] replay_start,
 output reg [MAX_WIRE*8-1:0] replay_packet,output reg [10:0] replay_length,input wire [1:0] replay_ready,
 output wire idle,sessions_idle,output reg event_push,output reg [159:0] event_record,
 input wire evidence_ack,output reg evidence_valid,
 output reg [MAX_WIRE*8-1:0] evidence_first,evidence_second,
 output reg [10:0] evidence_first_length,evidence_second_length,
 output reg [15:0] evidence_offset,output reg [63:0] evidence_first_stamp,evidence_second_stamp,
 output reg [31:0] evidence_lost,evidence_epoch,output reg [3:0] evidence_rule,
 output reg [1:0] evidence_channel,
 output reg [31:0] accepted,blocked,observed,ab_conflicts,hash_failures,context_timeouts
);
localparam F_FORMAT=16'h0001,F_ACL=16'h0002,F_AB=16'h0004,F_PHASE=16'h0008,F_RATE=16'h0010,F_QUOTA=16'h0020,F_AUTH=16'h0040,F_TID=16'h0080,F_TIME=16'h0100,F_ORPHAN=16'h0200,F_HASH=16'h0400,F_OVERLAP=16'h0800;
localparam IDLE=0,HEADER=1,L4SUM=2,MATCH_RULE=3,AB_FIND=4,AB_COMPARE=5,PROTOCOL=6,COPY_DATA=7,HASH_START=8,HASH_WAIT=9,DECIDE=10,RETIRE=11;
reg [3:0] state;reg [1:0] channel,last_channel;
reg [MAX_WIRE*8-1:0] packet_q;reg [10:0] len_q;reg good_q;
reg [63:0] stamp_q;reg [15:0] history_flags[0:HISTORY-1];integer inserted_history;
reg [15:0] flags;reg duplicate,permit;reg [3:0] rule_q;reg rule_found;
reg [15:0] ip_len,udp_len,sp,dp,ip_id,fragment;reg [31:0] sip,dip;reg [47:0] dm,sm;
reg [7:0] sn,kind;reg [31:0] udp_sum;integer sum_index;
reg [31:0] last_rx[0:RULES-1],window_start[0:RULES-1],window_count[0:RULES-1];reg [RULES-1:0] last_rx_valid;
reg [2:0] phase[0:RULES-1];reg [31:0] phase_stamp[0:RULES-1];reg [15:0] control_tid[0:RULES-1],report_tid[0:RULES-1];reg [RULES-1:0] final_report;
reg [63:0] ntp_origin[0:RULES-1],ntp_stamp[0:RULES-1];reg [15:0] ntp_port[0:RULES-1];reg [RULES-1:0] ntp_waiting,ntp_established;
reg [MAX_WIRE*8-1:0] history_data[0:HISTORY-1];reg [10:0] history_len[0:HISTORY-1];reg [1:0] history_channel[0:HISTORY-1];reg [63:0] history_stamp[0:HISTORY-1];reg history_valid[0:HISTORY-1];integer history_next,history_match,compare_index;
reg ctx_valid[0:CONTEXTS-1],ctx_complete[0:CONTEXTS-1],ctx_auth[0:CONTEXTS-1];
reg [3:0] ctx_rule[0:CONTEXTS-1];reg [15:0] ctx_tid[0:CONTEXTS-1],ctx_peer[0:CONTEXTS-1],ctx_next[0:CONTEXTS-1],ctx_length[0:CONTEXTS-1],ctx_last_n[0:CONTEXTS-1];
reg [63:0] ctx_expiry[0:CONTEXTS-1];reg [255:0] ctx_target[0:CONTEXTS-1];
reg [31:0] ctx_stamp[0:CONTEXTS-1],ctx_version[0:CONTEXTS-1];reg [255:0] ctx_digest[0:CONTEXTS-1],ctx_name[0:CONTEXTS-1];reg [5:0] ctx_name_len[0:CONTEXTS-1];
reg [15:0] ctx_expected[0:CONTEXTS-1];reg [7:0] file_memory[0:CONTEXTS*MAX_FILE-1];
// Fragment reservations are distinct from file-transfer contexts.
reg frag_valid[0:CONTEXTS-1];reg [3:0] frag_rule[0:CONTEXTS-1];reg [15:0] frag_id[0:CONTEXTS-1],frag_next[0:CONTEXTS-1];reg [31:0] frag_stamp[0:CONTEXTS-1];
integer expire_count,context_rule;integer i,j,k,pick,probe,chosen_rule,slot,free_slot,active_count,grant_slot,name_n,data_n,copy_index,crypto_ctx;reg same,any_session;
reg [255:0] name_q,expected_hash;reg [31:0] folded,limit;reg [15:0] opcode,block_q;
reg copy_duplicate;reg [63:0] origin_q,receive_q,transmit_q,abs_difference;
wire [15:0] sha_address;wire [7:0] sha_data=sha_address<MAX_FILE?file_memory[crypto_ctx*MAX_FILE+sha_address]:0;
reg sha_start;wire sha_busy,sha_done;wire [255:0] sha_digest;
afdx_sec_sha256 sha(.clk(clk),.rst(rst),.start(sha_start),.length(ctx_length[crypto_ctx]),.address(sha_address),.data(sha_data),.busy(sha_busy),.done(sha_done),.digest(sha_digest));
assign idle=state==IDLE;
always @*begin
 any_session=0;
 for(k=0;k<CONTEXTS;k=k+1)if((ctx_valid[k]&&!ctx_complete[k])||frag_valid[k])any_session=1;
 for(k=0;k<RULES;k=k+1)if((phase[k]!=0&&phase[k]!=5)||ntp_waiting[k])any_session=1;
end
assign sessions_idle=!any_session;
function [7:0] b;input integer offset;begin b=offset>=0&&offset<MAX_WIRE?packet_q[offset*8+:8]:0;end endfunction
function [15:0] u16;input integer offset;begin u16={b(offset),b(offset+1)};end endfunction
function [31:0] u32;input integer offset;begin u32={b(offset),b(offset+1),b(offset+2),b(offset+3)};end endfunction
function [63:0] u64;input integer offset;begin u64={u32(offset),u32(offset+4)};end endfunction
function [31:0] rw;input integer rule_id,word_id;begin rw=rules[(rule_id*16+word_id)*32+:32];end endfunction
function [31:0] gw;input integer grant_id,word_id;begin gw=grants[(grant_id*32+word_id)*32+:32];end endfunction
function [31:0] rb;input integer r,w,lsb,width;reg [31:0] v;begin v=rw(r,w)>>lsb;rb=v&((64'd1<<width)-1);end endfunction
function [31:0] gb;input integer r,w,lsb,width;reg [31:0] v;begin v=gw(r,w)>>lsb;gb=v&((64'd1<<width)-1);end endfunction
function [7:0] bb;input integer o,lsb,width;begin bb=(b(o)>>lsb)&((16'd1<<width)-1);end endfunction
function match_key;input integer h;integer q;reg equal_q;begin
 equal_q=history_valid[h]&&history_channel[h][1]==channel[1]&&history_channel[h][0]!=channel[0]&&(stamp_q>=history_stamp[h]?stamp_q-history_stamp[h]:history_stamp[h]-stamp_q)<=ab_window;
 // Logical key: VL, source identity except physical Interface_ID, IPv4 tuple,
 // ID/fragment, and AFDX SN. Compare content separately, never by CRC alone.
 for(q=8;q<19;q=q+1)if(history_data[h][q*8+:8]!=b(q))equal_q=0;
 for(q=26;q<30;q=q+1)if(history_data[h][q*8+:8]!=b(q))equal_q=0;
 for(q=34;q<42;q=q+1)if(history_data[h][q*8+:8]!=b(q))equal_q=0;
 if((history_data[h][19*8+:8]&8'h9f)!=(b(19)&8'h9f))equal_q=0;
 if(history_data[h][(history_len[h]-5)*8+:8]!=sn)equal_q=0;
 match_key=equal_q;
end endfunction
function is_suffix;input [23:0] suffix;begin is_suffix=name_n>=3&&name_q[(name_n-3)*8+:8]==suffix[23:16]&&name_q[(name_n-2)*8+:8]==suffix[15:8]&&name_q[(name_n-1)*8+:8]==suffix[7:0];end endfunction
// First outstanding conflict remains frozen until the trusted consumer acknowledges.
task capture_conflict;input [15:0] offset;begin
 if(!evidence_valid||evidence_ack)begin
  evidence_valid<=1;evidence_first<=history_data[history_match];evidence_second<=packet_q;
  evidence_first_length<=history_len[history_match];evidence_second_length<=len_q;evidence_offset<=offset;
  evidence_first_stamp<=history_stamp[history_match];evidence_second_stamp<=stamp_q;
  evidence_epoch<=epoch;evidence_rule<=rule_q;evidence_channel<=channel;
 end else evidence_lost<=evidence_lost+1'b1;
end endtask
always @(posedge clk)begin
 if(rst)begin
  evidence_valid<=0;evidence_first<=0;evidence_second<=0;evidence_first_length<=0;evidence_second_length<=0;evidence_offset<=0;evidence_first_stamp<=0;evidence_second_stamp<=0;evidence_lost<=0;evidence_epoch<=0;evidence_rule<=0;evidence_channel<=0;state<=IDLE;last_channel<=3;channel<=0;packet_q<=0;len_q<=0;good_q<=0;take<=0;replay_start<=0;replay_packet<=0;replay_length<=0;event_push<=0;event_record<=0;accepted<=0;blocked<=0;observed<=0;ab_conflicts<=0;hash_failures<=0;context_timeouts<=0;
  flags=0;duplicate=0;permit=0;rule_q<=0;rule_found<=0;kind<=0;last_rx_valid<=0;final_report<=0;ntp_waiting<=0;ntp_established<=0;history_next<=0;crypto_ctx<=0;sha_start<=0;
  for(i=0;i<RULES;i=i+1)begin last_rx[i]<=0;window_start[i]<=0;window_count[i]<=0;phase[i]<=0;phase_stamp[i]<=0;control_tid[i]<=0;report_tid[i]<=0;ntp_origin[i]<=0;ntp_stamp[i]<=0;ntp_port[i]<=0;end
  for(i=0;i<HISTORY;i=i+1)begin history_valid[i]<=0;history_len[i]<=0;history_channel[i]<=0;history_stamp[i]<=0;end
  for(i=0;i<CONTEXTS;i=i+1)begin ctx_valid[i]<=0;ctx_complete[i]<=0;ctx_rule[i]<=0;ctx_tid[i]<=0;ctx_peer[i]<=0;ctx_next[i]<=1;ctx_length[i]<=0;ctx_last_n[i]<=0;ctx_stamp[i]<=0;ctx_version[i]<=0;ctx_digest[i]<=0;ctx_name[i]<=0;ctx_name_len[i]<=0;ctx_expected[i]<=0;ctx_auth[i]<=0;frag_valid[i]<=0;frag_rule[i]<=0;frag_id[i]<=0;frag_next[i]<=0;frag_stamp[i]<=0;end
 end else begin
  take<=0;replay_start<=0;event_push<=0;sha_start<=0;if(evidence_ack)evidence_valid<=0;
  // Expiry runs while idle, so it never invalidates a context during SHA/COPY.
  if(state==IDLE)begin
   expire_count=0;
   for(i=0;i<CONTEXTS;i=i+1)begin
    if(ctx_valid[i]&&cycle[31:0]-ctx_stamp[i]>=rw(ctx_rule[i],11))begin ctx_valid[i]<=0;expire_count=expire_count+1;end
    if(frag_valid[i]&&cycle[31:0]-frag_stamp[i]>=rw(frag_rule[i],11))frag_valid[i]<=0;
   end
   if(expire_count!=0)context_timeouts<=context_timeouts+expire_count;
   for(i=0;i<RULES;i=i+1)begin
    if(phase[i]!=0&&cycle[31:0]-phase_stamp[i]>=rw(i,11))begin phase[i]<=0;final_report[i]<=0;end
    if(ntp_waiting[i]&&cycle-ntp_stamp[i]>=ntp_rtt_limit)ntp_waiting[i]<=0;
   end
  end
  if(clear)begin
   last_rx_valid<=0;final_report<=0;ntp_waiting<=0;ntp_established<=0;history_next<=0;
   for(i=0;i<RULES;i=i+1)begin phase[i]<=0;window_count[i]<=0;end
   for(i=0;i<HISTORY;i=i+1)history_valid[i]<=0;
   for(i=0;i<CONTEXTS;i=i+1)begin ctx_valid[i]<=0;frag_valid[i]<=0;end
  end
  case(state)
   IDLE:begin
    pick=-1;
    for(j=1;j<=4;j=j+1)begin probe=(last_channel+j)%4;if(pick<0&&requests[probe]&&(probe>=2||mode!=2||replay_ready[probe]))pick=probe;end
    if(pick>=0)begin channel<=pick;last_channel<=pick;packet_q<=packets[pick*MAX_WIRE*8+:MAX_WIRE*8];len_q<=lengths[pick*11+:11];good_q<=goods[pick];stamp_q<=stamps[pick*64+:64];inserted_history=-1;flags=0;duplicate=0;rule_found<=0;rule_q<=0;state<=HEADER;end
   end
   HEADER:begin
    dm<={b(8),b(9),b(10),b(11),b(12),b(13)};sm<={b(14),b(15),b(16),b(17),b(18),b(19)};
    sip<=u32(34);dip<=u32(38);sp<=u16(42);dp<=u16(44);ip_len<=u16(24);ip_id<=u16(26);fragment<=u16(28);udp_len<=u16(46);sn<=b(len_q-5);
    folded=0;for(j=22;j<42;j=j+2)folded=folded+u16(j);folded=(folded&65535)+(folded>>16);folded=(folded&65535)+(folded>>16);
    if(!good_q||len_q<72||u16(20)!=16'h0800||b(22)!=8'h45||b(31)!=17||u16(24)<21||((u16(28)&16'h1fff)==0&&u16(24)<28)||22+u16(24)>len_q-5||folded!=65535||bb(14,0,1))begin flags=flags|F_FORMAT;state<=DECIDE;end
    else if((u16(28)&16'h2000)!=0&&((u16(24)-20)&7)!=0)begin flags=flags|F_FORMAT;state<=DECIDE;end
    else if((u16(28)&16'h3fff)==0&&(u16(46)<8||u16(46)!=u16(24)-20))begin flags=flags|F_FORMAT;state<=DECIDE;end
    else if((u16(28)&16'h3fff)==0&&u16(48)!=0)begin udp_sum<=u16(34)+u16(36)+u16(38)+u16(40)+17+u16(46);sum_index<=0;state<=L4SUM;end
    else state<=MATCH_RULE;
   end
   L4SUM:begin
    if(sum_index<udp_len)begin udp_sum<=udp_sum+{b(42+sum_index),(sum_index+1<udp_len?b(43+sum_index):8'd0)};sum_index<=sum_index+2;end
    else begin folded=(udp_sum&65535)+(udp_sum>>16);folded=(folded&65535)+(folded>>16);if(folded!=65535)begin flags=flags|F_FORMAT;state<=DECIDE;end else state<=MATCH_RULE;end
   end
   MATCH_RULE:begin
    chosen_rule=-1;context_rule=-1;
    for(j=0;j<RULES;j=j+1)begin
     same=rw(j,0)&1;
     if(!channel[1])begin
      if(sip!=rw(j,1)||dip!=rw(j,2)||dm!={rb(j,5,0,16),rw(j,4)}||((sm^{rb(j,7,0,16),rw(j,6)})&48'hffffffffff9f)!=0)same=0;
      // Port-qualified rules remain associated with their fragment context.
      if((fragment&16'h1fff)==0&&((rw(j,0)>>2)&7)!=2)begin
       if(rb(j,3,0,16)!=0&&dp!=rb(j,3,0,16))same=0;
       if(rb(j,3,16,16)!=0&&sp!=rb(j,3,16,16))same=0;
      end
     end else begin
      if(dip!=rw(j,1)||sip!=rw(j,2))same=0;
      if(rw(j,14)!=0&&dm!={rb(j,15,0,16),rw(j,14)})same=0;
     end
     if(same)begin
      if(chosen_rule<0)chosen_rule=j;
      if(!channel[1]&&(fragment&16'h1fff)!=0)for(k=0;k<CONTEXTS;k=k+1)
       if(frag_valid[k]&&frag_rule[k]==j&&frag_id[k]==ip_id&&context_rule<0)context_rule=j;
     end
    end
    if(context_rule>=0)chosen_rule=context_rule;
    if(chosen_rule<0)begin flags=flags|F_ACL;state<=DECIDE;end
    else begin rule_q<=chosen_rule;rule_found<=1;kind<=(rw(chosen_rule,0)>>2)&7;
     if(len_q-8>rb(chosen_rule,9,0,16))flags=flags|F_QUOTA;
     state<=AB_FIND;
    end
   end
   AB_FIND:begin
    history_match=-1;for(j=0;j<HISTORY;j=j+1)if(history_match<0&&match_key(j))history_match=j;
    if(history_match>=0)begin
     if(history_len[history_match]!=len_q)begin capture_conflict(16'hffff);flags=flags|F_AB;ab_conflicts<=ab_conflicts+1'b1;state<=PROTOCOL;end
     else begin compare_index<=8;state<=AB_COMPARE;end
    end else begin
     inserted_history=history_next;history_data[history_next]<=packet_q;history_len[history_next]<=len_q;history_channel[history_next]<=channel;history_stamp[history_next]<=stamp_q;history_valid[history_next]<=1;history_next<=history_next==HISTORY-1?0:history_next+1;state<=PROTOCOL;
    end
   end
   AB_COMPARE:begin
    if(compare_index==len_q-4)begin duplicate=1;flags=flags|history_flags[history_match];
     if(!channel[1]&&kind==2&&dp>=42000&&dp<43000)for(j=0;j<CONTEXTS;j=j+1)if(ctx_valid[j]&&ctx_rule[j]==rule_q&&ctx_tid[j]==dp&&ctx_auth[j]&&(ctx_version[j]<floors[rule_q*32+:32]||cycle>=ctx_expiry[j]||ctx_target[j]!=target_id))flags=flags|F_AUTH;
     state<=DECIDE;end
    else if(((compare_index!=19&&history_data[history_match][compare_index*8+:8]!=b(compare_index))||(compare_index==19&&(history_data[history_match][19*8+:8]&8'h9f)!=(b(19)&8'h9f))))begin capture_conflict(compare_index);flags=flags|F_AB;ab_conflicts<=ab_conflicts+1'b1;state<=DECIDE;end
    else compare_index<=compare_index+1;
   end
   PROTOCOL:begin
    if(flags!=0)state<=DECIDE;
    else begin
     if(!channel[1])begin
      if(last_rx_valid[rule_q]&&stamp_q[31:0]-last_rx[rule_q]<rw(rule_q,8))flags=flags|F_RATE;
      if(rw(rule_q,12)!=0&&rw(rule_q,13)!=0)begin
       if(cycle[31:0]-window_start[rule_q]>=rw(rule_q,12))begin window_start[rule_q]<=cycle[31:0];window_count[rule_q]<=1;end
       else if(window_count[rule_q]>=rw(rule_q,13))flags=flags|F_RATE;
       else window_count[rule_q]<=window_count[rule_q]+1'b1;
      end
      if(flags==0)begin last_rx_valid[rule_q]<=1;last_rx[rule_q]<=stamp_q[31:0];end
     end
     opcode=u16(50);block_q=u16(52);data_n=udp_len-12;
     if(flags!=0)state<=DECIDE;
     else if((fragment&16'h3fff)!=0)begin
      if(channel[1])state<=DECIDE;
      else if((rw(rule_q,0)&32'h20)==0||kind!=0)begin flags=flags|F_ORPHAN;state<=DECIDE;end
      else begin
       slot=-1;free_slot=-1;active_count=0;
       for(j=0;j<CONTEXTS;j=j+1)begin
        if(!frag_valid[j]&&free_slot<0)free_slot=j;
        if(frag_valid[j]&&frag_rule[j]==rule_q)begin active_count=active_count+1;if(frag_id[j]==ip_id)slot=j;end
       end
       if((fragment&16'h1fff)==0)begin
        if(slot>=0)flags=flags|F_OVERLAP;
        else if(free_slot<0||active_count>=rb(rule_q,10,0,8))flags=flags|F_QUOTA;
        else begin frag_valid[free_slot]<=1;frag_rule[free_slot]<=rule_q;frag_id[free_slot]<=ip_id;frag_next[free_slot]<=ip_len-20;frag_stamp[free_slot]<=cycle[31:0];end
       end else if(slot<0)flags=flags|F_ORPHAN;
       else if(((fragment&16'h1fff)<<3)!=frag_next[slot])flags=flags|F_OVERLAP;
       else if(((fragment&16'h1fff)<<3)+ip_len-20>MAX_DATAGRAM)flags=flags|F_QUOTA;
       else begin frag_next[slot]<=frag_next[slot]+ip_len-20;frag_stamp[slot]<=cycle[31:0];if(!fragment[13])frag_valid[slot]<=0;end
       state<=DECIDE;
      end
     end else if(kind==3)begin
      if(channel[1]&&dp==123&&udp_len==56&&bb(50,0,3)==3)begin ntp_waiting[rule_q]<=1;ntp_origin[rule_q]<=u64(90);ntp_stamp[rule_q]<=stamp_q;ntp_port[rule_q]<=sp;end
      else if(!channel[1])begin
       origin_q=u64(74);receive_q=u64(82);transmit_q=u64(90);
       abs_difference=transmit_q>=ntp_origin[rule_q]?transmit_q-ntp_origin[rule_q]:ntp_origin[rule_q]-transmit_q;
       if(!ntp_waiting[rule_q]||udp_len!=56||sp!=123||dp!=ntp_port[rule_q]||bb(50,0,3)!=4||bb(50,3,3)!=4||bb(50,6,2)==3||b(51)==0||b(51)>15||origin_q!=ntp_origin[rule_q]||receive_q==0||transmit_q<receive_q||stamp_q-ntp_stamp[rule_q]>ntp_rtt_limit||((ntp_established[rule_q]||(rw(rule_q,0)&32'h200)!=0)&&abs_difference>time_jump_limit))flags=flags|F_TIME;
       if(flags==0)begin ntp_waiting[rule_q]<=0;ntp_established[rule_q]<=1;end
      end
      state<=DECIDE;
     end else if(kind==2)begin
      name_q=0;name_n=0;
      if(opcode==1||opcode==2)begin
       for(j=0;j<32;j=j+1)if(j+2<udp_len-8&&b(52+j)!=0&&name_n==j)begin name_q[j*8+:8]=b(52+j);name_n=name_n+1;end
       if(name_n==0||b(52+name_n)!=0)flags=flags|F_PHASE;
      end
      if(flags!=0)state<=DECIDE;
      else if(!channel[1]&&dp==69&&opcode==1&&is_suffix(24'h4c5549))begin
       if(phase[rule_q]!=0&&phase[rule_q]!=1&&phase[rule_q]!=5)flags=flags|F_PHASE;
       else begin phase[rule_q]<=1;control_tid[rule_q]<=sp;final_report[rule_q]<=0;end
       state<=DECIDE;
      end else if(!channel[1]&&dp==69&&opcode==2&&is_suffix(24'h4c5552))begin
       if(phase[rule_q]!=1&&phase[rule_q]!=2)flags=flags|F_PHASE;
       else begin phase[rule_q]<=2;control_tid[rule_q]<=sp;end
       state<=DECIDE;
      end else if(!channel[1]&&dp==41000)begin
       if(sp!=control_tid[rule_q])flags=flags|F_TID;
       else if(opcode==3&&(phase[rule_q]!=2||block_q!=1||data_n>128))flags=flags|F_PHASE;
       else if(opcode==4&&(phase[rule_q]!=1||block_q!=1))flags=flags|F_PHASE;
       else if(opcode!=3&&opcode!=4&&opcode!=5)flags=flags|F_PHASE;
       state<=DECIDE;
      end else if(channel[1]&&dp==69&&opcode==1)begin
       if((rw(rule_q,0)&32'h40)!=0&&(phase[rule_q]<2||phase[rule_q]>3))flags=flags|F_PHASE;
       slot=-1;free_slot=-1;active_count=0;
       for(j=0;j<CONTEXTS;j=j+1)begin
        if(ctx_valid[j]&&ctx_rule[j]==rule_q&&ctx_tid[j]==sp)slot=j;
        if(!ctx_valid[j]&&free_slot<0)free_slot=j;
        if(ctx_valid[j]&&ctx_rule[j]==rule_q)active_count=active_count+1;
       end
       grant_slot=-1;
       for(j=0;j<GRANTS;j=j+1)begin
        same=gw(j,0)&1;expected_hash=0;
        for(k=0;k<8;k=k+1)expected_hash[k*32+:32]=gw(j,20+k);
        if(gb(j,0,4,4)!=rule_q||gb(j,0,16,6)!=name_n||expected_hash!=target_id||!floor_loaded[rule_q]||gw(j,1)<floors[rule_q*32+:32]||cycle-committed_at>=gw(j,3))same=0;
        for(k=0;k<32;k=k+1)if(k<name_n&&gb(j,12+k/4,(k%4)*8,8)!=name_q[k*8+:8])same=0;
        if(same&&grant_slot<0)grant_slot=j;
       end
       if((rw(rule_q,0)&32'h80)!=0&&grant_slot<0)flags=flags|F_AUTH;
       if(slot>=0)begin if(ctx_name[slot]!=name_q||ctx_name_len[slot]!=name_n)flags=flags|F_TID;end
       else if(free_slot<0||active_count>=rb(rule_q,10,0,8))flags=flags|F_QUOTA;
       else if(flags==0)begin
        ctx_expiry[free_slot]<=grant_slot>=0?committed_at+gw(grant_slot,3):0;ctx_target[free_slot]<=target_id;
        ctx_valid[free_slot]<=1;ctx_complete[free_slot]<=0;ctx_rule[free_slot]<=rule_q;ctx_tid[free_slot]<=sp;ctx_peer[free_slot]<=0;ctx_next[free_slot]<=1;ctx_length[free_slot]<=0;ctx_last_n[free_slot]<=0;ctx_stamp[free_slot]<=cycle[31:0];ctx_name[free_slot]<=name_q;ctx_name_len[free_slot]<=name_n;ctx_auth[free_slot]<=grant_slot>=0;ctx_expected[free_slot]<=grant_slot>=0?gw(grant_slot,2):MAX_FILE;ctx_version[free_slot]<=grant_slot>=0?gw(grant_slot,1):0;
        for(k=0;k<8;k=k+1)ctx_digest[free_slot][(7-k)*32+:32]<=grant_slot>=0?gw(grant_slot,4+k):0;
        phase[rule_q]<=3;
       end
       state<=DECIDE;
      end else if(!channel[1]&&dp>=42000&&dp<43000)begin
       slot=-1;for(j=0;j<CONTEXTS;j=j+1)if(ctx_valid[j]&&ctx_rule[j]==rule_q&&ctx_tid[j]==dp)slot=j;
       if(slot<0||opcode!=3||data_n<0||data_n>512)begin flags=flags|F_PHASE;state<=DECIDE;end
       else if(ctx_peer[slot]!=0&&sp!=ctx_peer[slot])begin flags=flags|F_TID;state<=DECIDE;end
       else if(ctx_auth[slot]&&(ctx_version[slot]<floors[rule_q*32+:32]||cycle>=ctx_expiry[slot]||ctx_target[slot]!=target_id))begin flags=flags|F_AUTH;state<=DECIDE;end
       else if(block_q!=ctx_next[slot]&&block_q!=ctx_next[slot]-1)begin flags=flags|F_TID;state<=DECIDE;end
       else begin
        crypto_ctx<=slot;copy_duplicate=block_q==ctx_next[slot]-1;copy_index<=0;
        if(copy_duplicate&&data_n!=ctx_last_n[slot])begin flags=flags|F_TID;state<=DECIDE;end
        else if(!copy_duplicate&&(ctx_complete[slot]||ctx_length[slot]+data_n>MAX_FILE||(ctx_auth[slot]&&ctx_length[slot]+data_n>ctx_expected[slot])))begin flags=flags|F_QUOTA;state<=DECIDE;end
        else state<=COPY_DATA;
       end
      end else if(channel[1]&&sp==40002)begin
       if(opcode==2&&dp==69&&is_suffix(24'h4c5553))begin if(phase[rule_q]<2||phase[rule_q]>4)flags=flags|F_PHASE;report_tid[rule_q]<=0;end
       else if(opcode==3&&block_q==1)begin
        if(report_tid[rule_q]!=0&&dp!=report_tid[rule_q])flags=flags|F_TID;
        if(u16(60)==3)begin final_report[rule_q]<=1;phase[rule_q]<=4;end
       end else if(opcode!=5)flags=flags|F_PHASE;
       state<=DECIDE;
      end else if(!channel[1]&&dp==40002)begin
       if(opcode!=4||udp_len!=12)flags=flags|F_PHASE;
       else if(block_q==0)report_tid[rule_q]<=sp;
       else if(block_q==1&&sp==report_tid[rule_q])begin if(final_report[rule_q])begin phase[rule_q]<=5;final_report[rule_q]<=0;end end
       else flags=flags|F_TID;
       state<=DECIDE;
      end else if(channel[1]&&(sp==41000||(sp>=42000&&sp<43000)))state<=DECIDE;
      else begin flags=flags|F_PHASE;state<=DECIDE;end
      if(flags==0)phase_stamp[rule_q]<=cycle[31:0];
     end else state<=DECIDE;
    end
   end
   COPY_DATA:begin
    if(copy_index<data_n)begin
     if(copy_duplicate)begin if(file_memory[crypto_ctx*MAX_FILE+ctx_length[crypto_ctx]-ctx_last_n[crypto_ctx]+copy_index]!=b(54+copy_index))flags=flags|F_TID;end
     else file_memory[crypto_ctx*MAX_FILE+ctx_length[crypto_ctx]+copy_index]<=b(54+copy_index);
     copy_index<=copy_index+1;
    end else begin
     if(flags==0)begin ctx_stamp[crypto_ctx]<=cycle[31:0];ctx_peer[crypto_ctx]<=sp;end
     if(copy_duplicate||flags!=0)state<=DECIDE;
     else begin
      ctx_length[crypto_ctx]<=ctx_length[crypto_ctx]+data_n;ctx_last_n[crypto_ctx]<=data_n;ctx_next[crypto_ctx]<=ctx_next[crypto_ctx]+1'b1;
      if(data_n<512)begin
       if(ctx_auth[crypto_ctx]&&ctx_length[crypto_ctx]+data_n!=ctx_expected[crypto_ctx])begin flags=flags|F_HASH;hash_failures<=hash_failures+1'b1;ctx_valid[crypto_ctx]<=0;state<=DECIDE;end
       else if(ctx_auth[crypto_ctx])state<=HASH_START;
       else begin ctx_complete[crypto_ctx]<=1;state<=DECIDE;end
      end else state<=DECIDE;
     end
    end
   end
   HASH_START:begin sha_start<=1;state<=HASH_WAIT;end
   HASH_WAIT:if(sha_done)begin
    if(sha_digest!=ctx_digest[crypto_ctx])begin flags=flags|F_HASH;hash_failures<=hash_failures+1'b1;ctx_valid[crypto_ctx]<=0;end
    else ctx_complete[crypto_ctx]<=1;
    state<=DECIDE;
   end
   DECIDE:begin
    // TX is observational: sessions learnt from locally emitted requests can
    // cause subsequent RX rejection, but no producer frame is truncated.
    if(!channel[1]&&rule_found&&kind==2&&dp>=42000&&dp<43000)
     for(j=0;j<CONTEXTS;j=j+1)if(ctx_valid[j]&&ctx_rule[j]==rule_q&&ctx_tid[j]==dp&&ctx_auth[j]&&(cycle>=ctx_expiry[j]||ctx_version[j]<floors[rule_q*32+:32]||ctx_target[j]!=target_id))flags=flags|F_AUTH;
    permit=flags==0;if(inserted_history>=0)history_flags[inserted_history]<=flags;
    if(channel[1]||mode!=2||!permit||replay_ready[channel[0]])begin
     if(channel<2&&mode==2&&permit)begin replay_start[channel[0]]<=1;replay_packet<=packet_q;replay_length<=len_q;end
     event_push<=1;event_record<={epoch,stamp_q,flags,rule_q,channel,permit,duplicate,4'd0,phase[rule_q],1'b0,{5'd0,len_q},sn,{6'd0,mode}};
     observed<=observed+1'b1;
     if(channel<2)begin if(permit)accepted<=accepted+1'b1;else blocked<=blocked+1'b1;end
     take[channel]<=1;state<=RETIRE;
    end
   end
   RETIRE:state<=IDLE;
   default:state<=IDLE;
  endcase
 end
end
endmodule
