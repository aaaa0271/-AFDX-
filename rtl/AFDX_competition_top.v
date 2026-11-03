`timescale 1ns/1ps
// Competition end system: all business, extended SNMP, loader and RTC
// protocol traffic shares the same redundant A/B MAC byte interfaces.
module AFDX_competition_top #(
 parameter integer SERVICE_DOMAINS=1,
 parameter [SERVICE_DOMAINS*32-1:0] SERVICE_LOADER_IPS=default_service_ips(32'h0a000001),
 parameter [SERVICE_DOMAINS*32-1:0] SERVICE_CLOCK_IPS=default_service_ips(32'h0a000101),
 parameter integer EXTENDED_PORTS=1,SUBVL_MAX_MESSAGE=2048,
 parameter integer CLK_HZ=12500000,MANAGEMENT_BAG_CYCLES=50000,
 // SkewMax must stay well below 128 x minimum BAG: the smallest admissible
 // BAG is CLK_HZ/1000 = 12,500 cycles (1 ms), so 128 x BAG_min = 1,600,000
 // cycles. The 1,500,000-cycle default (120 ms) bounds late redundant copies
 // without letting an extreme-skew copy masquerade as a new frame and invert
 // the fresh/stale classification for a whole BAG interval.
 parameter integer RX_SKEW_MAX_CYCLES=1500000,SERVICE_BAG_CYCLES=12500,
 parameter integer SERVICE_TIMEOUT_CYCLES=12500000,
 parameter integer EXPLICIT_PORT_READ=0,FRESHNESS_CYCLES=12500000,
 parameter [3:0] SAMPLING_MASK=0,
 parameter [31:0] MANAGER_IP=32'hc0a80173,
 parameter [5:0] SNMP_COMMUNITY_LENGTH=6,
 parameter [255:0] SNMP_COMMUNITY={208'd0,48'h63696c627570},
 parameter integer SNMP_ENGINE_LENGTH=9,SNMP_USER_LENGTH=4,
 parameter [255:0] SNMP_ENGINE_ID=256'h5844464105d97e0080,SNMP_USER_NAME=256'h78646661,
 parameter [30:0] SNMP_ENGINE_BOOTS=1,
 parameter integer SERVICE_DOMAIN_WIDTH=$clog2(SERVICE_DOMAINS+1),RX_TIMESTAMP_DELAYS=0
)(
    input wire cfg_port_write,input wire [3:0] cfg_port_index,input wire [63:0] cfg_port_entry,
    input wire [1:0] app_wr_subvl,app_read_subvl,input wire app_wr_use_sap,input wire [15:0] app_wr_sap,
    input wire [2:0] app_wr_partition,app_read_partition,
    output wire [3:0] payload_port,output wire [15:0] payload_sap,output wire app_access_error,
    input wire cfg_rx_write,cfg_rx_seal,input wire [1:0] cfg_rx_index,input wire [167:0] cfg_rx_entry,
    output wire cfg_rx_ready,cfg_rx_error,
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
 input wire app_read_request,input wire [1:0] app_read_port,output wire app_read_ready,
 output wire [15:0] payload_length,output wire [1:0] payload_vl,output wire payload_fresh,
 output wire management_busy,
 output wire [31:0] snmp_snapshots,snmp_busy_drops,
 output wire [31:0] shared_rx_accepted,shared_rx_duplicates,shared_rx_dropped,
 output wire [31:0] shared_tx_overflows,physical_a_frames,physical_b_frames,
 input wire [31:0] loader_ip,time_server_ip,input wire [5:0] hardware_length,input wire [255:0] hardware_id,
 input wire [1:0] app_file,
 input wire rtc_poll,output wire rtc_locked,output wire [63:0] utc_ntp,monotonic_ticks,
 output wire image_valid,output wire [15:0] image_length,output wire [31:0] image_crc,
 output wire [31:0] package_generation,output wire [2:0] package_file_count,
 input wire [15:0] image_read_address,output wire [7:0] image_read_data,
 output wire loading,load_complete,load_failed,
 input wire [SERVICE_DOMAIN_WIDTH-1:0] service_app_domain,
 output wire [SERVICE_DOMAINS-1:0] service_loaded,service_clock_locked,
 input wire service_cfg_we,input wire [SERVICE_DOMAIN_WIDTH-1:0] service_cfg_domain,
 input wire [31:0] service_cfg_loader_ip,service_cfg_clock_ip,
 input wire service_cfg_enable,service_cfg_commit,
 output wire service_cfg_ready,service_cfg_error,service_cfg_pending,service_cfg_commit_pulse,
 output wire [SERVICE_DOMAINS-1:0] service_enabled,
 input wire [63:0] data_a_rx_delay,data_b_rx_delay,
 output wire [255:0] service_telemetry
);
function [SERVICE_DOMAINS*32-1:0] default_service_ips;
 input [31:0] base;integer d;
 begin for(d=0;d<SERVICE_DOMAINS;d=d+1)default_service_ips[d*32+:32]=base+d;end
endfunction
wire [671:0] rx_cfg_table;wire [1023:0] port_table;wire port_config_error,port_sealed;
// A seal is a transaction across VL, TX policy, and communication-port tables.
// Reject every coincident write; never leave one table live after another seals.
wire port_write_requested=cfg_port_write===1'b1;
wire config_write_requested=cfg_rx_write||cfg_we||port_write_requested;
wire seal_conflict=cfg_rx_seal&&config_write_requested;
wire seal_accept=cfg_rx_seal&&!config_write_requested;
reg seal_error;
always @(posedge clk)begin if(rst)seal_error<=0;else seal_error<=seal_conflict;end
function [1:0] normalized_sub;input [1:0] value;begin case(value)0,1,2,3:normalized_sub=value;default:normalized_sub=0;endcase end endfunction
function [2:0] normalized_partition;input [2:0] value;begin case(value)0,1,2,3,4,5,6,7:normalized_partition=value;default:normalized_partition=0;endcase end endfunction
wire use_sap=app_wr_use_sap===1'b1;
reg [3:0] routed_port;reg route_found;integer sap_i;
always @*begin
 routed_port={normalized_sub(app_wr_subvl),app_wr_vl_id};route_found=!use_sap;
 if(use_sap)for(sap_i=0;sap_i<16;sap_i=sap_i+1)if(port_table[sap_i*64]&&port_table[sap_i*64+2]&&port_table[sap_i*64+8+:16]==app_wr_sap)begin routed_port=sap_i;route_found=1;end
end
wire write_allowed=!EXTENDED_PORTS||(route_found&&port_table[routed_port*64]&&port_table[routed_port*64+56+normalized_partition(app_wr_partition)]);
wire [3:0] read_port_id={normalized_sub(app_read_subvl),app_read_port};
wire read_allowed=!EXTENDED_PORTS||port_table[read_port_id*64+56+normalized_partition(app_read_partition)];
// Business reception is disabled before the atomic configuration seal.
// If a leg is already inside a frame at the seal, arm only after its next idle.
reg [1:0] business_rx_armed;
always @(posedge clk)begin
 if(rst)business_rx_armed<=0;
 else if(seal_accept)business_rx_armed<={!data_b_rx_dv,!data_a_rx_dv};
 else if(!cfg_rx_ready)business_rx_armed<=0;
 else begin if(!data_a_rx_dv)business_rx_armed[0]<=1;if(!data_b_rx_dv)business_rx_armed[1]<=1;end
end
wire core_read_ready;
assign app_read_ready=core_read_ready&&read_allowed;
assign app_access_error=app_wr_en&&!write_allowed;
afdx_port_config_bank #(.SAMPLING_MASK(SAMPLING_MASK)) u_port_configuration(
 .clk(clk),.rst(rst),.write(port_write_requested&&!cfg_rx_seal),.seal(seal_accept),.index(cfg_port_index),.entry(cfg_port_entry),
 .network_cfg(rx_cfg_table),.port_table(port_table),.sealed(port_sealed),.error(port_config_error));
wire rx_config_error;reg tx_config_error;
function valid_bag;input [31:0] cycles;integer k;begin
 valid_bag=0;for(k=0;k<8;k=k+1)if(cycles==((CLK_HZ/1000)<<k)&&cycles!=0)valid_bag=1;
end endfunction
wire tx_config_accept=cfg_we&&!cfg_rx_ready&&!cfg_rx_seal&&valid_bag(cfg_bag)&&cfg_lmax>=64&&cfg_lmax<=1518;
assign cfg_rx_error=rx_config_error||tx_config_error||port_config_error||seal_error;
always @(posedge clk)begin
 if(rst)tx_config_error<=0;else tx_config_error<=cfg_we&&!tx_config_accept;
end
wire [799:0] mib_live;
wire core_app_ready,core_app_accept;
assign app_wr_ready=cfg_rx_ready&&core_app_ready&&write_allowed;
assign app_wr_accept=core_app_accept;
wire [7:0] business_a,business_b,management_rxd,service_rxd,management_txd,service_txd;
wire business_a_en,business_b_en,business_a_er,business_b_er;
wire management_rx_dv,service_rx_dv,management_tx_en,service_tx_en,management_tx_er,service_tx_er;
wire management_done,service_tx_done;
wire business_admit,management_admit,service_admit;
reg [127:0] business_bags;
always @(posedge clk)begin
 if(rst)business_bags<=0;
 else if(tx_config_accept)business_bags[cfg_vl_id*32+:32]<=cfg_bag;
end

afdx_rx_config_bank u_rx_configuration(.clk(clk),.rst(rst),.write(cfg_rx_write&&!cfg_rx_seal),.seal(seal_accept),.index(cfg_rx_index),
.present(cfg_rx_entry[0]),.enabled(cfg_rx_entry[1]),.dst_mac(cfg_rx_entry[55:8]),.src_ip(cfg_rx_entry[87:56]),.dst_ip(cfg_rx_entry[119:88]),
.src_port(cfg_rx_entry[135:120]),.dst_port(cfg_rx_entry[151:136]),.lmax(cfg_rx_entry[167:152]),.config_table(rx_cfg_table),.sealed(cfg_rx_ready),.error(rx_config_error));
afdx_datagram_core #(.EXTENDED_PORTS(EXTENDED_PORTS),.SUBVL_MAX_MESSAGE(SUBVL_MAX_MESSAGE),.CLK_HZ(CLK_HZ),.SKEW_MAX_CYCLES(RX_SKEW_MAX_CYCLES),.SAMPLING_MASK(SAMPLING_MASK),.AUTO_DRAIN(!EXPLICIT_PORT_READ),.FRESHNESS_CYCLES(FRESHNESS_CYCLES)) u_core(
.clk(clk),.rst(rst),.network_cfg(rx_cfg_table),.port_cfg(port_table),.app_wr_subvl(routed_port[3:2]),.read_subvl(normalized_sub(app_read_subvl)),.payload_port(payload_port),.payload_sap(payload_sap),.tx_enable(tx_enable&&cfg_rx_ready&&business_admit),.network_a_enable(network_a_enable),.network_b_enable(network_b_enable),
.cfg_we(tx_config_accept),.cfg_vl_id(cfg_vl_id),.cfg_bag(cfg_bag),.cfg_lmax(cfg_lmax),
.app_wr_en(app_wr_en&&cfg_rx_ready&&write_allowed),.app_wr_vl_id(routed_port[1:0]),.app_wr_data(app_wr_data),.app_wr_len(app_wr_len),.app_wr_sof(app_wr_sof),.app_wr_eof(app_wr_eof),.app_wr_ready(core_app_ready),.app_wr_accept(core_app_accept),.app_len_error(app_len_error),.fault_enable(fault_enable),
.a_txd(business_a),.b_txd(business_b),.a_tx_en(business_a_en),.b_tx_en(business_b_en),.a_tx_er(business_a_er),.b_tx_er(business_b_er),
.a_rxd(data_a_rxd),.b_rxd(data_b_rxd),.a_rx_dv(data_a_rx_dv&&cfg_rx_ready&&business_rx_armed[0]),.b_rx_dv(data_b_rx_dv&&cfg_rx_ready&&business_rx_armed[1]),.a_rx_er(data_a_rx_er),.b_rx_er(data_b_rx_er),
.payload_data(payload_data),.payload_valid(payload_valid),.payload_sof(payload_sof),.payload_eof(payload_eof),.payload_network(payload_network),.payload_ready(payload_ready),.read_request(app_read_request&&read_allowed),.read_port(app_read_port),.read_ready(core_read_ready),.payload_fresh(payload_fresh),.payload_length(payload_length),.payload_vl(payload_vl),.mib_live(mib_live));
generate begin:MULTI_SERVICES
wire [SERVICE_DOMAINS-1:0] domain_loading,domain_failed;
wire [31:0] merge_overflows;
// Unconnected selector remains domain zero for legacy single-domain callers.
// Explicit invalid and X selectors are rejected by the plane.
wire [SERVICE_DOMAIN_WIDTH-1:0] selected_domain=
 (SERVICE_DOMAINS==1 && service_app_domain==={SERVICE_DOMAIN_WIDTH{1'bz}})?{SERVICE_DOMAIN_WIDTH{1'b0}}:service_app_domain;
afdx_multi_loader_client_plane #(.DOMAINS(SERVICE_DOMAINS),.DOMAIN_WIDTH(SERVICE_DOMAIN_WIDTH),.LEGACY_SINGLE(SERVICE_DOMAINS==1),.MAC_TIMESTAMPS(1),
 .CLK_HZ(CLK_HZ),.TIMEOUT_CYCLES(SERVICE_TIMEOUT_CYCLES),
 .BAG_CYCLES(SERVICE_BAG_CYCLES),.SKEW_CYCLES(RX_SKEW_MAX_CYCLES),.LOADER_IPS(SERVICE_LOADER_IPS),.CLOCK_IPS(SERVICE_CLOCK_IPS)) plane(
 .clk(clk),.rst(rst),.tx_admit(service_admit),.a_data(data_a_rxd),.b_data(data_b_rxd),.a_valid(data_a_rx_dv),.b_valid(data_b_rx_dv),.a_error(data_a_rx_er),.b_error(data_b_rx_er),
 .hardware_length(hardware_length),.hardware_id(hardware_id),.rtc_poll(rtc_poll),.app_domain(selected_domain),.app_file(app_file),.app_address(image_read_address),
 .tx_data(service_txd),.tx_en(service_tx_en),.tx_er(service_tx_er),.domain_loading(domain_loading),.domain_complete(service_loaded),.domain_failed(domain_failed),.clock_locked(service_clock_locked),
 .selected_valid(image_valid),.selected_length(image_length),.selected_crc(image_crc),.selected_generation(package_generation),.selected_files(package_file_count),.selected_data(image_read_data),
 .selected_utc(utc_ntp),.selected_monotonic(monotonic_ticks),.overflows(merge_overflows),
 .selected_telemetry(service_telemetry),
 .legacy_loader_ip(loader_ip),.legacy_clock_ip(time_server_ip),
 .physical_tx_data(data_a_tx_en?data_a_txd:data_b_txd),.physical_tx_valid(data_a_tx_en||data_b_tx_en),.physical_tx_error(data_a_tx_en?data_a_tx_er:data_b_tx_er),
 .ingress_a_delay(RX_TIMESTAMP_DELAYS?data_a_rx_delay:64'd0),.ingress_b_delay(RX_TIMESTAMP_DELAYS?data_b_rx_delay:64'd0),
 .cfg_we(service_cfg_we),.cfg_domain(service_cfg_domain),.cfg_loader_ip(service_cfg_loader_ip),.cfg_clock_ip(service_cfg_clock_ip),
 .cfg_enable(service_cfg_enable),.cfg_commit(service_cfg_commit),.cfg_ready(service_cfg_ready),.cfg_error(service_cfg_error),
 .cfg_pending(service_cfg_pending),.commit_pulse(service_cfg_commit_pulse),.enabled(service_enabled));
assign loading=|domain_loading;assign load_failed=|domain_failed;
// Disabled domains do not prevent completion; an empty active set is not ready.
assign load_complete=(|service_enabled)&&(&(service_loaded|~service_enabled));
assign rtc_locked=(|service_enabled)&&(&(service_clock_locked|~service_enabled));
assign service_tx_done=1'b0;
end endgenerate
afdx_snmp_mac #(.BAG_CYCLES(MANAGEMENT_BAG_CYCLES),.EXTERNAL_ADMISSION(1),.CLK_HZ(CLK_HZ),
 .ENGINE_LENGTH(SNMP_ENGINE_LENGTH),.ENGINE_ID(SNMP_ENGINE_ID),.ENGINE_BOOTS(SNMP_ENGINE_BOOTS),
 .USER_LENGTH(SNMP_USER_LENGTH),.USER_NAME(SNMP_USER_NAME)) u_management(
.clk(clk),.rst(rst),.tx_admit(management_admit),.community_length(SNMP_COMMUNITY_LENGTH),.community_bytes(SNMP_COMMUNITY),.mib_values(mib_live),
.rxd(management_rxd),.dv(management_rx_dv),.er(1'b0),.txd(management_txd),.txen(management_tx_en),.txer(management_tx_er),.tx_done(management_done),
.busy(management_busy),.busy_drops(snmp_busy_drops),.snapshots(snmp_snapshots));
afdx_shared_rx_demux #(.MANAGER_IP(MANAGER_IP),.SKEW_MAX_CYCLES(RX_SKEW_MAX_CYCLES)) u_shared_rx(
.clk(clk),.rst(rst),.loader_ip(loader_ip),.time_server_ip(time_server_ip),
.a_data(data_a_rxd),.b_data(data_b_rxd),.a_valid(data_a_rx_dv),.b_valid(data_b_rx_dv),.a_error(data_a_rx_er),.b_error(data_b_rx_er),
.management_data(management_rxd),.service_data(service_rxd),.management_valid(management_rx_dv),.service_valid(service_rx_dv),
.accepted(shared_rx_accepted),.duplicates(shared_rx_duplicates),.dropped(shared_rx_dropped));
afdx_shared_tx_mux #(.REWRITE_SOURCE(1),.SOURCE_USER_ID(16'h0010),.MANAGEMENT_BAG_CYCLES(MANAGEMENT_BAG_CYCLES),.SERVICE_BAG_CYCLES(SERVICE_BAG_CYCLES)) u_shared_tx(
.clk(clk),.rst(rst),.network_a_enable(network_a_enable),.network_b_enable(network_b_enable),
.business_bags(business_bags),.business_macs({rx_cfg_table[512+:48],rx_cfg_table[344+:48],rx_cfg_table[176+:48],rx_cfg_table[8+:48]}),
.business_a(business_a),.business_b(business_b),.business_a_en(business_a_en),.business_b_en(business_b_en),.business_a_er(business_a_er),.business_b_er(business_b_er),
.management_data(management_txd),.service_data(service_txd),.management_en(management_tx_en),.service_en(service_tx_en),.management_er(management_tx_er),.service_er(service_tx_er),
.business_admit(business_admit),.management_admit(management_admit),.service_admit(service_admit),
.a_data(data_a_txd),.b_data(data_b_txd),.a_en(data_a_tx_en),.b_en(data_b_tx_en),.a_er(data_a_tx_er),.b_er(data_b_tx_er),.a_done(data_a_done),.b_done(data_b_done),
.overflow_count(shared_tx_overflows),.a_frames(physical_a_frames),.b_frames(physical_b_frames));
endmodule
