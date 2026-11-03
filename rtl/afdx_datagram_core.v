`timescale 1ns/1ps
module afdx_datagram_core #(
 parameter integer EXTENDED_PORTS=0,SUBVL_MAX_MESSAGE=2048,
 parameter integer CLK_HZ=12500000,MAX_MESSAGE=8192,SKEW_MAX_CYCLES=2000000,REASSEMBLY_TIMEOUT=0,CHECK_UDP=1,AUTO_DRAIN=1,FRESHNESS_CYCLES=12500000,
 parameter [3:0] SAMPLING_MASK=0
)(
 input wire clk,rst,input wire [671:0] network_cfg,input wire [1023:0] port_cfg,
 input wire [1:0] app_wr_subvl,read_subvl,output wire [3:0] payload_port,output wire [15:0] payload_sap,
 input wire tx_enable,network_a_enable,network_b_enable,cfg_we,input wire [1:0] cfg_vl_id,input wire [31:0] cfg_bag,input wire [15:0] cfg_lmax,
 input wire app_wr_en,input wire [1:0] app_wr_vl_id,input wire [7:0] app_wr_data,input wire [15:0] app_wr_len,input wire app_wr_sof,app_wr_eof,
 output wire app_wr_ready,app_wr_accept,app_len_error,input wire fault_enable,
 output wire [7:0] a_txd,b_txd,output wire a_tx_en,b_tx_en,a_tx_er,b_tx_er,
 input wire [7:0] a_rxd,b_rxd,input wire a_rx_dv,b_rx_dv,a_rx_er,b_rx_er,
 output wire [7:0] payload_data,output wire payload_valid,payload_sof,payload_eof,payload_network,input wire payload_ready,
 input wire read_request,input wire [1:0] read_port,output wire read_ready,output wire payload_fresh,
 output wire [15:0] payload_length,output wire [1:0] payload_vl,output wire [799:0] mib_live
);
wire [7:0] raw_b;wire raw_b_en,raw_b_er,adone,bdone,busy,fault_event;
wire [31:0] accepted_a,accepted_b,cross_duplicate,same_repeat,sequence_gap;
wire [31:0] tx_messages,tx_frames,tx_errors,rx_messages,accepted,duplicate,stale,dropped,overflows,reassembly_errors,timeouts;
afdx_datagram_tx #(.MAX_MESSAGE(MAX_MESSAGE),.EXTENDED_PORTS(EXTENDED_PORTS),.SUBVL_MAX_MESSAGE(SUBVL_MAX_MESSAGE),.SAMPLING_MASK(SAMPLING_MASK)) tx(
.clk(clk),.rst(rst),.tx_enable(tx_enable),.network_a_enable(network_a_enable),.network_b_enable(network_b_enable),.network_cfg(network_cfg),.port_cfg(port_cfg),
.cfg_we(cfg_we),.cfg_vl_id(cfg_vl_id),.cfg_bag(cfg_bag),.cfg_lmax(cfg_lmax),.app_wr_subvl(app_wr_subvl),.app_wr_en(app_wr_en),.app_wr_vl_id(app_wr_vl_id),.app_wr_data(app_wr_data),.app_wr_len(app_wr_len),.app_wr_sof(app_wr_sof),.app_wr_eof(app_wr_eof),
.app_wr_ready(app_wr_ready),.app_wr_accept(app_wr_accept),.app_len_error(app_len_error),.a_data(a_txd),.b_data(raw_b),.a_en(a_tx_en),.b_en(raw_b_en),.a_er(a_tx_er),.b_er(raw_b_er),.a_done(adone),.b_done(bdone),.busy(busy),.messages(tx_messages),.frames(tx_frames),.errors(tx_errors));
gmii_fault_injector fault(.clk(clk),.rst_n(!rst),.in_txd(raw_b),.in_tx_en(raw_b_en),.in_tx_er(raw_b_er),.in_frame_done(bdone),.in_underrun(1'b0),.fault_enable(fault_enable),
.corrupt_byte_enable(1'b1),.corrupt_byte_index(16'd50),.corrupt_xor_mask(8'h01),.drop_byte_enable(1'b0),.drop_byte_index(16'd0),.tx_error_byte_enable(1'b0),.tx_error_byte_index(16'd0),.drop_frame_done_enable(1'b0),.mute_link(1'b0),
.out_txd(b_txd),.out_tx_en(b_tx_en),.out_tx_er(b_tx_er),.out_frame_done(),.out_underrun(),.active_byte_index_dbg(),.fault_applied_dbg(fault_event));
afdx_datagram_rx #(.MAX_MESSAGE(MAX_MESSAGE),.EXTENDED_PORTS(EXTENDED_PORTS),.SUBVL_MAX_MESSAGE(SUBVL_MAX_MESSAGE),.SKEW_MAX_CYCLES(SKEW_MAX_CYCLES),.REASSEMBLY_TIMEOUT(REASSEMBLY_TIMEOUT),.CHECK_UDP(CHECK_UDP),.AUTO_DRAIN(AUTO_DRAIN),.FRESHNESS_CYCLES(FRESHNESS_CYCLES),.SAMPLING_MASK(SAMPLING_MASK)) rx(
.clk(clk),.rst(rst),.network_cfg(network_cfg),.port_cfg(port_cfg),.a_data(a_rxd),.b_data(b_rxd),.a_valid(a_rx_dv),.b_valid(b_rx_dv),.a_error(a_rx_er),.b_error(b_rx_er),
.payload_data(payload_data),.payload_valid(payload_valid),.payload_sof(payload_sof),.payload_eof(payload_eof),.payload_network(payload_network),.payload_ready(payload_ready),.read_subvl(read_subvl),.payload_port(payload_port),.payload_sap(payload_sap),.read_request(read_request),.read_port(read_port),.read_ready(read_ready),.payload_fresh(payload_fresh),.payload_length(payload_length),.payload_vl(payload_vl),
.accepted_a_frames(accepted_a),.accepted_b_frames(accepted_b),.cross_duplicates(cross_duplicate),.same_repeats(same_repeat),.sequence_gaps(sequence_gap),.accepted_frames(accepted),.duplicate_frames(duplicate),.stale_frames(stale),.messages(rx_messages),.dropped(dropped),.overflows(overflows),.reassembly_errors(reassembly_errors),.timeouts(timeouts));
reg [31:0] ticks,divider,events;reg redundancy_previous;
wire [31:0] txa,txb,bytesa,bytesb,mismatches,skew,done_skew,er_mismatch,a_errors,b_errors,a_underruns,b_underruns;
wire redundancy_ok,frame_match,byte_match;
redundancy_integrity_monitor monitor(.clk(clk),.rst_n(!rst),.monitor_clear(1'b0),.monitor_enable(1'b1),
.gmii_a_txd(a_txd),.gmii_a_tx_en(a_tx_en),.gmii_a_tx_er(a_tx_er),.gmii_a_frame_done(adone),.gmii_a_underrun(1'b0),
.gmii_b_txd(b_txd),.gmii_b_tx_en(b_tx_en),.gmii_b_tx_er(b_tx_er),.gmii_b_frame_done(bdone),.gmii_b_underrun(1'b0),
.redundancy_ok(redundancy_ok),.fault_event(),.frame_count_match(frame_match),.active_byte_count_match(byte_match),
.a_frame_count(txa),.b_frame_count(txb),.a_active_byte_count(bytesa),.b_active_byte_count(bytesb),.byte_mismatch_count(mismatches),.frame_skew_cycle_count(skew),.frame_done_skew_count(done_skew),.tx_er_mismatch_count(er_mismatch),.a_tx_error_cycle_count(a_errors),.b_tx_error_cycle_count(b_errors),.a_underrun_count(a_underruns),.b_underrun_count(b_underruns));
always @(posedge clk)begin
 if(rst)begin ticks<=0;divider<=0;events<=0;redundancy_previous<=0;end
 else begin
  if(divider>=(CLK_HZ/100>0?CLK_HZ/100-1:0))begin ticks<=ticks+1'b1;divider<=0;end else divider<=divider+1'b1;
  redundancy_previous<=redundancy_ok;if(redundancy_previous&&!redundancy_ok)events[0]<=1;if(fault_event)events[1]<=1;
 end
end
assign mib_live[0*32+:32]=32'h00060a01;assign mib_live[1*32+:32]=0;assign mib_live[2*32+:32]=ticks;
assign mib_live[3*32+:32]={26'd0,byte_match,frame_match,redundancy_ok,network_a_enable^network_b_enable,network_b_enable,network_a_enable};
assign mib_live[4*32+:32]=events;assign mib_live[5*32+:32]=accepted;assign mib_live[6*32+:32]=accepted_a;assign mib_live[7*32+:32]=accepted_b;
assign mib_live[8*32+:32]=duplicate;assign mib_live[9*32+:32]=cross_duplicate;assign mib_live[10*32+:32]=same_repeat;assign mib_live[11*32+:32]=stale;assign mib_live[12*32+:32]=sequence_gap;
assign mib_live[13*32+:32]=txa;assign mib_live[14*32+:32]=txb;assign mib_live[15*32+:32]=bytesa;assign mib_live[16*32+:32]=bytesb;
assign mib_live[17*32+:32]=mismatches;assign mib_live[18*32+:32]=skew;assign mib_live[19*32+:32]=done_skew;assign mib_live[20*32+:32]=er_mismatch;assign mib_live[21*32+:32]=a_errors;assign mib_live[22*32+:32]=b_errors;assign mib_live[23*32+:32]=a_underruns;assign mib_live[24*32+:32]=b_underruns;
endmodule