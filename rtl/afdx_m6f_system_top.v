`timescale 1ns/1ps
// M6 integration: true variable business payloads, independent management GMII.
module afdx_m6f_system_top #(
    parameter integer CLK_HZ = 100_000_000,
    parameter integer MANAGEMENT_BAG_CYCLES = 400000,
    parameter integer RX_SKEW_MAX_CYCLES = 16_000_000,
    parameter integer RX_CONFIGURABLE=0
)(
    input wire [671:0] rx_cfg_table,
    output wire [799:0] mib_live,
    input wire clk, rst,
    input wire tx_enable, network_a_enable, network_b_enable,
    input wire cfg_we,
    input wire [1:0] cfg_vl_id,
    input wire [31:0] cfg_bag,
    input wire [7:0] cfg_destination,
    input wire app_wr_en,
    input wire [1:0] app_wr_vl_id,
    input wire [7:0] app_wr_data,
    input wire [15:0] app_wr_len,
    input wire app_wr_sof, app_wr_eof,
    input wire [15:0] cfg_lmax,
    output wire app_wr_ready, app_len_error,
    output wire app_wr_accept,
    input wire fault_enable,
    output wire [7:0] data_a_txd, data_b_txd,
    output wire data_a_tx_en, data_b_tx_en, data_a_tx_er, data_b_tx_er,
    output wire data_a_done, data_b_done,
    input wire [7:0] data_a_rxd, data_b_rxd,
    input wire data_a_rx_dv, data_b_rx_dv, data_a_rx_er, data_b_rx_er,
    output wire [7:0] payload_data,
    output wire payload_valid, payload_sof, payload_eof, payload_network,
    input wire payload_ready,
    input wire [7:0] management_rxd,
    input wire management_rx_dv, management_rx_er,
    output wire [7:0] management_txd,
    output wire management_tx_en, management_tx_er, management_done,
    output wire management_busy, management_commit,
    output wire management_response_done, management_response_error,
    output wire [7:0] management_error_code
);
wire [7:0] raw_b_txd;
wire raw_b_en, raw_b_er, raw_b_done, raw_b_underrun, a_underrun, b_underrun;
wire active_a, active_b, degraded, fault_applied;
wire redundancy_ok, frame_match, byte_match;
wire [31:0] accepted, accepted_a, accepted_b, duplicate, cross_duplicate, same_repeat, stale, gap;
wire [31:0] tx_a_frames, tx_b_frames, tx_a_bytes, tx_b_bytes, mismatches, skew, done_skew;
wire [31:0] er_mismatch, a_errors, b_errors, a_underruns, b_underruns;
wire m5_tx_app_len_error;
wire m5_tx_fork_fire_dbg;
wire [7:0] m5_tx_a_stream_data_dbg;
wire m5_tx_a_stream_valid_dbg;
wire m5_tx_a_stream_ready_dbg;
wire [7:0] m5_tx_b_stream_data_dbg;
wire m5_tx_b_stream_valid_dbg;
wire m5_tx_b_stream_ready_dbg;
wire m5_tx_redundant_frame_done_dbg;
wire m5_tx_any_network_enabled_dbg;
wire m5_tx_core_busy;
wire m5_tx_core_frame_done;
wire [1:0] m5_tx_scheduler_mode_active_dbg;
wire m5_tx_schedule_fire_dbg;
wire m5_tx_frame_start_dbg;
wire m5_tx_commit_valid_dbg;
wire [1:0] m5_tx_commit_vl_id_dbg;
wire [7:0] m5_tx_commit_data_dbg;
wire [7:0] m5_tx_commit_seq_dbg;
wire [1:0] m5_tx_selected_vl_dbg;
wire [7:0] m5_tx_selected_seq_dbg;
wire [7:0] m5_tx_selected_destination_dbg;
wire [1:0] m5_tx_policy_selected_priority_dbg;
wire [7:0] m5_tx_policy_selected_age_dbg;
wire [8:0] m5_tx_policy_selected_score_dbg;
wire [7:0] m5_tx_ba_wait_age0_dbg;
wire [7:0] m5_tx_ba_wait_age1_dbg;
wire [7:0] m5_tx_ba_wait_age2_dbg;
wire [7:0] m5_tx_ba_wait_age3_dbg;
wire [3:0] m5_tx_bag_ready_metrics_dbg;
wire [3:0] m5_tx_eligible_metrics_dbg;
wire [7:0] m5_tx_core_stream_data_dbg;
wire m5_tx_core_stream_valid_dbg;
wire m5_tx_core_stream_ready_dbg;
wire [2:0] m5_tx_fifo_count0_dbg;
wire [2:0] m5_tx_fifo_count1_dbg;
wire [2:0] m5_tx_fifo_count2_dbg;
wire [2:0] m5_tx_fifo_count3_dbg;
wire [7:0] m5_tx_seq0_dbg;
wire [7:0] m5_tx_seq1_dbg;
wire [7:0] m5_tx_seq2_dbg;
wire [7:0] m5_tx_seq3_dbg;
wire m5_rx_accept_event;
wire m5_rx_duplicate_event;
wire m5_rx_stale_event;
wire m5_rx_gap_event;
wire m5_rx_a_candidate_valid;
wire m5_rx_a_candidate_outstanding;
wire m5_rx_b_candidate_valid;
wire m5_rx_b_candidate_outstanding;
wire m5_rx_a_l2_crc_error;
wire m5_rx_b_l2_crc_error;
wire m5_rx_a_unknown_vl_error;
wire m5_rx_b_unknown_vl_error;
wire m5_rx_a_commit_overflow_error;
wire m5_rx_b_commit_overflow_error;
wire m5_rx_decision_arb_valid;
wire m5_rx_decision_arb_network;
wire m5_rx_payload_frame_active;
wire m5_redundancy_fault_event;
wire [15:0] m5_fault_active_byte_index;
wire management_rx_result_valid, management_rx_accept, management_rx_reject, management_crc_error, management_boundary_busy;
wire management_response_valid;
wire management_builder_start, management_builder_done, management_underrun;
wire [7:0] management_sequence_num;
reg [31:0] uptime_divider,uptime_ticks,live_events;
reg redundancy_previous;
always @(posedge clk)begin
 if(rst)begin uptime_divider<=0;uptime_ticks<=0;live_events<=0;redundancy_previous<=0;end
 else begin
  if(uptime_divider>=CLK_HZ/100-1)begin uptime_divider<=0;uptime_ticks<=uptime_ticks+1'b1;end
  else uptime_divider<=uptime_divider+1'b1;
  redundancy_previous<=redundancy_ok;
  if(redundancy_previous&&!redundancy_ok)live_events[0]<=1;
  if(fault_applied)live_events[1]<=1;
 end
end
afdx_business_tx_varlen #(.CONFIGURABLE_NETWORK(RX_CONFIGURABLE)) u_m5_tx (
    .network_cfg(rx_cfg_table),
    .clk(clk),.rst(rst),.tx_enable(tx_enable),.network_a_enable(network_a_enable),.network_b_enable(network_b_enable),
    .cfg_we(cfg_we),.cfg_vl_id(cfg_vl_id),.cfg_bag(cfg_bag),.cfg_lmax(cfg_lmax),.cfg_destination(cfg_destination),
    .app_wr_en(app_wr_en),.app_wr_vl_id(app_wr_vl_id),.app_wr_data(app_wr_data),.app_wr_len(app_wr_len),
    .app_wr_sof(app_wr_sof),.app_wr_eof(app_wr_eof),.app_wr_accept(app_wr_accept),.app_wr_ready(app_wr_ready),.app_len_error(app_len_error),
    .gmii_a_txd(data_a_txd),.gmii_a_tx_en(data_a_tx_en),.gmii_a_tx_er(data_a_tx_er),.gmii_a_frame_done(data_a_done),.gmii_a_underrun(a_underrun),
    .gmii_b_txd(raw_b_txd),.gmii_b_tx_en(raw_b_en),.gmii_b_tx_er(raw_b_er),.gmii_b_frame_done(raw_b_done),.gmii_b_underrun(raw_b_underrun),
    .network_a_active(active_a),.network_b_active(active_b),.degraded_mode(degraded),.busy(m5_tx_core_busy),
    .frame_start(m5_tx_frame_start_dbg),.selected_vl(m5_tx_selected_vl_dbg),.selected_seq(m5_tx_selected_seq_dbg));
gmii_fault_injector u_m5_fault (
    .clk(clk),.rst_n(!rst),.in_txd(raw_b_txd),.in_tx_en(raw_b_en),.in_tx_er(raw_b_er),
    .in_frame_done(raw_b_done),.in_underrun(raw_b_underrun),.fault_enable(fault_enable),
    .corrupt_byte_enable(1'b1),.corrupt_byte_index(16'd50),.corrupt_xor_mask(8'h01),
    .drop_byte_enable(1'b0),.drop_byte_index(16'd0),.tx_error_byte_enable(1'b0),
    .tx_error_byte_index(16'd0),.drop_frame_done_enable(1'b0),.mute_link(1'b0),
    .out_txd(data_b_txd),.out_tx_en(data_b_tx_en),.out_tx_er(data_b_tx_er),
    .out_frame_done(data_b_done),.out_underrun(b_underrun),.active_byte_index_dbg(m5_fault_active_byte_index),.fault_applied_dbg(fault_applied));
redundancy_integrity_monitor u_m5_monitor (
    .clk(clk),.rst_n(!rst),.monitor_clear(1'b0),.monitor_enable(1'b1),
    .gmii_a_txd(data_a_txd),.gmii_a_tx_en(data_a_tx_en),.gmii_a_tx_er(data_a_tx_er),
    .gmii_a_frame_done(data_a_done),.gmii_a_underrun(a_underrun),
    .gmii_b_txd(data_b_txd),.gmii_b_tx_en(data_b_tx_en),.gmii_b_tx_er(data_b_tx_er),
    .gmii_b_frame_done(data_b_done),.gmii_b_underrun(b_underrun),
    .redundancy_ok(redundancy_ok),.fault_event(m5_redundancy_fault_event),.frame_count_match(frame_match),.active_byte_count_match(byte_match),
    .a_frame_count(tx_a_frames),.b_frame_count(tx_b_frames),.a_active_byte_count(tx_a_bytes),
    .b_active_byte_count(tx_b_bytes),.byte_mismatch_count(mismatches),.frame_skew_cycle_count(skew),
    .frame_done_skew_count(done_skew),.tx_er_mismatch_count(er_mismatch),
    .a_tx_error_cycle_count(a_errors),.b_tx_error_cycle_count(b_errors),
    .a_underrun_count(a_underruns),.b_underrun_count(b_underruns));
afdx_rx_dual_frontend #(.SKEW_MAX_CYCLES(RX_SKEW_MAX_CYCLES),.RX_CONFIGURABLE(RX_CONFIGURABLE)) u_m5_rx (
    .rx_cfg_table(rx_cfg_table),
    .clk(clk),.rst(rst),.clear(1'b0),
    .gmii_a_rxd(data_a_rxd),.gmii_a_rx_dv(data_a_rx_dv),.gmii_a_rx_er(data_a_rx_er),
    .gmii_b_rxd(data_b_rxd),.gmii_b_rx_dv(data_b_rx_dv),.gmii_b_rx_er(data_b_rx_er),
    .payload_data(payload_data),.payload_valid(payload_valid),.payload_ready(payload_ready),
    .payload_sof(payload_sof),.payload_eof(payload_eof),.payload_network(payload_network),
    .accepted_count(accepted),.accepted_a_count(accepted_a),.accepted_b_count(accepted_b),
    .duplicate_count(duplicate),.cross_network_duplicate_count(cross_duplicate),
    .same_network_repeat_count(same_repeat),.stale_count(stale),.sequence_gap_count(gap),.accept_event(m5_rx_accept_event),.duplicate_event(m5_rx_duplicate_event),.stale_event(m5_rx_stale_event),.gap_event(m5_rx_gap_event),.a_candidate_valid(m5_rx_a_candidate_valid),.a_candidate_outstanding(m5_rx_a_candidate_outstanding),.b_candidate_valid(m5_rx_b_candidate_valid),.b_candidate_outstanding(m5_rx_b_candidate_outstanding),.a_l2_crc_error(m5_rx_a_l2_crc_error),.b_l2_crc_error(m5_rx_b_l2_crc_error),.a_unknown_vl_error(m5_rx_a_unknown_vl_error),.b_unknown_vl_error(m5_rx_b_unknown_vl_error),.a_commit_overflow_error(m5_rx_a_commit_overflow_error),.b_commit_overflow_error(m5_rx_b_commit_overflow_error),.decision_arb_valid(m5_rx_decision_arb_valid),.decision_arb_network(m5_rx_decision_arb_network),.payload_frame_active(m5_rx_payload_frame_active));
afdx_m6e_management_top #(.CLK_HZ(CLK_HZ),.BAG_CYCLES(MANAGEMENT_BAG_CYCLES)) u_management (
    .clk(clk),.rst(rst),.gmii_rxd(management_rxd),.gmii_rx_dv(management_rx_dv),.gmii_rx_er(management_rx_er),
    .cfg_src_mac(48'h020000000001),.cfg_dst_mac(48'h020000000002),.cfg_src_ip(32'hc0a80101),
    .gmii_txd(management_txd),.gmii_tx_en(management_tx_en),.gmii_tx_er(management_tx_er),
    .tx_frame_done(management_done),.busy(management_busy),.rx_commit(management_commit),
    .rx_result_valid(management_rx_result_valid),.rx_accept(management_rx_accept),.rx_reject(management_rx_reject),
    .crc_error(management_crc_error),.boundary_busy(management_boundary_busy),
    .response_done(management_response_done),.response_valid(management_response_valid),.response_error(management_response_error),
    .response_error_code(management_error_code),
    .builder_start(management_builder_start),.builder_done(management_builder_done),.underrun(management_underrun),.sequence_num(management_sequence_num),
    .m5_network_a_enable(active_a),.m5_network_b_enable(active_b),.m5_degraded_mode(degraded),
    .m5_redundancy_ok(redundancy_ok),.m5_frame_count_match(frame_match),.m5_active_byte_count_match(byte_match),
    .m5_fault_applied_event(fault_applied),.m5_rx_accepted_count(accepted),
    .m5_rx_accepted_a_count(accepted_a),.m5_rx_accepted_b_count(accepted_b),
    .m5_rx_duplicate_count(duplicate),.m5_rx_cross_network_duplicate_count(cross_duplicate),
    .m5_rx_same_network_repeat_count(same_repeat),.m5_rx_stale_count(stale),.m5_rx_sequence_gap_count(gap),
    .m5_tx_a_frame_count(tx_a_frames),.m5_tx_b_frame_count(tx_b_frames),
    .m5_tx_a_active_byte_count(tx_a_bytes),.m5_tx_b_active_byte_count(tx_b_bytes),
    .m5_tx_byte_mismatch_count(mismatches),.m5_tx_frame_skew_cycle_count(skew),
    .m5_tx_frame_done_skew_count(done_skew),.m5_tx_er_mismatch_count(er_mismatch),
    .m5_tx_a_error_cycle_count(a_errors),.m5_tx_b_error_cycle_count(b_errors),
    .m5_tx_a_underrun_count(a_underruns),.m5_tx_b_underrun_count(b_underruns));
assign mib_live[0*32+:32]=32'h00060a01;
assign mib_live[1*32+:32]=32'd0;
assign mib_live[2*32+:32]=uptime_ticks;
assign mib_live[3*32+:32]={26'd0,byte_match,frame_match,redundancy_ok,degraded,active_b,active_a};
assign mib_live[4*32+:32]=live_events;
assign mib_live[5*32+:32]=accepted;
assign mib_live[6*32+:32]=accepted_a;
assign mib_live[7*32+:32]=accepted_b;
assign mib_live[8*32+:32]=duplicate;
assign mib_live[9*32+:32]=cross_duplicate;
assign mib_live[10*32+:32]=same_repeat;
assign mib_live[11*32+:32]=stale;
assign mib_live[12*32+:32]=gap;
assign mib_live[13*32+:32]=tx_a_frames;
assign mib_live[14*32+:32]=tx_b_frames;
assign mib_live[15*32+:32]=tx_a_bytes;
assign mib_live[16*32+:32]=tx_b_bytes;
assign mib_live[17*32+:32]=mismatches;
assign mib_live[18*32+:32]=skew;
assign mib_live[19*32+:32]=done_skew;
assign mib_live[20*32+:32]=er_mismatch;
assign mib_live[21*32+:32]=a_errors;
assign mib_live[22*32+:32]=b_errors;
assign mib_live[23*32+:32]=a_underruns;
assign mib_live[24*32+:32]=b_underruns;
endmodule
