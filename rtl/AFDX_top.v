`timescale 1ns/1ps
// Eight-port demonstration shell.  This wrapper owns only a legal startup
// configuration and a self-contained demo source; configured products use
// AFDX_competition_top directly through its full configuration interface.
// No AI or mimic path is part of this demonstration boundary.
module AFDX_top #(
 parameter integer CLK_HZ=12500000,DEMO_INTERVAL_CYCLES=1250000,
 parameter integer RTC_POLL_CYCLES=12500000,SERVICE_TIMEOUT_CYCLES=12500000,
 parameter [31:0] LOADER_IP=32'h0a000001,TIME_SERVER_IP=32'h0a000101
)(
 input wire clk,
 input wire reset,
 output wire [7:0] tx_data,
 input wire [7:0] rx_data,
 output wire tx_valid,
 input wire rx_valid,
 output wire tx_ready,
 input wire rx_ready
);
 localparam [31:0] DEMO_BAG=CLK_HZ/1000;
 localparam [15:0] DEMO_LMAX=16'd16;
 wire net_enable=rx_ready&&!reset;

 reg [2:0] cfg_state;
 localparam CFG_RX=0,CFG_PORT=1,CFG_SEAL=2,CFG_TX=3,CFG_RUN=4;
 reg [1:0] cfg_index;
 wire cfg_rx_write=(cfg_state==CFG_RX);
 wire cfg_port_write=(cfg_state==CFG_PORT);
 wire cfg_rx_seal=(cfg_state==CFG_SEAL);
 wire cfg_we=(cfg_state==CFG_TX);
 wire [15:0] demo_sport=16'd10000+cfg_index,demo_dport=16'd20000+cfg_index;
 wire [167:0] cfg_rx_entry={16'd1518,demo_dport,demo_sport,
                             32'h0a000010,32'h0a000020+cfg_index,
                             48'h030000000040+cfg_index,6'd0,1'b1,1'b1};
 wire [63:0] cfg_port_entry=64'h0100000000000001;
 wire cfg_rx_ready,cfg_rx_error;
 assign tx_ready=!reset&&cfg_rx_ready&&!cfg_rx_error;

 wire [7:0] a_txd,b_txd;
 wire a_tx_en,b_tx_en,a_tx_er,b_tx_er,a_done,b_done;
 wire [7:0] payload_data;
 wire payload_valid,payload_sof,payload_eof,payload_network;
 wire [15:0] payload_length;
 wire [1:0] payload_vl;
 wire [3:0] payload_port;
 wire app_access_error,app_wr_ready,app_wr_accept,app_len_error;
 wire [31:0] shared_rx_accepted,shared_rx_duplicates,shared_rx_dropped,shared_tx_overflows;
 wire [31:0] physical_a_frames,physical_b_frames;
 wire management_busy;
 wire [31:0] snmp_snapshots,snmp_busy_drops;
 wire [5:0] hardware_length=6'd3;
 wire [255:0] hardware_id={232'd0,24'h4d4953};
 wire [31:0] package_generation,image_crc;
 wire [63:0] utc_ntp,monotonic_ticks;
 wire [15:0] image_length;
 wire [2:0] package_file_count;
 wire [7:0] image_read_data;
 wire image_valid,loading,load_complete,load_failed,rtc_locked;
 wire [0:0] service_loaded,service_clock_locked,service_enabled;
 wire service_cfg_ready,service_cfg_error,service_cfg_pending,service_cfg_commit_pulse;
 reg [1:0] app_wr_vl_id;
 reg [7:0] app_wr_data;
 reg [15:0] app_wr_len;
 reg app_wr_en,app_wr_sof,app_wr_eof;
 reg demo_enable;
 reg [6:0] demo_byte;
 reg [31:0] demo_timer,rtc_counter,frames,received;
 reg [7:0] last_rx;reg [127:0] demo_message;
 reg [15:0] image_address;
 wire rtc_poll=demo_enable&&(rtc_counter==0);
 assign tx_data=a_txd;
 assign tx_valid=a_tx_en;

 always @(posedge clk) begin
  if(reset) begin
   cfg_state<=CFG_RX; cfg_index<=0;
   demo_enable<=0; demo_byte<=0; demo_timer<=0; rtc_counter<=0;frames<=0;received<=0;last_rx<=0;demo_message<=0;image_address<=0;
   app_wr_en<=0; app_wr_sof<=0; app_wr_eof<=0; app_wr_data<=0;
   app_wr_len<=DEMO_LMAX; app_wr_vl_id<=0;
  end else begin
   case(cfg_state)
    CFG_RX: if(cfg_index==2'd3) begin cfg_state<=CFG_PORT;cfg_index<=0;end else cfg_index<=cfg_index+1'b1;
    CFG_PORT: if(cfg_index==2'd3) begin cfg_state<=CFG_TX;cfg_index<=0;end else cfg_index<=cfg_index+1'b1;
    CFG_TX: if(cfg_index==3)begin cfg_state<=CFG_SEAL;cfg_index<=0;end else cfg_index<=cfg_index+1'b1;
    CFG_SEAL: cfg_state<=CFG_RUN;
    CFG_RUN: if(cfg_rx_ready) demo_enable<=1;
    default: begin end
   endcase
   if(demo_enable) begin
    if(rtc_counter==0)rtc_counter<=RTC_POLL_CYCLES>0?RTC_POLL_CYCLES-1:0;else rtc_counter<=rtc_counter-1'b1;
    if(demo_timer!=0) demo_timer<=demo_timer-1'b1;
    // SOF must be offered before the core can assert ready for a new message.
    // Hold all fields while stalled; advance only on an accepted byte.
    if(!app_wr_en && demo_timer==0) begin
     app_wr_en<=1; app_wr_sof<=1; app_wr_eof<=0; demo_byte<=0; app_wr_data<=8'h41;
     demo_message<={image_length[7:0],image_read_data,last_rx,4'd0,load_failed,loading,image_valid,rtc_locked,received,frames,32'h58444641};
    end else if(app_wr_en && app_wr_accept) begin
     if(demo_byte==7'd15) begin
      app_wr_en<=0; app_wr_sof<=0; app_wr_eof<=0; demo_byte<=0; demo_timer<=DEMO_INTERVAL_CYCLES>0?DEMO_INTERVAL_CYCLES-1:0;
      frames<=frames+1'b1;app_wr_vl_id<=app_wr_vl_id+1'b1;
      if(image_valid&&image_length!=0&&image_address<image_length-1'b1)image_address<=image_address+1'b1;else image_address<=0;
     end else begin
      demo_byte<=demo_byte+1'b1; app_wr_data<=demo_message[(demo_byte+1)*8+:8]; app_wr_sof<=0; app_wr_eof<=demo_byte==7'd14;
     end
    end
   end
   if(payload_valid)begin received<=received+1'b1;last_rx<=payload_data;end
  end
 end

 AFDX_competition_top #(.SERVICE_DOMAINS(1),.CLK_HZ(CLK_HZ),.SERVICE_TIMEOUT_CYCLES(SERVICE_TIMEOUT_CYCLES)) u_end_system (
  .cfg_port_write(cfg_port_write),.cfg_port_index({2'b0,cfg_index}),.cfg_port_entry(cfg_port_entry),
  .app_wr_subvl(2'd0),.app_read_subvl(2'd0),.app_wr_use_sap(1'b0),.app_wr_sap(16'd0),.app_wr_partition(3'd0),.app_read_partition(3'd0),
  .payload_port(payload_port),.payload_sap(),.app_access_error(app_access_error),
  .cfg_rx_write(cfg_rx_write),.cfg_rx_seal(cfg_rx_seal),.cfg_rx_index(cfg_index),.cfg_rx_entry(cfg_rx_entry),.cfg_rx_ready(cfg_rx_ready),.cfg_rx_error(cfg_rx_error),
  .clk(clk),.rst(reset),.tx_enable(net_enable),.network_a_enable(net_enable),.network_b_enable(net_enable),
  .cfg_we(cfg_we),.cfg_vl_id(cfg_index),.cfg_bag(DEMO_BAG),.cfg_destination(8'd2),
  .app_wr_en(app_wr_en),.app_wr_vl_id(app_wr_vl_id),.app_wr_data(app_wr_data),.app_wr_len(app_wr_len),.app_wr_sof(app_wr_sof),.app_wr_eof(app_wr_eof),
  .cfg_lmax(16'd1518),.app_wr_ready(app_wr_ready),.app_len_error(app_len_error),.app_wr_accept(app_wr_accept),.fault_enable(1'b0),
  .data_a_txd(a_txd),.data_b_txd(b_txd),.data_a_tx_en(a_tx_en),.data_b_tx_en(b_tx_en),.data_a_tx_er(a_tx_er),.data_b_tx_er(b_tx_er),.data_a_done(a_done),.data_b_done(b_done),
  .data_a_rxd(rx_data),.data_b_rxd(rx_data),.data_a_rx_dv(rx_valid),.data_b_rx_dv(rx_valid),.data_a_rx_er(1'b0),.data_b_rx_er(1'b0),
  .payload_data(payload_data),.payload_valid(payload_valid),.payload_sof(payload_sof),.payload_eof(payload_eof),.payload_network(payload_network),.payload_ready(1'b1),
  .app_read_request(1'b0),.app_read_port(2'd0),.app_read_ready(),.payload_length(payload_length),.payload_vl(payload_vl),.payload_fresh(),
  .management_busy(management_busy),.snmp_snapshots(snmp_snapshots),.snmp_busy_drops(snmp_busy_drops),.shared_rx_accepted(shared_rx_accepted),.shared_rx_duplicates(shared_rx_duplicates),.shared_rx_dropped(shared_rx_dropped),.shared_tx_overflows(shared_tx_overflows),.physical_a_frames(physical_a_frames),.physical_b_frames(physical_b_frames),
  .loader_ip(LOADER_IP),.time_server_ip(TIME_SERVER_IP),.hardware_length(hardware_length),.hardware_id(hardware_id),.app_file(2'd0),.rtc_poll(rtc_poll),.rtc_locked(rtc_locked),.utc_ntp(utc_ntp),.monotonic_ticks(monotonic_ticks),
  .image_valid(image_valid),.image_length(image_length),.image_crc(image_crc),.package_generation(package_generation),.package_file_count(package_file_count),.image_read_address(image_address),.image_read_data(image_read_data),.loading(loading),.load_complete(load_complete),.load_failed(load_failed),
  .service_app_domain(1'b0),.service_loaded(service_loaded),.service_clock_locked(service_clock_locked),.service_cfg_we(1'b0),.service_cfg_domain(1'b0),.service_cfg_loader_ip(32'd0),.service_cfg_clock_ip(32'd0),.service_cfg_enable(1'b0),.service_cfg_commit(1'b0),.service_cfg_ready(service_cfg_ready),.service_cfg_error(service_cfg_error),.service_cfg_pending(service_cfg_pending),.service_cfg_commit_pulse(service_cfg_commit_pulse),.service_enabled(service_enabled)
 );
endmodule
