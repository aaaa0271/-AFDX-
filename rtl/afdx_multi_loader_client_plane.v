`timescale 1ns/1ps
// Independent package banks, transfer state, clocks and RX/TX VLs for each
// domain. Domain count controls every lane, packed endpoint array and mask.
module afdx_multi_loader_client_plane #(
 parameter integer DOMAINS=2,CLK_HZ=12500000,TIMEOUT_CYCLES=12500000,BAG_CYCLES=12500,SKEW_CYCLES=2000000,
 parameter [DOMAINS*32-1:0] LOADER_IPS=default_ips(32'h0a000001),
 parameter [DOMAINS*32-1:0] CLOCK_IPS=default_ips(32'h0a000101),
 parameter [DOMAINS*48-1:0] LOADER_RX_MACS=default_macs(48'h030000000010),
 parameter [DOMAINS*48-1:0] CLOCK_RX_MACS=default_macs(48'h030000000011),
 parameter [DOMAINS*48-1:0] LOADER_TX_MACS=default_macs(48'h030000000020),
 parameter [DOMAINS*48-1:0] CLOCK_TX_MACS=default_macs(48'h030000000021),
 parameter integer DOMAIN_WIDTH=$clog2(DOMAINS+1),LEGACY_SINGLE=0,MAC_TIMESTAMPS=0
)(
 input wire clk,rst,tx_admit,input wire [7:0] a_data,b_data,input wire a_valid,b_valid,a_error,b_error,
 input wire [5:0] hardware_length,input wire [255:0] hardware_id,input wire rtc_poll,
 input wire [DOMAIN_WIDTH-1:0] app_domain,input wire [1:0] app_file,input wire [15:0] app_address,
 output wire [7:0] tx_data,output wire tx_en,tx_er,
 output wire [DOMAINS-1:0] domain_loading,domain_complete,domain_failed,clock_locked,
 output wire selected_valid,output wire [15:0] selected_length,output wire [31:0] selected_crc,selected_generation,
 output wire [2:0] selected_files,output wire [7:0] selected_data,
 output wire [63:0] selected_utc,selected_monotonic,
 output wire [31:0] overflows,
 // The scalar reset defaults preserve the original single-domain top interface.
 input wire [31:0] legacy_loader_ip,legacy_clock_ip,
 input wire cfg_we,input wire [DOMAIN_WIDTH-1:0] cfg_domain,
 input wire [31:0] cfg_loader_ip,cfg_clock_ip,input wire cfg_enable,cfg_commit,
 output wire cfg_ready,cfg_error,cfg_pending,commit_pulse,
 output wire [DOMAINS-1:0] enabled,
 input wire [7:0] physical_tx_data,input wire physical_tx_valid,physical_tx_error,
 input wire [63:0] ingress_a_delay,ingress_b_delay,
 output wire [255:0] selected_telemetry
);
 function [DOMAINS*32-1:0] default_ips;
  input [31:0] base;integer n;
  begin for(n=0;n<DOMAINS;n=n+1)default_ips[n*32+:32]=base+n;end
 endfunction
 function [DOMAINS*48-1:0] default_macs;
  input [47:0] base;integer n;
  begin for(n=0;n<DOMAINS;n=n+1)default_macs[n*48+:48]=base+2*n;end
 endfunction
 wire [DOMAINS*8-1:0] lane_tx,data;
 wire [DOMAINS-1:0] lane_en,lane_er,admit,pkg_valid;
 wire [DOMAINS-1:0] raw_loading,raw_complete,raw_failed,raw_locked;
 wire [DOMAINS*16-1:0] lengths;
 wire [DOMAINS*32-1:0] crcs,generations;
 wire [DOMAINS*3-1:0] counts;
 wire [DOMAINS*64-1:0] utcs,monos;
 wire [DOMAINS*256-1:0] telemetry;
 wire [DOMAINS*32-1:0] active_loader_ips,active_clock_ips;
 wire [DOMAINS-1:0] changed,rx_idle,mac_idle,lane_idle;
 wire merge_idle,commit_apply;
 wire safe_to_commit=(&lane_idle)&&merge_idle&&!a_valid&&!b_valid&&!rtc_poll;
 afdx_service_domain_config #(.DOMAINS(DOMAINS),.DOMAIN_WIDTH(DOMAIN_WIDTH)) configuration(
  .clk(clk),.rst(rst),.initial_loader_ips(LEGACY_SINGLE?legacy_loader_ip:LOADER_IPS),
  .initial_clock_ips(LEGACY_SINGLE?legacy_clock_ip:CLOCK_IPS),
  .cfg_we(cfg_we),.cfg_domain(cfg_domain),.cfg_loader_ip(cfg_loader_ip),.cfg_clock_ip(cfg_clock_ip),
  .cfg_enable(cfg_enable),.cfg_commit(cfg_commit),.cfg_ready(cfg_ready),.cfg_error(cfg_error),
  .cfg_pending(cfg_pending),.commit_pulse(commit_pulse),.safe_to_commit(safe_to_commit),
  .commit_apply(commit_apply),.changed(changed),.loader_ips(active_loader_ips),.clock_ips(active_clock_ips),.enabled(enabled));
 assign domain_loading=raw_loading&enabled;
 assign domain_complete=raw_complete&enabled;
 assign domain_failed=raw_failed&enabled;
 assign clock_locked=raw_locked&enabled;
 genvar g;
 generate for(g=0;g<DOMAINS;g=g+1)begin:LANES
  begin:ACTIVE
   wire lane_rst=rst||!enabled[g]||(commit_apply&&changed[g]);
   wire [7:0] replay;wire replay_valid;
   wire rx_valid,tx_valid,tx_ready,client_idle;wire [31:0] rip,tip;wire [15:0] rsp,rdp,tsp,tdp;
   wire [10:0] rl,tl;wire [4127:0] rb,tb;
   wire [63:0] replay_timestamp,received_timestamp,departure_timestamp,departure_origin;
   wire departure_valid;wire [31:0] departure_ip;
   // Delay metadata from an optional outer security queue is measured in
   // cycles. Constant division introduces at most one NTP fractional LSB.
   wire [95:0] a_elapsed={ingress_a_delay,32'd0}/CLK_HZ;
   wire [95:0] b_elapsed={ingress_b_delay,32'd0}/CLK_HZ;
   afdx_ntp_tx_timestamp departure(
    .clk(clk),.rst(lane_rst),.utc(utcs[g*64+:64]),.data(physical_tx_data),.valid(physical_tx_valid),.error(physical_tx_error),
    .event_valid(departure_valid),.timestamp(departure_timestamp),.origin(departure_origin),.peer_ip(departure_ip));
   afdx_shared_rx_demux #(.MANAGER_IP(0),.SKEW_MAX_CYCLES(SKEW_CYCLES),.SPLIT_CLOCK(!LEGACY_SINGLE),.DUAL_TIMESTAMPS(1),
    .SERVICE_MAC(LOADER_RX_MACS[g*48+:48]),.CLOCK_MAC(CLOCK_RX_MACS[g*48+:48])) rx(
    .clk(clk),.rst(lane_rst),.loader_ip(active_loader_ips[g*32+:32]),.time_server_ip(active_clock_ips[g*32+:32]),
    .a_data(a_data),.b_data(b_data),.a_valid(a_valid&&enabled[g]),.b_valid(b_valid&&enabled[g]),.a_error(a_error),.b_error(b_error),
    .management_data(),.management_valid(),.service_data(replay),.service_valid(replay_valid),.accepted(),.duplicates(),.dropped(),.idle(rx_idle[g]),
    .timestamp_now(utcs[g*64+:64]-(MAC_TIMESTAMPS?a_elapsed[63:0]:64'd0)),
    .timestamp_b_now(utcs[g*64+:64]-(MAC_TIMESTAMPS?b_elapsed[63:0]:64'd0)),.service_timestamp(replay_timestamp));
   afdx_service_gmii #(.SOURCE_MAC(48'h020000000010),.LOCAL_MAC(LOADER_RX_MACS[g*48+:48]),
    .PEER_MAC(LEGACY_SINGLE?48'h030000000012:LOADER_TX_MACS[g*48+:48]),.CLOCK_LOCAL_MAC(CLOCK_RX_MACS[g*48+:48]),.CLOCK_PEER_MAC(CLOCK_TX_MACS[g*48+:48]),
    .SPLIT_CLOCK(!LEGACY_SINGLE),.BAG_CYCLES(BAG_CYCLES),.EXTERNAL_ADMISSION(1)) mac(
    .clk(clk),.rst(lane_rst),.tx_admit(admit[g]),.gmii_rxd(replay),.gmii_rx_dv(replay_valid),.gmii_rx_er(1'b0),
    .gmii_txd(lane_tx[g*8+:8]),.gmii_tx_en(lane_en[g]),.gmii_tx_er(lane_er[g]),.tx_done(),
    .rx_valid(rx_valid),.rx_ip(rip),.rx_sport(rsp),.rx_dport(rdp),.rx_length(rl),.rx_bytes(rb),.gmii_rx_timestamp(replay_timestamp),.rx_timestamp(received_timestamp),
    .tx_valid(tx_valid),.tx_ready(tx_ready),.tx_ip(tip),.tx_sport(tsp),.tx_dport(tdp),.tx_length(tl),.tx_bytes(tb),.received(),.rejected(),.idle(mac_idle[g]));
   afdx_package_network_services #(.CLK_HZ(CLK_HZ),.TIMEOUT_CYCLES(TIMEOUT_CYCLES),.MAC_TIMESTAMPS(MAC_TIMESTAMPS)) client(
    .telemetry(telemetry[g*256+:256]),
    .clk(clk),.rst(lane_rst),.loader_ip(active_loader_ips[g*32+:32]),.time_server_ip(active_clock_ips[g*32+:32]),
    .hardware_length(hardware_length),.hardware_id(hardware_id),.rtc_poll(rtc_poll&&!cfg_pending&&enabled[g]),.rtc_locked(raw_locked[g]),
    .utc_ntp(utcs[g*64+:64]),.monotonic_ticks(monos[g*64+:64]),
    .package_valid(pkg_valid[g]),.generation(generations[g*32+:32]),.package_crc(crcs[g*32+:32]),.file_count(counts[g*3+:3]),
    .app_file(app_file),.app_address(app_address),.app_data(data[g*8+:8]),.app_length(lengths[g*16+:16]),.app_name(),
    .loading(raw_loading[g]),.load_complete(raw_complete[g]),.load_failed(raw_failed[g]),
    .tx_valid(tx_valid),.tx_ready(tx_ready),.tx_ip(tip),.tx_sport(tsp),.tx_dport(tdp),.tx_length(tl),.tx_bytes(tb),
    // Idle clients cannot start a new control session while a bank commit
    // waits. Busy clients keep port 69 retries / continuation requests, and
    // established TIDs and NTP replies are always allowed to drain.
    .rx_valid(rx_valid&&(!cfg_pending||!client_idle||rdp!=16'd69)),
    .rx_ip(rip),.rx_sport(rsp),.rx_dport(rdp),.rx_length(rl),.rx_bytes(rb),.service_idle(client_idle),
    .tx_timestamp_valid(departure_valid),.tx_timestamp(departure_timestamp),.tx_origin(departure_origin),.tx_peer_ip(departure_ip),.rx_timestamp(received_timestamp));
   assign lane_idle[g]=!enabled[g]||(rx_idle[g]&&mac_idle[g]&&client_idle&&!rx_valid&&!tx_valid);

  end
 end endgenerate
 // Complete-frame buffering and round-robin arbitration scale with DOMAINS.
 afdx_service_domain_tx_mux #(.DOMAINS(DOMAINS)) merge(
  .clk(clk),.rst(rst),.tx_admit(tx_admit),.lane_data(lane_tx),.lane_en(lane_en),.lane_er(lane_er),
  .lane_admit(admit),.tx_data(tx_data),.tx_en(tx_en),.tx_er(tx_er),.overflows(overflows),.idle(merge_idle));
 // The extra selector code makes out-of-range values testable for powers of 2.
 // Unknown/unconnected selectors never alias a real bank inside the plane.
 wire valid_selection=(app_domain<DOMAINS)===1'b1;
 wire selected_enabled=valid_selection?(enabled[app_domain]===1'b1):1'b0;
 assign selected_valid=selected_enabled&&pkg_valid[app_domain];
 assign selected_length=selected_enabled?lengths[app_domain*16+:16]:16'd0;
 assign selected_crc=selected_enabled?crcs[app_domain*32+:32]:32'd0;
 assign selected_generation=selected_enabled?generations[app_domain*32+:32]:32'd0;
 assign selected_files=selected_enabled?counts[app_domain*3+:3]:3'd0;
 assign selected_data=selected_enabled?data[app_domain*8+:8]:8'd0;
 assign selected_utc=selected_enabled?utcs[app_domain*64+:64]:64'd0;
 assign selected_monotonic=selected_enabled?monos[app_domain*64+:64]:64'd0;
 assign selected_telemetry=selected_enabled?telemetry[app_domain*256+:256]:256'd0;
endmodule

// One bounded frame slot per lane. Admission is sampled by the producer at
// frame start; the downstream grant is sampled once per whole buffered frame.
module afdx_service_domain_tx_mux #(
 parameter integer DOMAINS=1,MAX_FRAME_BYTES=1536,
 parameter integer DOMAIN_WIDTH=$clog2(DOMAINS+1),COUNT_WIDTH=$clog2(MAX_FRAME_BYTES+1)
)(
 input wire clk,rst,tx_admit,
 input wire [DOMAINS*8-1:0] lane_data,input wire [DOMAINS-1:0] lane_en,lane_er,
 output wire [DOMAINS-1:0] lane_admit,
 output reg [7:0] tx_data,output reg tx_en,tx_er,output reg [31:0] overflows,
 output wire idle
);
 reg [7:0] memory[0:DOMAINS*MAX_FRAME_BYTES-1];
 reg [COUNT_WIDTH-1:0] count[0:DOMAINS-1],length[0:DOMAINS-1];
 reg [DOMAINS-1:0] pending,previous,bad,dropping;
 reg sending;
 reg [DOMAIN_WIDTH-1:0] owner,last;
 reg [COUNT_WIDTH-1:0] index;
 reg [3:0] ifg;
 integer scan,probe,capture,overflow_increment;
 reg found;
 reg [DOMAIN_WIDTH-1:0] choice;
 genvar d;
 generate for(d=0;d<DOMAINS;d=d+1)begin:ADMISSION
  assign lane_admit[d]=!rst&&count[d]==0&&!pending[d]&&!previous[d]&&!dropping[d]&&!(sending&&owner==d);
 end endgenerate
 assign idle=!rst&&!sending&&!tx_en&&pending==0&&previous==0&&lane_en==0&&(&lane_admit);
 always @*begin
  found=0;choice=0;probe=0;
  // Use an integer for modulo arithmetic, not a truncated lane index.
  for(scan=1;scan<=DOMAINS;scan=scan+1)begin
   probe=(last+scan)%DOMAINS;
   if(!found&&pending[probe])begin found=1;choice=probe;end
  end
 end
 always @(posedge clk)begin
  if(rst)begin
   pending<=0;previous<=0;bad<=0;dropping<=0;sending<=0;owner<=0;last<=DOMAINS-1;
   index<=0;ifg<=0;tx_data<=0;tx_en<=0;tx_er<=0;overflows<=0;
   for(capture=0;capture<DOMAINS;capture=capture+1)begin count[capture]<=0;length[capture]<=0;end
  end else begin
   tx_en<=0;tx_er<=0;previous<=lane_en;overflow_increment=0;
   for(capture=0;capture<DOMAINS;capture=capture+1)begin
    if(lane_en[capture])begin
     if(!dropping[capture]&&count[capture]<MAX_FRAME_BYTES&&!pending[capture]&&!(sending&&owner==capture))begin
      memory[capture*MAX_FRAME_BYTES+count[capture]]<=lane_data[capture*8+:8];
      count[capture]<=count[capture]+1'b1;
      if(!previous[capture])bad[capture]<=lane_er[capture];
      else if(lane_er[capture])bad[capture]<=1;
     end else begin
      if(!dropping[capture])overflow_increment=overflow_increment+1;
      dropping[capture]<=1;
     end
    end else if(previous[capture])begin
     if(dropping[capture])begin
      dropping[capture]<=0;
      if(!pending[capture]&&!(sending&&owner==capture))count[capture]<=0;
     end else if(count[capture]!=0)begin pending[capture]<=1;length[capture]<=count[capture];end
    end
   end
   if(overflow_increment!=0)overflows<=overflows+overflow_increment;
   if(ifg!=0)ifg<=ifg-1'b1;
   if(!sending&&ifg==0&&found&&tx_admit)begin sending<=1;owner<=choice;last<=choice;index<=0;end
   if(sending)begin
    tx_data<=memory[owner*MAX_FRAME_BYTES+index];tx_en<=1;tx_er<=bad[owner];
    if(index==length[owner]-1'b1)begin sending<=0;pending[owner]<=0;count[owner]<=0;ifg<=12;end
    else index<=index+1'b1;
   end
  end
 end
endmodule
