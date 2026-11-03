`timescale 1ns/1ps
// External plugin: unchanged baseline MAC byte ports, independent control plane.
module afdx_security_plugin #(
 parameter integer BOOT_MODE=2,CLK_HZ=12500000,QUEUE_SLOTS=4,CONTEXTS=8,HISTORY=16,MAX_WIRE=1536,
 parameter integer TIME_SAMPLE_CYCLES=CLK_HZ/100
)(
 input wire clk,rst,
 input wire [7:0] a_rx,b_rx,a_tx,b_tx,input wire a_rx_valid,b_rx_valid,a_rx_error,b_rx_error,
 input wire a_tx_valid,b_tx_valid,a_tx_error,b_tx_error,
 output wire [7:0] core_a_rx,core_b_rx,output wire core_a_valid,core_b_valid,core_a_error,core_b_error,
 input wire core_safe,input wire [255:0] target_id,input wire rtc_locked,
 input wire [63:0] utc_ntp,monotonic_ticks,input wire time_reanchor,
 input wire cfg_write,cfg_read,input wire [15:0] cfg_address,input wire [31:0] cfg_wdata,
 output wire cfg_ready,cfg_error,cfg_pending,cfg_commit_pulse,output wire [31:0] cfg_rdata,
 output wire [1:0] mode,output wire [31:0] epoch,
 output wire event_valid,input wire event_ready,output wire [159:0] event_record,
 output wire alarm,output wire [3:0] time_flags,output wire [31:0] time_alarms,
 output wire [31:0] would_allow,would_block,queue_overflows,event_overflows,ab_conflicts,hash_failures,
 output wire idle
);
reg [63:0] cycle;always @(posedge clk)begin if(rst)cycle<=0;else cycle<=cycle+1'b1;end
wire [8191:0] rules;wire [16383:0] grants;wire [511:0] floors;wire [15:0] floor_loaded;
wire [31:0] ab_window,ntp_rtt;wire [63:0] jump_limit,committed_at;
wire [3:0] requests,goods,takes,queue_idle;wire [255:0] stamps;wire [4*MAX_WIRE*8-1:0] packets;wire [43:0] lengths;
wire [127:0] lost;wire [7:0] data[0:3];wire [3:0] valids={b_tx_valid,a_tx_valid,b_rx_valid,a_rx_valid};wire [3:0] errors={b_tx_error,a_tx_error,b_rx_error,a_rx_error};
assign data[0]=a_rx;assign data[1]=b_rx;assign data[2]=a_tx;assign data[3]=b_tx;
genvar g;generate for(g=0;g<4;g=g+1)begin:CAPTURE
 afdx_sec_frame_queue #(.SLOTS(QUEUE_SLOTS),.MAX_WIRE(MAX_WIRE)) q(.clk(clk),.rst(rst),.cycle(cycle),.data(data[g]),.valid(valids[g]),.error(errors[g]),.request(requests[g]),.packet(packets[g*MAX_WIRE*8+:MAX_WIRE*8]),.length(lengths[g*11+:11]),.stamp(stamps[g*64+:64]),.good(goods[g]),.take(takes[g]),.idle(queue_idle[g]),.overflows(lost[g*32+:32]));
end endgenerate
assign queue_overflows=lost[31:0]+lost[63:32]+lost[95:64]+lost[127:96];
wire engine_idle,sessions_idle;wire [1:0] replay_start,replay_ready,replay_idle;wire [MAX_WIRE*8-1:0] replay_packet;wire [10:0] replay_length;wire [15:0] replay_data;wire [1:0] replay_valid,replay_error;
generate for(g=0;g<2;g=g+1)begin:REPLAY
 afdx_sec_replay #(.MAX_WIRE(MAX_WIRE)) r(.clk(clk),.rst(rst),.start(replay_start[g]),.packet(replay_packet),.length(replay_length),.ready(replay_ready[g]),.data(replay_data[g*8+:8]),.valid(replay_valid[g]),.error(replay_error[g]),.idle(replay_idle[g]));
end endgenerate
// The bypass/shadow path is combinational and preserves error and timing too.
assign core_a_rx=mode==2?replay_data[7:0]:a_rx;assign core_b_rx=mode==2?replay_data[15:8]:b_rx;
assign core_a_valid=mode==2?replay_valid[0]:a_rx_valid;assign core_b_valid=mode==2?replay_valid[1]:b_rx_valid;
assign core_a_error=mode==2?replay_error[0]:a_rx_error;assign core_b_error=mode==2?replay_error[1]:b_rx_error;
assign idle=(&queue_idle)&&engine_idle&&(&replay_idle);
wire safe=idle&&sessions_idle&&core_safe;
wire [31:0] policy_rdata;wire policy_error;
wire evidence_ack=cfg_write===1'b1&&cfg_ready&&cfg_address==16'h2000&&cfg_wdata==32'h41434b31;
wire evidence_valid;wire [MAX_WIRE*8-1:0] evidence_first,evidence_second;
wire [10:0] evidence_first_length,evidence_second_length;wire [15:0] evidence_offset;
wire [63:0] evidence_first_stamp,evidence_second_stamp;wire [31:0] evidence_lost,evidence_epoch;
wire [3:0] evidence_rule;wire [1:0] evidence_channel;
reg evidence_error;always @(posedge clk)begin
 if(rst)evidence_error<=0;else evidence_error<=cfg_write===1'b1&&cfg_address>=16'h2000&&(!evidence_ack);
end
assign cfg_error=policy_error||evidence_error;
reg [31:0] evidence_rdata;
always @*begin
 evidence_rdata=0;
 case(cfg_address)
  16'h2000:evidence_rdata={31'd0,evidence_valid};
  16'h2004:evidence_rdata={16'd0,evidence_offset};
  16'h2008:evidence_rdata={21'd0,evidence_first_length};
  16'h200c:evidence_rdata={21'd0,evidence_second_length};
  16'h2010:evidence_rdata=evidence_first_stamp[31:0];
  16'h2014:evidence_rdata=evidence_first_stamp[63:32];
  16'h2018:evidence_rdata=evidence_second_stamp[31:0];
  16'h201c:evidence_rdata=evidence_second_stamp[63:32];
  16'h2020:evidence_rdata=evidence_lost;
  16'h2024:evidence_rdata=evidence_epoch;
  16'h2028:evidence_rdata={26'd0,evidence_rule,evidence_channel};
 endcase
 if(cfg_address>=16'h2100&&cfg_address<16'h2100+MAX_WIRE)evidence_rdata=evidence_first[((cfg_address-16'h2100)>>2)*32+:32];
 if(cfg_address>=16'h2900&&cfg_address<16'h2900+MAX_WIRE)evidence_rdata=evidence_second[((cfg_address-16'h2900)>>2)*32+:32];
end
afdx_sec_policy #(.BOOT_MODE(BOOT_MODE)) policy(.clk(clk),.rst(rst),.safe(safe),.write(cfg_write===1'b1&&cfg_address<16'h2000),.read(cfg_read),.address(cfg_address),.wdata(cfg_wdata),.ready(cfg_ready),.error(policy_error),.pending(cfg_pending),.commit_pulse(cfg_commit_pulse),.rdata(policy_rdata),.mode(mode),.epoch(epoch),.ab_window(ab_window),.ntp_rtt_limit(ntp_rtt),.time_jump_limit(jump_limit),.rules(rules),.grants(grants),.floors(floors),.floor_loaded(floor_loaded),.committed_at(committed_at),.cycle(cycle));
wire push;wire [159:0] record;wire [31:0] observed,context_timeouts;
afdx_sec_engine #(.MAX_WIRE(MAX_WIRE),.CONTEXTS(CONTEXTS),.HISTORY(HISTORY),.CLK_HZ(CLK_HZ)) engine(
 .clk(clk),.rst(rst),.clear(cfg_commit_pulse),.mode(mode),.rules(rules),.grants(grants),.floors(floors),.floor_loaded(floor_loaded),.epoch(epoch),.ab_window(ab_window),.ntp_rtt_limit(ntp_rtt),.committed_at(committed_at),.time_jump_limit(jump_limit),.cycle(cycle),.target_id(target_id),.requests(requests),.goods(goods),.packets(packets),.lengths(lengths),.stamps(stamps),.take(takes),.replay_start(replay_start),.replay_packet(replay_packet),.replay_length(replay_length),.replay_ready(replay_ready),.idle(engine_idle),.sessions_idle(sessions_idle),.event_push(push),.event_record(record),.accepted(would_allow),.blocked(would_block),.observed(observed),.ab_conflicts(ab_conflicts),.hash_failures(hash_failures),.context_timeouts(context_timeouts),.evidence_ack(evidence_ack),.evidence_valid(evidence_valid),.evidence_first(evidence_first),.evidence_second(evidence_second),.evidence_first_length(evidence_first_length),.evidence_second_length(evidence_second_length),.evidence_offset(evidence_offset),.evidence_first_stamp(evidence_first_stamp),.evidence_second_stamp(evidence_second_stamp),.evidence_lost(evidence_lost),.evidence_epoch(evidence_epoch),.evidence_rule(evidence_rule),.evidence_channel(evidence_channel));
afdx_sec_events events(.clk(clk),.rst(rst),.push(push),.record(record),.valid(event_valid),.ready(event_ready!==1'b0),.data(event_record),.lost(event_overflows));
wire time_pulse;
afdx_sec_time_monitor #(.CLK_HZ(CLK_HZ),.SAMPLE_CYCLES(TIME_SAMPLE_CYCLES>0?TIME_SAMPLE_CYCLES:1)) time_monitor(.clk(clk),.rst(rst),.reanchor(time_reanchor||cfg_commit_pulse),.locked(rtc_locked),.utc(utc_ntp),.monotonic(monotonic_ticks),.limit(jump_limit),.pulse(time_pulse),.flags(time_flags),.alarms(time_alarms));
reg sticky_alarm;always @(posedge clk)begin if(rst)sticky_alarm<=0;else if((push&&record[63:48]!=0)||time_pulse||queue_overflows!=0||event_overflows!=0)sticky_alarm<=1;end
assign alarm=sticky_alarm;
assign cfg_rdata=cfg_address>=16'h2000 ?evidence_rdata:cfg_address==16'h40 ?would_allow:cfg_address==16'h44 ?would_block:cfg_address==16'h48 ?queue_overflows:cfg_address==16'h4c ?event_overflows:cfg_address==16'h50 ?ab_conflicts:cfg_address==16'h54 ?hash_failures:cfg_address==16'h58 ?time_alarms:cfg_address==16'h5c ?context_timeouts:cfg_address==16'h60 ?observed:policy_rdata;
endmodule
