// Semantics-preserving test copy; original source remains frozen.
`timescale 1ns/1ps
// A reference network combines loader, management and business loopback on
// actual A/B wires. No service or SNMP packet is injected behind the DUT MAC.
module model_security_baseline #(parameter integer MODE=0,MESSAGE_BYTES=1471,BULK_TEST=0)(output reg [31:0] errors,output reg finished);
initial begin errors=0;finished=0;end
reg clk=0;always #40 clk=~clk;reg rst=1;
reg cfg_rx_write=0,cfg_rx_seal=0;reg [1:0] cfg_rx_index=0;reg [167:0] cfg_rx_entry=0;
wire cfg_rx_ready,cfg_rx_error;
reg network_a_enable=1,network_b_enable=1,cfg_we=0;
reg [1:0] cfg_vl_id=0,app_wr_vl_id=0,app_file=0;
reg [31:0] cfg_bag=32'd12500;reg [7:0] cfg_destination=2,app_wr_data=0;
reg app_wr_en=0,app_wr_sof=0,app_wr_eof=0;reg [15:0] app_wr_len=0,image_read_address=0;
wire app_wr_ready,app_len_error,app_wr_accept;
wire [7:0] data_a_txd,data_b_txd,payload_data,image_read_data;
wire data_a_tx_en,data_b_tx_en,data_a_tx_er,data_b_tx_er,data_a_done,data_b_done;
wire [7:0] network_a_data,network_b_data;wire network_a_valid,network_b_valid,network_a_error,network_b_error;
wire payload_valid,payload_sof,payload_eof,payload_network;wire management_busy;
wire [31:0] snmp_snapshots,snmp_busy_drops,shared_rx_accepted,shared_rx_duplicates,shared_rx_dropped,shared_tx_overflows,physical_a_frames,physical_b_frames;
reg rtc_poll=0;wire rtc_locked,image_valid,loading,load_complete,load_failed;wire [63:0] utc_ntp,monotonic_ticks;
wire [15:0] image_length;wire [31:0] image_crc,package_generation;wire [2:0] package_file_count;
AFDX_competition_top #(.CLK_HZ(12500000),.MANAGEMENT_BAG_CYCLES(12500),.SERVICE_BAG_CYCLES(12500),.SERVICE_TIMEOUT_CYCLES(30000),.RX_SKEW_MAX_CYCLES(200000),
.SNMP_COMMUNITY_LENGTH(11),.SNMP_COMMUNITY({168'd0,88'h747365742d746867696c66})) dut(
.clk(clk),.rst(rst),.cfg_rx_write(cfg_rx_write),.cfg_rx_seal(cfg_rx_seal),.cfg_rx_index(cfg_rx_index),.cfg_rx_entry(cfg_rx_entry),.cfg_rx_ready(cfg_rx_ready),.cfg_rx_error(cfg_rx_error),
.tx_enable(1'b1),.network_a_enable(network_a_enable),.network_b_enable(network_b_enable),.cfg_we(cfg_we),.cfg_vl_id(cfg_vl_id),.cfg_bag(cfg_bag),.cfg_destination(cfg_destination),.cfg_lmax(16'd1518),
.app_wr_en(app_wr_en),.app_wr_vl_id(app_wr_vl_id),.app_wr_data(app_wr_data),.app_wr_len(app_wr_len),.app_wr_sof(app_wr_sof),.app_wr_eof(app_wr_eof),.app_wr_ready(app_wr_ready),.app_len_error(app_len_error),.app_wr_accept(app_wr_accept),.fault_enable(1'b0),
.data_a_txd(data_a_txd),.data_b_txd(data_b_txd),.data_a_tx_en(data_a_tx_en),.data_b_tx_en(data_b_tx_en),.data_a_tx_er(data_a_tx_er),.data_b_tx_er(data_b_tx_er),.data_a_done(data_a_done),.data_b_done(data_b_done),
.data_a_rxd(network_a_data),.data_b_rxd(network_b_data),.data_a_rx_dv(network_a_valid),.data_b_rx_dv(network_b_valid),.data_a_rx_er(network_a_error),.data_b_rx_er(network_b_error),
.payload_data(payload_data),.payload_valid(payload_valid),.payload_sof(payload_sof),.payload_eof(payload_eof),.payload_network(payload_network),.payload_ready(1'b1),
.app_read_request(1'b0),.app_read_port(2'd0),.app_read_ready(),.payload_length(),.payload_vl(),.payload_fresh(),.management_busy(management_busy),.snmp_snapshots(snmp_snapshots),.snmp_busy_drops(snmp_busy_drops),.shared_rx_accepted(shared_rx_accepted),.shared_rx_duplicates(shared_rx_duplicates),.shared_rx_dropped(shared_rx_dropped),.shared_tx_overflows(shared_tx_overflows),.physical_a_frames(physical_a_frames),.physical_b_frames(physical_b_frames),
.loader_ip(32'h0a000001),.time_server_ip(32'h0a000001),.hardware_length(6'd3),.hardware_id({232'd0,24'h4d4953}),.app_file(app_file),
.rtc_poll(rtc_poll),.rtc_locked(rtc_locked),.utc_ntp(utc_ntp),.monotonic_ticks(monotonic_ticks),.image_valid(image_valid),.image_length(image_length),.image_crc(image_crc),.package_generation(package_generation),.package_file_count(package_file_count),.image_read_address(image_read_address),.image_read_data(image_read_data),.loading(loading),.load_complete(load_complete),.load_failed(load_failed));
wire [7:0] target_data=data_a_tx_en?data_a_txd:data_b_txd;wire target_valid=data_a_tx_en||data_b_tx_en;
wire target_error=data_a_tx_en?data_a_tx_er:data_b_tx_er;
wire [7:0] peer_host_data,manager_host_data;wire peer_host_valid,peer_host_error,manager_host_valid,manager_host_error;wire [31:0] peer_filter_overflow,manager_filter_overflow;
model_reference_rx_filter peer_filter(.clk(clk),.rst(rst),.data(target_data),.valid(target_valid),.error(target_error),.host_data(peer_host_data),.host_valid(peer_host_valid),.host_error(peer_host_error),.overflows(peer_filter_overflow));
model_reference_rx_filter #(.HOST_IP(32'hc0a80173)) manager_filter(.clk(clk),.rst(rst),.data(target_data),.valid(target_valid),.error(target_error),.host_data(manager_host_data),.host_valid(manager_host_valid),.host_error(manager_host_error),.overflows(manager_filter_overflow));
wire [7:0] peer_data;wire peer_valid,peer_error,peer_admit;wire [31:0] peer_errors,peer_reports,peer_final;wire peer_lui,peer_lur,peer_ntp;
model_foundation_peer peer(.clk(clk),.rst(rst),.start(cfg_rx_ready&&MODE!=0),.tx_admit(peer_admit),.rxd(peer_host_data),.dv(peer_host_valid),.er(peer_host_error),
.txd(peer_data),.txen(peer_valid),.txer(peer_error),.errors(peer_errors),.reports(peer_reports),.final_reports(peer_final),.lui_seen(peer_lui),.lur_seen(peer_lur),.ntp_seen(peer_ntp));
reg manager_request=0;reg [10:0] manager_length=0;reg [4127:0] manager_bytes=0;wire manager_ready,manager_admit;
wire [7:0] manager_data;wire manager_valid,manager_error;
wire response_valid;wire [10:0] response_length;wire [4127:0] response_bytes;wire [15:0] response_sp,response_dp;
afdx_service_gmii #(.LOCAL_MAC(48'h030000000011),.SOURCE_MAC(48'h020000000002),.PEER_MAC(48'h030000000001),.LOCAL_IP(32'hc0a80173),.BAG_CYCLES(1),.EXTERNAL_ADMISSION(1)) manager(
.clk(clk),.rst(rst),.tx_admit(manager_admit),.gmii_rxd(manager_host_data),.gmii_rx_dv(manager_host_valid),.gmii_rx_er(manager_host_error),.gmii_txd(manager_data),.gmii_tx_en(manager_valid),.gmii_tx_er(manager_error),.tx_done(),
.rx_valid(response_valid),.rx_ip(),.rx_sport(response_sp),.rx_dport(response_dp),.rx_length(response_length),.rx_bytes(response_bytes),
.tx_valid(manager_request),.tx_ready(manager_ready),.tx_ip(32'hc0a80101),.tx_sport(16'd40009),.tx_dport(16'd161),.tx_length(manager_length),.tx_bytes(manager_bytes),.received(),.rejected());
reg [7:0] loop_a=0,loop_b=0;reg loop_a_en=0,loop_b_en=0;wire loop_admit;
wire [7:0] incoming_a,incoming_b;wire incoming_a_en,incoming_b_en;wire [31:0] reference_overflows;
wire [191:0] macs={48'h030000000005,48'h030000000004,48'h030000000003,48'h030000000002};
afdx_shared_tx_mux #(.REWRITE_SOURCE(1),.SOURCE_USER_ID(16'h0002)) network(
.clk(clk),.rst(rst),.network_a_enable(1'b1),.network_b_enable(1'b1),.business_bags(128'd0),.business_macs(macs),
.business_a(loop_a),.business_b(loop_b),.business_a_en(loop_a_en),.business_b_en(loop_b_en),.business_a_er(1'b0),.business_b_er(1'b0),
.management_data(manager_data),.service_data(peer_data),.management_en(manager_valid),.service_en(peer_valid),.management_er(manager_error),.service_er(peer_error),
.business_admit(loop_admit),.management_admit(manager_admit),.service_admit(peer_admit),.a_data(incoming_a),.b_data(incoming_b),.a_en(incoming_a_en),.b_en(incoming_b_en),.a_er(),.b_er(),.a_done(),.b_done(),.overflow_count(reference_overflows),.a_frames(),.b_frames());
// MODE2 damages A copies while B remains valid, then operates B-only.
integer incoming_index=0;reg incoming_prev=0;reg disable_a=0;
always @(posedge clk)begin
 if(rst)begin incoming_index<=0;incoming_prev<=0;end
 else begin incoming_prev<=incoming_a_en;if(incoming_a_en)incoming_index<=incoming_prev?incoming_index+1:1;else incoming_index<=0;end
end
assign network_a_data=incoming_a^((MODE==2&&incoming_index==55)?8'h01:8'h00);
assign network_b_data=incoming_b;assign network_a_valid=incoming_a_en&&!disable_a;assign network_b_valid=incoming_b_en;
assign network_a_error=0;assign network_b_error=0;
integer case_id=0,response_count=0,snapshot_samples=0,i,j,t,old_responses;
integer business_frames=0,business_bytes=0,business_index=0,business_seed=0;integer expected_bytes=0;integer app_ends[0:7],rx_ends[0:7];integer app_inputs=0,wire_business=0,rx_business=0;
reg [7:0] capture_a[0:1535],capture_b[0:1535],capture_in[0:1535];integer ca=0,cb=0,ci=0,log_index;
reg pa=0,pb=0,pi=0;integer all_wire,service_wire;integer loop_length=0;reg loop_pending=0;
reg [7:0] loop_mem_a[0:1535],loop_mem_b[0:1535];integer loop_index=0;reg loop_running=0;
initial begin all_wire=$fopen("baseline_shared_wire.txt","w");service_wire=$fopen("baseline_service_wire.txt","w");end
function [31:0] crcbyte;input [31:0] c;input [7:0] x;reg [31:0] v;integer k;begin v=c^x;for(k=0;k<8;k=k+1)v=v[0]?(v>>1)^32'hedb88320:v>>1;crcbyte=v;end endfunction
reg [31:0] crc_a=32'hffffffff,crc_b=32'hffffffff;
integer cycle=0,a_gap=1000,b_gap=1000,bag_start[0:5];integer traffic_class,started_a=0,started_b=0;
task fail;input [511:0] message;begin errors=errors+1;$display("FAIL SHARED mode=%0d case=%0d %0s",MODE,case_id,message);end endtask
always @(negedge clk)if(!rst)begin
 cycle=cycle+1;
 if(data_a_tx_en)begin
  if(!pa)begin if(a_gap<12)fail("A IFG");crc_a=32'hffffffff;started_a=cycle;end
  capture_a[ca]=data_a_txd;if(ca>=8)crc_a=crcbyte(crc_a,data_a_txd);ca=ca+1;a_gap=0;
  if(data_a_tx_er)fail("A output error");
 end else begin a_gap=a_gap+1;if(pa)begin
  if(crc_a!==32'hdebb20e3)fail("A wire FCS");
  $fwrite(all_wire,"A %0t ",$time);for(log_index=0;log_index<ca;log_index=log_index+1)$fwrite(all_wire,"%02x",capture_a[log_index]);$fwrite(all_wire,"\n");
  ca=0;
 end end
 if(data_b_tx_en)begin
  if(!pb)begin if(b_gap<12)fail("B IFG");crc_b=32'hffffffff;started_b=cycle;end
  capture_b[cb]=data_b_txd;if(cb>=8)crc_b=crcbyte(crc_b,data_b_txd);cb=cb+1;b_gap=0;
  if(data_b_tx_er)fail("B output error");
 end else begin b_gap=b_gap+1;if(pb)begin
  if(crc_b!==32'hdebb20e3)fail("B wire FCS");
  $fwrite(all_wire,"B %0t ",$time);for(log_index=0;log_index<cb;log_index=log_index+1)$fwrite(all_wire,"%02x",capture_b[log_index]);$fwrite(all_wire,"\n");
  if(capture_b[8]==3&&capture_b[13]>=2&&capture_b[13]<=5)begin
   traffic_class=capture_b[13]-2;
   if(({capture_b[28],capture_b[29]}&16'h1fff)==0)begin
   $display("TX_MEASURE ordinal=%0d vl=%0d app_end=%0d wire_start=%0d wire_end=%0d",wire_business,traffic_class,app_ends[wire_business],started_b,cycle);
   wire_business=wire_business+1;end
   if(loop_pending||loop_running)fail("reference business loopback overflow");
   loop_length=cb;for(log_index=0;log_index<cb;log_index=log_index+1)begin loop_mem_a[log_index]=capture_b[log_index];loop_mem_b[log_index]=capture_b[log_index];end
   loop_pending=1;
  end else if({capture_b[42],capture_b[43]}==161)traffic_class=4;else traffic_class=5;
  if(bag_start[traffic_class]!=0&&started_b-bag_start[traffic_class]<12500)fail("shared wire BAG");
  bag_start[traffic_class]=started_b;
  if({capture_b[38],capture_b[39],capture_b[40],capture_b[41]}==32'h0a000001)begin
   $fwrite(service_wire,"TARGET %0t ",$time);for(log_index=0;log_index<cb;log_index=log_index+1)$fwrite(service_wire,"%02x",capture_b[log_index]);$fwrite(service_wire,"\n");
  end
  cb=0;
 end end
 if(network_b_valid)begin capture_in[ci]=network_b_data;ci=ci+1;end
 else if(pi)begin
  if(capture_in[8]==3&&capture_in[13]>=2&&capture_in[13]<=5&&(capture_in[28]&8'h20)==0)begin rx_ends[rx_business]=cycle;rx_business=rx_business+1;end
  $fwrite(all_wire,"RX_B %0t ",$time);for(log_index=0;log_index<ci;log_index=log_index+1)$fwrite(all_wire,"%02x",capture_in[log_index]);$fwrite(all_wire,"\n");
  if({capture_in[38],capture_in[39],capture_in[40],capture_in[41]}==32'h0a000010)begin
   $fwrite(service_wire,"PEER %0t ",$time);for(log_index=0;log_index<ci;log_index=log_index+1)$fwrite(service_wire,"%02x",capture_in[log_index]);$fwrite(service_wire,"\n");
  end
  ci=0;
 end
 pa=data_a_tx_en;pb=data_b_tx_en;pi=network_b_valid;
 loop_a_en=0;loop_b_en=0;
 if(!loop_running&&loop_pending&&loop_admit)begin loop_running=1;loop_pending=0;loop_index=0;end
 if(loop_running)begin
  loop_a=loop_mem_a[loop_index];loop_b=loop_mem_b[loop_index];loop_a_en=1;loop_b_en=1;
  if(loop_index==loop_length-1)loop_running=0;else loop_index=loop_index+1;
 end
end
always @(posedge clk)if(!rst)begin
 if(app_wr_accept&&app_wr_eof)begin app_ends[app_inputs]=cycle;app_inputs=app_inputs+1;end
 if(app_len_error)fail("application length rejected");
 if(payload_valid)begin
  if(payload_sof)business_index=0;
  if(payload_data!==((31+business_frames+business_index*7)&255))fail("business payload mismatch");
  business_index=business_index+1;business_bytes=business_bytes+1;
  if(payload_eof)begin $display("RX_MEASURE ordinal=%0d wire_end=%0d app_end=%0d",business_frames,rx_ends[business_frames],cycle);if(business_index!=MESSAGE_BYTES)fail("business length");business_frames=business_frames+1;end
 end
 if(dut.snmp_snapshots>snapshot_samples)begin
  $write("MAC_SNAPSHOT case=%0d values=",case_id);for(log_index=0;log_index<25;log_index=log_index+1)$write("%08x",dut.mib_live[log_index*32+:32]);$display("");snapshot_samples=snapshot_samples+1;
 end
 if(response_valid)begin
  if(response_sp!=161||response_dp!=40009)fail("SNMP return endpoint");
  $write("MAC_RESPONSE case=%0d hex=",case_id);for(log_index=0;log_index<response_length;log_index=log_index+1)$write("%02x",response_bytes[log_index*8+:8]);$display("");response_count=response_count+1;
 end
end
task query;input [4095:0] bytes;input integer n,rejected;integer delay;begin
 old_responses=response_count;
 @(negedge clk);manager_request=1;manager_bytes={32'd0,bytes};manager_length=n;#1;
 delay=0;while(!manager_ready&&delay<10000)begin @(negedge clk);#1;delay=delay+1;end
 if(!manager_ready)fail("manager request admission timeout");
 @(negedge clk);manager_request=0;
 delay=0;while((response_count==old_responses||management_busy)&&delay<30000)begin @(negedge clk);#1;delay=delay+1;end
 repeat(1500)@(negedge clk);
 if(response_count!=old_responses+(rejected?0:1))fail("SNMP response or duplicate count");
 $display("MAC_CASE=%0d REJECT=%0d RESPONSES=%0d SNAPSHOTS=%0d",case_id,rejected,response_count,snmp_snapshots);
 case_id=case_id+1;
 if(MODE==2&&case_id==2)begin disable_a=1;network_a_enable=0;end
end endtask
task send_business;input integer vl;integer k,waited;begin
 for(k=0;k<MESSAGE_BYTES;k=k+1)begin
  @(negedge clk);app_wr_vl_id=vl;app_wr_data=(31+vl+k*7)&255;app_wr_len=MESSAGE_BYTES;app_wr_sof=k==0;app_wr_eof=k==MESSAGE_BYTES-1;app_wr_en=1;
  #1;waited=0;while(!app_wr_ready&&waited<10000)begin @(negedge clk);waited=waited+1;end
  if(!app_wr_ready)fail("business ingress timeout");
 end
 @(negedge clk);app_wr_en=0;app_wr_sof=0;app_wr_eof=0;
 waited=0;while(business_frames<=vl&&waited<200000)begin @(negedge clk);waited=waited+1;end
 if(business_frames!=vl+1)fail("business delivery timeout");
end endtask
reg [15:0] row_port;reg [31:0] row_ip;reg [47:0] row_mac;
initial begin
 $display("BULK_PROFILE=%0d",BULK_TEST);
 $display("BUSINESS_PROFILE bytes=%0d messages=%0d",MESSAGE_BYTES,MODE==0?0:MODE==3?8:4);
 for(i=0;i<6;i=i+1)bag_start[i]=0;
 repeat(5)@(negedge clk);rst=0;
 for(i=0;i<4;i=i+1)begin
  row_port=i==0?10001:(i==1?20001:20002+i);row_ip=32'h0a000002+i;row_mac=48'h030000000002+i;
  cfg_rx_index=i;cfg_rx_entry={16'd1518,row_port,16'd10000,row_ip,32'h0a000001,row_mac,8'h03};cfg_rx_write=1;
  cfg_we=1;cfg_vl_id=i;cfg_destination=i+2;
  @(negedge clk);cfg_rx_write=0;cfg_we=0;@(negedge clk);
 end
 cfg_rx_seal=1;@(negedge clk);cfg_rx_seal=0;
 if(!cfg_rx_ready||cfg_rx_error)fail("configuration seal");
 fork
  begin
   if(BULK_TEST)begin
    `include "snmp_bulk_queries.vh"
   end else begin
    `include "snmp_queries.vh"
   end
  end
  begin if(MODE!=0)begin
   for(j=0;j<(MODE==3?8:4);j=j+1)send_business(j);
  end end
  begin if(MODE!=0)begin
   @(negedge clk);rtc_poll=1;@(negedge clk);rtc_poll=0;
   t=0;while((!load_complete||!rtc_locked)&&t<1000000)begin @(negedge clk);t=t+1;end
   if(!image_valid||!load_complete||load_failed||package_file_count!==2||package_generation!==1||image_crc!==32'hce05f473||!rtc_locked||peer_errors!=0||!peer_lui||!peer_lur||!peer_ntp||peer_final!=1)begin
    $display("JOINT_DEBUG valid=%b complete=%b failed=%b files=%d gen=%d crc=%h locked=%b peer=%d final=%d rx=%d dup=%d drop=%d",image_valid,load_complete,load_failed,package_file_count,package_generation,image_crc,rtc_locked,peer_errors,peer_final,shared_rx_accepted,shared_rx_duplicates,shared_rx_dropped);
    fail("shared package RTC joint");
   end
   for(t=0;t<1724;t=t+1)begin app_file=t<700?0:1;image_read_address=t<700?t:t-700;#1;if(image_read_data!==(t<700?((3+t*7)&255):((225-(t-700)*3)&255)))fail("shared package application bytes");end
   app_file=0;image_read_address=0;
  end end
 join
 repeat(2000)@(negedge clk);
 if(response_count!=(BULK_TEST?14:8)||snmp_snapshots!=(BULK_TEST?14:8)||snmp_busy_drops!=0||shared_tx_overflows!=0||reference_overflows!=0||peer_filter_overflow!=0||manager_filter_overflow!=0)fail("final management/queue counts");
 if(MODE!=0&&(business_frames!=(MODE==3?8:4)||business_bytes!=(MODE==3?8:4)*MESSAGE_BYTES))fail("four VL shared result");
 if(MODE!=2&&shared_rx_duplicates<11)fail("redundant management dedup coverage");
 if(MODE==2&&shared_rx_dropped==0)fail("bad A copy rejection coverage");
 $display("SHARED_FINAL mode=%0d business=%0d bytes=%0d snmp=%0d snapshots=%0d load=%b rtc=%b a_frames=%0d b_frames=%0d drops=%0d overflows=%0d errors=%0d",MODE,business_frames,business_bytes,response_count,snmp_snapshots,load_complete,rtc_locked,physical_a_frames,physical_b_frames,shared_rx_dropped,shared_tx_overflows,errors);
 $fclose(all_wire);$fclose(service_wire);finished=1;
end
endmodule