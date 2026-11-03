`timescale 1ns/1ps
// Driven over a trusted simulator-local CSR transport by real host plugins.
module tb_defense_live;
reg clk=0;always #40 clk=~clk;reg rst=1;
reg [7:0] a_rx=0,b_rx=0;reg a_valid=0,b_valid=0;
reg defense_cfg_valid=0,defense_cfg_write=0;reg [15:0] defense_cfg_addr=0;reg [31:0] defense_cfg_wdata=0;
wire defense_cfg_ready,defense_cfg_error;wire [31:0] defense_cfg_rdata;
reg sec_write=0;reg [15:0] sec_addr=0;reg [31:0] sec_wdata=0;
wire sec_ready,sec_error;wire [31:0] sec_rdata;wire [1:0] sec_mode;wire [31:0] sec_epoch;
reg cfg_write=0,cfg_seal=0,poll=0;wire cfg_ready,cfg_error;
reg [167:0] cfg_entry;reg inject=0;reg [3:0] inject_index=0;
reg [12287:0] packets[0:15];reg [15:0] lengths[0:15];
wire [7:0] a_tx,b_tx,payload;wire a_en,b_en,pv,ps,pe;
wire [31:0] forwarded,blocked,timeouts,overflow,ai_results,ai_actions;
wire alarm,ai_block;wire [7:0] candidates;wire [15:0] ai_status;
wire [31:0] sec_allow,sec_block;wire [63:0] utc,mono;wire locked;
reg [15:0] image_address=0;reg [1:0] image_file=0;wire [7:0] image_data;wire [15:0] image_length;wire [31:0] package_generation;
integer errors=0,payload_frames=0,payload_bytes=0,tx_frames=0,raw_frames=0;
reg tx_previous=0;integer index;reg injecting=0;integer wire_log;reg [7:0] payload_log[0:8191];
reg [12287:0] tx_packet=0;integer tx_count=0,tx_length=0;
reg [12287:0] tx_history[0:255];integer tx_sizes[0:255];integer tx_written=0,tx_read=0;
wire [12287:0] tx_head=tx_history[tx_read];wire [31:0] tx_head_length=tx_read<tx_written?tx_sizes[tx_read]:0;
AFDX_defense_top #(.MIMIC_DEADLINE_CYCLES(100000),.AI_BLOCK_CYCLES(5000),.SERVICE_BAG_CYCLES(100),.SERVICE_TIMEOUT_CYCLES(100000)) dut(
 .clk(clk),.rst(rst),.cfg_port_write(1'b0),.cfg_port_index(4'd0),.cfg_port_entry(64'd0),
 .cfg_rx_write(cfg_write),.cfg_rx_seal(cfg_seal),.cfg_rx_index(2'd0),.cfg_rx_entry(cfg_entry),.cfg_rx_ready(cfg_ready),.cfg_rx_error(cfg_error),
 .tx_enable(1'b1),.network_a_enable(1'b1),.network_b_enable(1'b1),.cfg_we(cfg_write),.cfg_vl_id(2'd0),.cfg_bag(32'd12500),.cfg_destination(8'd2),.cfg_lmax(16'd1518),
 .app_wr_en(1'b0),.app_wr_vl_id(2'd0),.app_wr_data(8'd0),.app_wr_len(16'd0),.app_wr_sof(1'b0),.app_wr_eof(1'b0),.app_wr_ready(),.app_len_error(),.app_wr_accept(),
 .app_wr_subvl(2'd0),.app_wr_use_sap(1'b0),.app_wr_sap(16'd0),.app_wr_partition(3'd0),.app_read_partition(3'd0),.app_read_subvl(2'd0),.app_access_error(),.payload_port(),.payload_sap(),
 .fault_enable(1'b0),.data_a_txd(a_tx),.data_b_txd(b_tx),.data_a_tx_en(a_en),.data_b_tx_en(b_en),.data_a_tx_er(),.data_b_tx_er(),.data_a_done(),.data_b_done(),
 .data_a_rxd(a_rx),.data_b_rxd(b_rx),.data_a_rx_dv(a_valid),.data_b_rx_dv(b_valid),.data_a_rx_er(1'b0),.data_b_rx_er(1'b0),
 .payload_data(payload),.payload_valid(pv),.payload_sof(ps),.payload_eof(pe),.payload_network(),.payload_ready(1'b1),.app_read_request(1'b0),.app_read_port(2'd0),.app_read_ready(),.payload_length(),.payload_vl(),.payload_fresh(),
 .management_busy(),.snmp_snapshots(),.snmp_busy_drops(),.shared_rx_accepted(),.shared_rx_duplicates(),.shared_rx_dropped(),.shared_tx_overflows(),.physical_a_frames(),.physical_b_frames(),
 .loader_ip(32'h0a000001),.time_server_ip(32'h0a000101),.hardware_length(6'd3),.hardware_id({232'd0,24'h4d4953}),
 .service_app_domain(1'b0),.service_loaded(),.service_clock_locked(),.app_file(image_file),.rtc_poll(poll),.rtc_locked(locked),.utc_ntp(utc),.monotonic_ticks(mono),
 .image_valid(),.image_length(image_length),.image_crc(),.package_generation(package_generation),.package_file_count(),.image_read_address(image_address),.image_read_data(image_data),.loading(),.load_complete(),.load_failed(),
 .service_cfg_we(1'b0),.service_cfg_domain(1'b0),.service_cfg_loader_ip(32'd0),.service_cfg_clock_ip(32'd0),.service_cfg_enable(1'b0),.service_cfg_commit(1'b0),.service_cfg_ready(),.service_cfg_error(),.service_cfg_pending(),.service_cfg_commit_pulse(),.service_enabled(),
 .sec_cfg_write(sec_write),.sec_cfg_read(1'b1),.sec_cfg_address(sec_addr),.sec_cfg_wdata(sec_wdata),.sec_cfg_ready(sec_ready),.sec_cfg_error(sec_error),.sec_cfg_pending(),.sec_cfg_commit_pulse(),.sec_cfg_rdata(sec_rdata),
 .sec_mode(sec_mode),.sec_epoch(sec_epoch),.sec_event_valid(),.sec_event_ready(1'b1),.sec_event_record(),.sec_alarm(),.sec_time_flags(),.sec_time_alarms(),.sec_would_allow(sec_allow),.sec_would_block(sec_block),.sec_queue_overflows(),.sec_event_overflows(),.sec_ab_conflicts(),.sec_hash_failures(),
 .defense_cfg_valid(defense_cfg_valid),.defense_cfg_write(defense_cfg_write),.defense_cfg_addr(defense_cfg_addr),.defense_cfg_wdata(defense_cfg_wdata),.defense_cfg_ready(defense_cfg_ready),.defense_cfg_error(defense_cfg_error),.defense_cfg_rdata(defense_cfg_rdata),
 .ai_alarm(alarm),.ai_block(ai_block),.ai_candidates(candidates),.ai_status(ai_status),.ai_results(ai_results),.ai_actions(ai_actions),
 .mimic_forwarded(forwarded),.mimic_blocked(blocked),.mimic_timeouts(timeouts),.mimic_overflows(overflow),.mimic_request());
initial begin
 cfg_entry={16'd1518,16'd20000,16'd10000,32'h0a000010,32'h0a000020,48'h030000000040,8'h03};
 repeat(8)@(negedge clk);rst=0;cfg_write=1;@(negedge clk);cfg_write=0;cfg_seal=1;@(negedge clk);cfg_seal=0;
end
always @(negedge clk)begin
 if(!rst)begin
  if(inject&&!injecting)begin injecting=1;index=0;raw_frames=raw_frames+1;end
  a_valid=0;b_valid=0;
  if(injecting)begin
   a_rx=packets[inject_index][index*8+:8];a_valid=1;
   index=index+1;if(index==lengths[inject_index])injecting=0;
  end
 end
end
always @(posedge clk)if(!rst)begin
 if(pv)begin payload_log[payload_bytes]=payload;payload_bytes=payload_bytes+1;if(pe)payload_frames=payload_frames+1;end
 if(a_en)begin
  if(!tx_previous)begin tx_frames=tx_frames+1;tx_count=0;tx_packet=0;end
  tx_packet[tx_count*8+:8]=a_tx;tx_count=tx_count+1;
 end else if(tx_previous)begin
  tx_length=tx_count;
  if(tx_written<256)begin tx_history[tx_written]=tx_packet;tx_sizes[tx_written]=tx_count;tx_written=tx_written+1;end
  else begin errors=errors+1;$display("FAIL DEFENSE reference TX queue overflow");end
 end
 tx_previous=a_en;
 if(cfg_error)begin errors=errors+1;$display("FAIL DEFENSE configuration");end
end
endmodule
