`timescale 1ns/1ps
// Full-frame validation precedes per-network integrity. Four independent UDP
// reassembly contexts; two completed-message slots per VL. No partial message
// reaches the application. A/B duplicate fragments are eliminated before copy.
module afdx_datagram_rx #(
 parameter integer MAX_MESSAGE=8192,SUBVL_MAX_MESSAGE=2048,SKEW_MAX_CYCLES=2000000,EXTENDED_PORTS=0,
 parameter integer PORTS=EXTENDED_PORTS?16:4,
 parameter integer REASSEMBLY_TIMEOUT=0,CHECK_UDP=1,AUTO_DRAIN=1,FRESHNESS_CYCLES=12500000,
 parameter [3:0] SAMPLING_MASK=0
)(
 input wire clk,rst,input wire [671:0] network_cfg,input wire [1023:0] port_cfg,
 input wire [1:0] read_subvl,output wire [3:0] payload_port,output wire [15:0] payload_sap,
 input wire [7:0] a_data,b_data,input wire a_valid,b_valid,a_error,b_error,
 output reg [7:0] payload_data,output wire payload_valid,payload_sof,payload_eof,
 output wire payload_network,input wire payload_ready,
 output wire [15:0] payload_length,output wire [1:0] payload_vl,output reg payload_fresh,
 input wire read_request,input wire [1:0] read_port,output wire read_ready,
 output wire [31:0] accepted_frames,duplicate_frames,stale_frames,
 output wire [31:0] accepted_a_frames,accepted_b_frames,cross_duplicates,same_repeats,sequence_gaps,
 output reg [31:0] messages,dropped,overflows,reassembly_errors,timeouts
);
wire [PORTS-1:0] sampling,port_enabled;
localparam UDP_MAX=MAX_MESSAGE+8,BLOCKS=(UDP_MAX+7)/8;
localparam MEMORY_BYTES=12*UDP_MAX+(PORTS-4)*3*(SUBVL_MAX_MESSAGE+8);
reg [7:0] frame_mem[0:12287],data_mem[0:MEMORY_BYTES-1];
function [15:0] port_capacity;input [3:0] p;begin port_capacity=p<4?MAX_MESSAGE:SUBVL_MAX_MESSAGE;end endfunction
function integer message_address;input [3:0] p;input [1:0] q;input [15:0] offset;begin
 if(p<4)message_address=(p*3+q)*UDP_MAX+offset;
 else message_address=12*UDP_MAX+((p-4)*3+q)*(SUBVL_MAX_MESSAGE+8)+offset;
end endfunction
reg [10:0] wire_count[0:1],frame_length[0:7];reg [31:0] crc[0:1];reg [47:0] destination[0:1];
reg [1:0] wptr[0:1],rptr[0:1],frame_vl[0:7];reg [2:0] used[0:1];
reg [1:0] previous,bad,discard,push,pop;reg [3:0] drop_inc,overflow_inc,timeout_inc;
wire [7:0] in_data[0:1];wire [1:0] in_valid={b_valid,a_valid},in_error={b_error,a_error};assign in_data[0]=a_data;assign in_data[1]=b_data;
reg [1:0] cfg_match[0:1];reg [1:0] cfg_found;integer n,k;
always @*begin
 cfg_found=0;cfg_match[0]=0;cfg_match[1]=0;
 for(n=0;n<2;n=n+1)for(k=0;k<4;k=k+1)
  if(network_cfg[k*168]&&network_cfg[k*168+1]&&destination[n]==network_cfg[k*168+8+:48])begin cfg_found[n]=1;cfg_match[n]=k;end
end
function [31:0] crcbyte;input [31:0] c;input [7:0] x;reg [31:0] v;integer j;begin v=c^x;for(j=0;j<8;j=j+1)v=v[0]?(v>>1)^32'hedb88320:v>>1;crcbyte=v;end endfunction
localparam IDLE=0,HEADER=1,IP_SUM=2,IP_CHECK=3,IC=4,WAIT_IC=5,CONTEXT=6,START_FRAGMENT=7,COPY=8,VERIFY=9,RELEASE=10;
reg [3:0] state;reg owner,rr;reg [2:0] frame_slot;reg [3:0] vl;reg [3:0] checksum_index;
reg [15:0] ip_total,ip_id,frag_offset,frag_length,index,udp_len,udp_checksum;
reg mf;reg [31:0] ip_sum;reg [7:0] sequence_number,word_high;
reg [PORTS-1:0] active,first_seen,last_seen,context_network;
reg [15:0] context_id[0:PORTS-1],expected_length[0:PORTS-1],last_end[0:PORTS-1],filled[0:PORTS-1],checksums[0:PORTS-1];
reg [31:0] ages[0:PORTS-1],udp_sums[0:PORTS-1];reg [BLOCKS-1:0] seen[0:PORTS-1];
reg [1:0] message_wp[0:PORTS-1],message_rp[0:PORTS-1],latest[0:PORTS-1];reg [PORTS-1:0] unread;
reg [31:0] freshness_age[0:PORTS-1];reg [1:0] message_count[0:PORTS-1];reg [15:0] message_length[0:PORTS*3-1];reg [PORTS*3-1:0] message_network;
reg [1:0] out_state;reg [3:0] out_vl,out_rr;reg [1:0] out_slot;reg [15:0] out_index,out_length;
reg out_choice_valid;reg [3:0] out_choice,out_probe;integer j;
always @*begin
 out_choice_valid=0;out_choice=0;out_probe=0;
 for(j=1;j<=PORTS;j=j+1)begin out_probe=(out_rr+j)%PORTS;if(!out_choice_valid&&message_count[out_probe]!=0&&(!sampling[out_probe]||unread[out_probe]))begin out_choice_valid=1;out_choice=out_probe;end end
end
wire [3:0] read_index=EXTENDED_PORTS?{read_subvl,read_port}:{2'd0,read_port};
assign payload_port=out_vl;assign payload_sap=EXTENDED_PORTS&&port_cfg[out_vl*64+2]?port_cfg[out_vl*64+8+:16]:16'd0;
assign read_ready=!rst&&out_state==0&&message_count[read_index]!=0;
assign payload_valid=out_state==2;assign payload_sof=payload_valid&&out_index==0;assign payload_eof=payload_valid&&out_index==out_length-1;
assign payload_length=out_length;assign payload_vl=out_vl[1:0];assign payload_network=message_network[out_vl*3+out_slot];
wire consume=payload_valid&&payload_ready&&payload_eof&&!sampling[out_vl];
wire begin_read=out_state==0&&(AUTO_DRAIN?out_choice_valid:read_request&&read_ready);
wire [3:0] selected_read_port=AUTO_DRAIN?out_choice:read_index;
reg [1:0] free_sample_slot;reg sample_slot_found;integer ss;
always @*begin free_sample_slot=0;sample_slot_found=0;
 for(ss=0;ss<3;ss=ss+1)if(!sample_slot_found&&!(message_count[vl]!=0&&latest[vl]==ss)&&!(out_state!=0&&out_vl==vl&&out_slot==ss))begin free_sample_slot=ss;sample_slot_found=1;end
end
function [15:0] f16;input integer p;begin f16={frame_mem[frame_slot*1536+p],frame_mem[frame_slot*1536+p+1]};end endfunction
function [31:0] f32;input integer p;begin f32={f16(p),f16(p+2)};end endfunction
function [15:0] folded;input [31:0] v;reg [31:0] x;begin x=(v&65535)+(v>>16);x=(x&65535)+(x>>16);folded=x[15:0];end endfunction
genvar policy;
generate for(policy=0;policy<PORTS;policy=policy+1)begin:PORT_POLICY
 assign sampling[policy]=EXTENDED_PORTS?port_cfg[policy*64+1]:SAMPLING_MASK[policy%4];
 assign port_enabled[policy]=EXTENDED_PORTS?port_cfg[policy*64]:1'b1;
end endgenerate
// Later fragments use the IPv4 ID within their VL. Before-first fragments can
// be assigned only when the VL has one configured receiving port; ambiguous
// orphan fragments are discarded rather than delivered to an incorrect SAP.
wire [15:0] lookup_fragment={frame_mem[frame_slot*1536+28],frame_mem[frame_slot*1536+29]};
wire [15:0] lookup_identifier={frame_mem[frame_slot*1536+26],frame_mem[frame_slot*1536+27]};
wire [15:0] lookup_source_port={frame_mem[frame_slot*1536+42],frame_mem[frame_slot*1536+43]};
wire [15:0] lookup_dest_port={frame_mem[frame_slot*1536+44],frame_mem[frame_slot*1536+45]};
reg port_match_valid;reg [3:0] port_match,fallback_port;integer pi,enabled_ports;
reg [15:0] match_sport,match_dport;
always @*begin
 port_match_valid=0;port_match=0;enabled_ports=0;fallback_port=0;match_sport=0;match_dport=0;
 for(pi=0;pi<PORTS;pi=pi+1)begin
  match_sport=EXTENDED_PORTS&&port_cfg[pi*64+3]?port_cfg[pi*64+24+:16]:network_cfg[(pi%4)*168+120+:16];
  match_dport=EXTENDED_PORTS&&port_cfg[pi*64+3]?port_cfg[pi*64+40+:16]:network_cfg[(pi%4)*168+136+:16];
  if(pi%4==vl[1:0]&&port_enabled[pi])begin
   enabled_ports=enabled_ports+1;fallback_port=pi;
   if((lookup_fragment&16'h1fff)==0)begin
    if(match_sport==lookup_source_port&&match_dport==lookup_dest_port)begin port_match_valid=1;port_match=pi;end
   end else if(active[pi]&&context_id[pi]==lookup_identifier)begin port_match_valid=1;port_match=pi;end
  end
 end
 if((lookup_fragment&16'h1fff)!=0&&!port_match_valid&&enabled_ports==1)begin port_match_valid=1;port_match=fallback_port;end
end
wire choice_network=used[0]!=0&&used[1]!=0?!rr:used[1]!=0;
wire ic_ready,ic_accept,ic_duplicate,ic_stale;
afdx_rx_redundancy_eliminator #(.HISTORY_TIMEOUT_CYCLES(SKEW_MAX_CYCLES)) integrity(
.clk(clk),.rst_n(!rst),.clear(1'b0),.rx_valid(state==IC),.rx_ready(ic_ready),.rx_network(owner),.rx_vl_id(vl[1:0]),.rx_seq(sequence_number),.rx_payload(32'd0),
.out_valid(),.out_ready(1'b1),.out_vl_id(),.out_seq(),.out_payload(),.out_network(),.accept_event(ic_accept),.duplicate_event(ic_duplicate),.stale_event(ic_stale),.gap_event(),
.accepted_count(accepted_frames),.accepted_a_count(accepted_a_frames),.accepted_b_count(accepted_b_frames),.duplicate_count(duplicate_frames),.cross_network_duplicate_count(cross_duplicates),.same_network_repeat_count(same_repeats),.stale_count(stale_frames),.sequence_gap_count(sequence_gaps),
.last_valid0_dbg(),.last_valid1_dbg(),.last_valid2_dbg(),.last_valid3_dbg(),.last_seq0_dbg(),.last_seq1_dbg(),.last_seq2_dbg(),.last_seq3_dbg(),.seen_mask0_dbg(),.seen_mask1_dbg(),.seen_mask2_dbg(),.seen_mask3_dbg());
wire [15:0] absolute_byte=frag_offset+index;
wire [7:0] copy_byte=frame_mem[frame_slot*1536+42+index];
wire complete=active[vl]&&first_seen[vl]&&last_seen[vl]&&filled[vl]==expected_length[vl]&&last_end[vl]==expected_length[vl];
wire udp_ok=!CHECK_UDP||checksums[vl]==0||folded(udp_sums[vl]+expected_length[vl])==16'hffff;
wire publish=state==VERIFY&&complete&&udp_ok;
integer i;
task abandon;begin active[vl]<=0;reassembly_errors<=reassembly_errors+1'b1;drop_inc=drop_inc+1'b1;state<=RELEASE;end endtask
task fresh_context;begin
 if(sampling[vl])message_wp[vl]<=free_sample_slot;
 active[vl]<=1;context_id[vl]<=ip_id;seen[vl]<=0;filled[vl]<=0;first_seen[vl]<=0;last_seen[vl]<=0;expected_length[vl]<=0;last_end[vl]<=0;checksums[vl]<=0;ages[vl]<=0;context_network[vl]<=owner;
 udp_sums[vl]<={16'd0,network_cfg[vl[1:0]*168+72+:16]}+{16'd0,network_cfg[vl[1:0]*168+56+:16]}+{16'd0,network_cfg[vl[1:0]*168+104+:16]}+{16'd0,network_cfg[vl[1:0]*168+88+:16]}+17;
 state<=START_FRAGMENT;
end endtask
always @(posedge clk)begin
 if(rst)begin
  previous<=0;bad<=0;discard<=0;push=0;pop=0;drop_inc=0;overflow_inc=0;timeout_inc=0;
  state<=IDLE;owner<=0;rr<=1;frame_slot<=0;vl<=0;checksum_index<=0;ip_total<=0;ip_id<=0;frag_offset<=0;frag_length<=0;index<=0;udp_len<=0;udp_checksum<=0;mf<=0;ip_sum<=0;sequence_number<=0;word_high<=0;
  active<=0;first_seen<=0;last_seen<=0;context_network<=0;unread<=0;message_network<=0;payload_fresh<=0;
  out_state<=0;out_vl<=0;out_rr<=PORTS-1;out_slot<=0;out_index<=0;out_length<=0;payload_data<=0;
  messages<=0;dropped<=0;overflows<=0;reassembly_errors<=0;timeouts<=0;
  for(i=0;i<2;i=i+1)begin wire_count[i]<=0;crc[i]<=32'hffffffff;destination[i]<=0;wptr[i]<=0;rptr[i]<=0;used[i]<=0;end
  for(i=0;i<8;i=i+1)begin frame_length[i]<=0;frame_vl[i]<=0;end
  for(i=0;i<PORTS*3;i=i+1)message_length[i]<=0;
  for(i=0;i<PORTS;i=i+1)begin message_wp[i]<=0;message_rp[i]<=0;latest[i]<=0;freshness_age[i]<=0;context_id[i]<=0;expected_length[i]<=0;last_end[i]<=0;filled[i]<=0;checksums[i]<=0;ages[i]<=0;udp_sums[i]<=0;seen[i]<=0;message_count[i]<=0;end
 end else begin
  previous<=in_valid;push=0;pop=0;drop_inc=0;overflow_inc=0;timeout_inc=0;
  for(i=0;i<2;i=i+1)begin
   if(in_valid[i])begin
    if(!previous[i])begin
     discard[i]<=used[i]==4;bad[i]<=in_error[i]||in_data[i]!=8'h55;wire_count[i]<=1;crc[i]<=32'hffffffff;destination[i]<=0;
     if(used[i]<4)frame_mem[(i*4+wptr[i])*1536]<=in_data[i];
    end else if(wire_count[i]<1536)begin
     if(!discard[i])frame_mem[(i*4+wptr[i])*1536+wire_count[i]]<=in_data[i];wire_count[i]<=wire_count[i]+1'b1;
     if(wire_count[i]>=8)crc[i]<=crcbyte(crc[i],in_data[i]);
     if(wire_count[i]>=8&&wire_count[i]<=13)destination[i]<={destination[i][39:0],in_data[i]};
     if(in_error[i]||(wire_count[i]<7&&in_data[i]!=8'h55)||(wire_count[i]==7&&in_data[i]!=8'hd5))bad[i]<=1;
    end else bad[i]<=1;
   end else if(previous[i]&&cfg_found[i])begin
    if(!discard[i]&&!bad[i]&&wire_count[i]>=72&&wire_count[i]<=1526&&wire_count[i]-8<=network_cfg[cfg_match[i]*168+152+:16]&&crc[i]==32'hdebb20e3)begin
     frame_length[i*4+wptr[i]]<=wire_count[i];frame_vl[i*4+wptr[i]]<=cfg_match[i];wptr[i]<=wptr[i]+1'b1;push[i]=1;
    end else begin drop_inc=drop_inc+1'b1;if(discard[i])overflow_inc=overflow_inc+1'b1;end
   end
  end
  for(i=0;i<PORTS;i=i+1)begin
   if(active[i]&&REASSEMBLY_TIMEOUT!=0&&!(state>=CONTEXT&&state<=VERIFY&&vl==i))begin
    if(ages[i]>=REASSEMBLY_TIMEOUT-1)begin active[i]<=0;timeout_inc=timeout_inc+1'b1;end else ages[i]<=ages[i]+1'b1;
   end
   if(freshness_age[i]!=32'hffffffff)freshness_age[i]<=freshness_age[i]+1'b1;
   if(sampling[i])begin if(publish&&vl==i)message_count[i]<=1;end
   else case({publish&&vl==i,consume&&out_vl==i})2'b10:message_count[i]<=message_count[i]+1'b1;2'b01:message_count[i]<=message_count[i]-1'b1;default:;endcase
  end
  case(state)
   IDLE:if(used[0]!=0||used[1]!=0)begin owner<=choice_network;rr<=choice_network;frame_slot<={choice_network,rptr[choice_network]};vl<=frame_vl[{choice_network,rptr[choice_network]}];state<=HEADER;end
   HEADER:begin
    ip_total<=f16(24);ip_id<=f16(26);mf<=frame_mem[frame_slot*1536+28][5];frag_offset<=(f16(28)&16'h1fff)<<3;frag_length<=f16(24)-20;
    vl<=port_match;udp_len<=f16(46);udp_checksum<=f16(48);sequence_number<=frame_mem[frame_slot*1536+frame_length[frame_slot]-5];checksum_index<=0;ip_sum<=0;
    if(!port_match_valid||f16(20)!=16'h0800||frame_mem[frame_slot*1536+22]!=8'h45||frame_mem[frame_slot*1536+31]!=17||frame_mem[frame_slot*1536+30]==0||frame_mem[frame_slot*1536+14][0]||
     f32(34)!=network_cfg[vl[1:0]*168+56+:32]||f32(38)!=network_cfg[vl[1:0]*168+88+:32]||f16(24)<21||
     frame_length[frame_slot]!=(f16(24)+27<72?16'd72:f16(24)+27)||(f16(28)&16'h8000)!=0||
     ((f16(28)&16'h4000)!=0&&(f16(28)&16'h3fff)!=0)||
     ((f16(28)&16'h2000)!=0&&((f16(24)-20)&7)!=0)||
     ((f16(28)&16'h1fff)*8+(f16(24)-20)>port_capacity(port_match)+8)||
     ((f16(28)&16'h1fff)==0&&(f16(24)<28||f16(46)<9||f16(46)>port_capacity(port_match)+8))||
     (sampling[port_match]&&(f16(28)&16'h3fff)!=0))begin drop_inc=drop_inc+1'b1;state<=RELEASE;end
    else state<=IP_SUM;
   end
   IP_SUM:begin ip_sum<=ip_sum+f16(22+checksum_index*2);if(checksum_index==9)state<=IP_CHECK;else checksum_index<=checksum_index+1'b1;end
   IP_CHECK:if(folded(ip_sum)!=16'hffff)begin drop_inc=drop_inc+1'b1;state<=RELEASE;end else state<=IC;
   IC:if(ic_ready)state<=WAIT_IC;
   WAIT_IC:if(ic_accept)state<=CONTEXT;else if(ic_duplicate||ic_stale)state<=RELEASE;
   CONTEXT:begin
    if(!sampling[vl]&&message_count[vl]==2)begin drop_inc=drop_inc+1'b1;overflow_inc=overflow_inc+1'b1;state<=RELEASE;end
    else if(!active[vl])fresh_context;
    else if(context_id[vl]!=ip_id)begin
     if(frag_offset==0)begin reassembly_errors<=reassembly_errors+1'b1;fresh_context;end
     else begin drop_inc=drop_inc+1'b1;state<=RELEASE;end
    end else state<=START_FRAGMENT;
   end
   START_FRAGMENT:begin
    ages[vl]<=0;index<=0;
    if((last_seen[vl]&&frag_offset+frag_length>last_end[vl])||
       (first_seen[vl]&&frag_offset+frag_length>expected_length[vl])||
       (!mf&&last_seen[vl]&&frag_offset+frag_length!=last_end[vl]))abandon;
    else begin
     if(frag_offset==0)begin first_seen[vl]<=1;expected_length[vl]<=udp_len;checksums[vl]<=udp_checksum;end
     if(!mf)begin last_seen[vl]<=1;last_end[vl]<=frag_offset+frag_length;end
     state<=COPY;
    end
   end
   COPY:begin
    if(seen[vl][absolute_byte>>3])begin
     if(data_mem[message_address(vl,message_wp[vl],absolute_byte)]!=copy_byte)abandon;
     else if(index==frag_length-1)state<=VERIFY;else index<=index+1'b1;
    end else begin
     data_mem[message_address(vl,message_wp[vl],absolute_byte)]<=copy_byte;filled[vl]<=filled[vl]+1'b1;
     if(!absolute_byte[0])word_high<=copy_byte;
     if(absolute_byte[0])udp_sums[vl]<=udp_sums[vl]+{word_high,copy_byte};
     else if(index==frag_length-1)udp_sums[vl]<=udp_sums[vl]+{copy_byte,8'd0};
     if(absolute_byte[2:0]==7||index==frag_length-1)seen[vl][absolute_byte>>3]<=1;
     if(index==frag_length-1)state<=VERIFY;else index<=index+1'b1;
    end
   end
   VERIFY:begin
    if(first_seen[vl]&&(filled[vl]>expected_length[vl]||(last_seen[vl]&&last_end[vl]!=expected_length[vl])))abandon;
    else if(complete)begin
     if(!udp_ok)abandon;
     else begin message_length[vl*3+message_wp[vl]]<=expected_length[vl]-8;message_network[vl*3+message_wp[vl]]<=context_network[vl];if(sampling[vl])latest[vl]<=message_wp[vl];else message_wp[vl]<=message_wp[vl]^2'd1;freshness_age[vl]<=0;unread[vl]<=1;active[vl]<=0;messages<=messages+1'b1;state<=RELEASE;end
    end else state<=RELEASE;
   end
   RELEASE:begin pop[owner]=1;state<=IDLE;end
  endcase
  case(out_state)
   0:if(begin_read)begin
    out_vl<=selected_read_port;out_slot<=sampling[selected_read_port]?latest[selected_read_port]:message_rp[selected_read_port];out_rr<=selected_read_port;out_index<=0;
    out_length<=message_length[selected_read_port*3+(sampling[selected_read_port]?latest[selected_read_port]:message_rp[selected_read_port])];
    payload_fresh<=!sampling[selected_read_port]||FRESHNESS_CYCLES==0||freshness_age[selected_read_port]<FRESHNESS_CYCLES;
    if(!(publish&&vl==selected_read_port))unread[selected_read_port]<=0;
    out_state<=1;
   end
   1:begin payload_data<=data_mem[message_address(out_vl,out_slot,8+out_index)];out_state<=2;end
   2:if(payload_ready)begin if(payload_eof)begin if(!sampling[out_vl])message_rp[out_vl]<=message_rp[out_vl]^2'd1;out_state<=0;end else begin payload_data<=data_mem[message_address(out_vl,out_slot,9+out_index)];out_index<=out_index+1'b1;out_state<=2;end end
  endcase
  for(i=0;i<2;i=i+1)begin
   if(pop[i])rptr[i]<=rptr[i]+1'b1;
   case({push[i],pop[i]})2'b10:used[i]<=used[i]+1'b1;2'b01:used[i]<=used[i]-1'b1;default:;endcase
  end
  if(drop_inc!=0)dropped<=dropped+drop_inc;
  if(overflow_inc!=0)overflows<=overflows+overflow_inc;
  if(timeout_inc!=0)timeouts<=timeouts+timeout_inc;
 end
end
endmodule