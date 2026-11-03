`timescale 1ns/1ps
// Real 615A upload transaction backed by an ARINC665 package loader, not an
// opaque LUH treated as executable data. Prior package survives any failed load.
module afdx_package_network_services #(
 parameter integer CLK_HZ=100000000,TIMEOUT_CYCLES=100000000,MAC_TIMESTAMPS=0
)(
 input wire clk,rst,input wire [31:0] loader_ip,time_server_ip,
 input wire [5:0] hardware_length,input wire [255:0] hardware_id,
 input wire rtc_poll,output wire rtc_locked,output wire [63:0] utc_ntp,monotonic_ticks,
 output wire package_valid,output wire [31:0] generation,package_crc,output wire [2:0] file_count,
 input wire [1:0] app_file,input wire [15:0] app_address,
 output wire [7:0] app_data,output wire [15:0] app_length,output wire [255:0] app_name,
 output wire loading,load_complete,load_failed,
 output wire service_idle,
 output wire tx_valid,input wire tx_ready,output wire [31:0] tx_ip,output wire [15:0] tx_sport,tx_dport,
 output wire [10:0] tx_length,output wire [4127:0] tx_bytes,
 input wire rx_valid,input wire [31:0] rx_ip,input wire [15:0] rx_sport,rx_dport,
 input wire [10:0] rx_length,input wire [4127:0] rx_bytes,
 input wire tx_timestamp_valid,input wire [63:0] tx_timestamp,tx_origin,
 input wire [31:0] tx_peer_ip,input wire [63:0] rx_timestamp,
 output wire [255:0] telemetry
);
wire init,iv,ir,lv,la,lr,sv;wire [79:0] ib;wire [1023:0] lb,sb;wire [15:0] ll;wire [7:0] sl;
wire fetch,validate,ctrl_loading,ctrl_complete,ctrl_failed,control_idle;wire [5:0] filename_length;wire [255:0] filename;
wire pkg_busy,pkg_idle,pkg_done,pkg_error,pkg_prepared;wire [7:0] pkg_error_code;reg pending_fetch;
wire commit_package;wire [4:0] valid_bus,ready_bus;
wire [31:0] peer0,peer1,peer2;wire [15:0] sp0,sp1,sp2,dp0,dp1,dp2;wire [10:0] len0,len1,len2;wire [4127:0] b0,b1,b2;
wire download_active,download_idle,download_complete,download_failed;
wire [1:0] download_file;wire [15:0] download_address,download_length;
wire [7:0] download_data;wire [255:0] download_name;
wire [31:0] peer4;wire [15:0] sp4,dp4;wire [10:0] len4;wire [4127:0] b4;
// Control requests are routed once, so the upload and download servers never
// both answer the same port-69 packet.
wire download_request=rx_dport==69&&rx_length>=13&&
 (rx_bytes[2*8+:80]==80'h4f4e4c2e544547524154||rx_bytes[2*8+:80]==80'h444e4c2e544547524154||
  rx_bytes[2*8+:80]==80'h414e4c2e544547524154||rx_bytes[2*8+:80]==80'h524e4c2e544547524154);
wire ntp_busy;wire [383:0] ntp_packet;reg [31:0] time_peer;
wire [63:0] measured_delay,measured_offset;wire [31:0] measured_syncs,measured_bytes,measured_retries,expected_bytes;
assign telemetry={expected_bytes,measured_retries,measured_bytes,measured_syncs,measured_offset,measured_delay};
reg [2:0] owner,last;integer j;reg [2:0] probe,choice;
reg report_inflight,final_report,final_ack,report_error;
wire report_busy,report_done,report_failed,report_idle;
wire ctrl_abort,pkg_abort,report_abort,pkg_wait;
wire [15:0] ctrl_abort_status,pkg_abort_status,report_abort_status;
wire abort_event=ctrl_abort||pkg_abort||report_abort;
wire [15:0] abort_reason=ctrl_abort?ctrl_abort_status:pkg_abort?pkg_abort_status:report_abort_status;wire [15:0] report_addr;
wire start_report=sv&&!report_inflight&&!report_busy&&!valid_bus[2]&&!report_error;
wire start_package=pending_fetch&&!pkg_busy&&!valid_bus[1];
assign commit_package=report_done&&!report_failed&&final_report;
assign loading=ctrl_loading||pkg_busy||report_inflight||download_active;
assign load_complete=ctrl_complete&&final_ack&&!pkg_busy&&!report_error;
assign load_failed=ctrl_failed||report_error;
// This is a state contract, not a quiet-time heuristic. Final-ACK dally,
// deferred package work, pending reports, and an occupied TX owner all keep
// the service non-idle.
assign service_idle=control_idle&&pkg_idle&&report_idle&&!ntp_busy&&
                    download_idle&&!pending_fetch&&!report_inflight&&(owner==0)&&
                    !valid_bus[0]&&!valid_bus[1]&&!valid_bus[2]&&!valid_bus[3]&&!valid_bus[4]&&!sv&&!ctrl_loading;
assign tx_valid=owner!=0?valid_bus[owner-1]:1'b0;
assign tx_ip=owner==1?peer0:owner==2?peer1:owner==3?peer2:owner==5?peer4:time_peer;
assign tx_sport=owner==1?sp0:owner==2?sp1:owner==3?sp2:owner==5?sp4:16'd40001;
assign tx_dport=owner==1?dp0:owner==2?dp1:owner==3?dp2:owner==5?dp4:16'd123;
assign tx_length=owner==1?len0:owner==2?len1:owner==3?len2:owner==5?len4:11'd48;
assign tx_bytes=owner==1?b0:owner==2?b1:owner==3?b2:owner==5?b4:{3744'd0,ntp_packet};
assign ready_bus[0]=owner==1&&tx_ready;assign ready_bus[1]=owner==2&&tx_ready;
assign ready_bus[2]=owner==3&&tx_ready;assign ready_bus[3]=owner==4&&tx_ready;assign ready_bus[4]=owner==5&&tx_ready;
always @*begin
 choice=0;probe=0;
 for(j=1;j<=5;j=j+1)begin
  probe=(last+j)%5;
  if(choice==0&&valid_bus[probe])choice=probe+1'b1;
 end
end
always @(posedge clk)begin
 if(rst)begin owner<=0;last<=3;time_peer<=0;pending_fetch<=0;report_inflight<=0;final_report<=0;final_ack<=0;report_error<=0;end
 else begin
  if(rtc_poll&&!ntp_busy)time_peer<=time_server_ip;
  if(init)begin final_ack<=0;report_error<=0;end
  if(fetch)pending_fetch<=1;if(start_package||abort_event)pending_fetch<=0;
  if(owner==0)owner<=choice;
  else if(tx_valid&&tx_ready)begin last<=owner-1'b1;owner<=0;end
  if(start_report)begin report_inflight<=1;final_report<={sb[55:48],sb[63:56]}==3;end
  if(report_done)begin report_inflight<=0;if(report_failed)report_error<=1;else if(final_report)final_ack<=1;end
 end
end
afdx_615a_control_tftp #(.TIMEOUT_CYCLES(TIMEOUT_CYCLES)) control(.clk(clk),.rst(rst),.loader_ip(loader_ip),
.rx_valid(rx_valid&&!download_request),.rx_ip(rx_ip),.rx_sport(rx_sport),.rx_dport(rx_dport),.rx_length(rx_length),.rx_bytes(rx_bytes),
.tx_valid(valid_bus[0]),.tx_ready(ready_bus[0]),.tx_ip(peer0),.tx_sport(sp0),.tx_dport(dp0),.tx_length(len0),.tx_bytes(b0),
.initialize(init),.lui_valid(iv),.lui_ready(ir),.lui_bytes(ib),.lur_valid(lv),.lur_length(ll),.lur_bytes(lb),.lur_accept(la),.lur_reject(lr),.loading(loading),.idle(control_idle),.remote_abort(ctrl_abort),.abort_status(ctrl_abort_status));
// Publication currently commits one LUH transaction at a time.
// Reject larger LUR lists until aggregate multi-header commit is implemented.
afdx_615a_upload_control #(.MAX_HEADERS(1)) upload(.clk(clk),.rst(rst),.initialize(init),.init_valid(iv),.init_ready(ir),.init_bytes(ib),
.lur_valid(lv),.lur_length(ll),.lur_bytes(lb),.lur_accept(la),.lur_reject(lr),.fetch_start(fetch),.filename_length(filename_length),.filename(filename),
.transfer_done(pkg_done),.transfer_error(pkg_done&&pkg_error),.transferred_length(16'd0),.transferred_crc(32'd0),
.validate_request(validate),.validate_length(),.validate_crc(),.validation_done(validate),.validation_ok(pkg_prepared&&!pkg_error),
.status_valid(sv),.status_ready(report_done),.status_length(sl),.status_bytes(sb),.active(ctrl_loading),.complete(ctrl_complete),.failed(ctrl_failed),.status_code(),.abort_request(abort_event),.abort_reason(abort_reason),.idle(),.selected_header(),.header_count());
afdx_665_package_loader #(.TIMEOUT_CYCLES(TIMEOUT_CYCLES),.DEFER_COMMIT(1),.CLK_HZ(CLK_HZ)) package_loader(.clk(clk),.rst(rst),.start(start_package),.abort((report_error||abort_event||ctrl_failed)&&pkg_busy),
 .measured_bytes(measured_bytes),.measured_retries(measured_retries),.expected_bytes(expected_bytes),
.commit_authorize(commit_package),.prepared(pkg_prepared),.server_ip(loader_ip),.header_name_length(filename_length),.header_name(filename),.hardware_length(hardware_length),.hardware_id(hardware_id),
.tx_valid(valid_bus[1]),.tx_ready(ready_bus[1]),.tx_length(len1),.tx_bytes(b1),.tx_ip(peer1),.tx_sport(sp1),.tx_dport(dp1),
.rx_valid(rx_valid),.rx_ip(rx_ip),.rx_sport(rx_sport),.rx_dport(rx_dport),.rx_length(rx_length),.rx_bytes(rx_bytes),.busy(pkg_busy),.idle(pkg_idle),.done(pkg_done),.error(pkg_error),.error_code(pkg_error_code),
.package_valid(package_valid),.generation(generation),.package_crc(package_crc),.loaded_file_count(file_count),.app_file(app_file),.app_address(app_address),.app_data(app_data),.app_length(app_length),.app_name(app_name),.active_file(),.waiting(pkg_wait),.remote_abort(pkg_abort),.abort_status(pkg_abort_status),.loaded_support_mask(),.download_file(download_file),.download_address(download_address),.download_data(download_data),.download_length(download_length),.download_name(download_name));
afdx_tftp_client #(.MAX_FILE_BYTES(128),.TIMEOUT_CYCLES(TIMEOUT_CYCLES),.CLK_HZ(CLK_HZ)) reports(.clk(clk),.rst(rst),.start(start_report),.read_not_write(1'b0),.server_ip(loader_ip),.local_tid(16'd40002),
.filename_length(6'd10),.filename({176'd0,80'h53554c2e544547524154}),.put_length({8'd0,sl}),.put_address(report_addr),.put_data(sb[report_addr*8+:8]),
.tx_valid(valid_bus[2]),.tx_ready(ready_bus[2]),.tx_length(len2),.tx_bytes(b2),.tx_destination_ip(peer2),.tx_source_port(sp2),.tx_destination_port(dp2),
.rx_valid(rx_valid&&rx_dport==40002),.rx_source_ip(rx_ip),.rx_source_port(rx_sport),.rx_destination_port(rx_dport),.rx_length(rx_length),.rx_bytes(rx_bytes),
.remote_abort(report_abort),.abort_status(report_abort_status),.error_code(),.wait_active(),
.busy(report_busy),.done(report_done),.error(report_failed),.idle(report_idle),.file_valid(),.file_length(),.file_crc(),.read_address(16'd0),.read_data(),.retries(),.duplicates(),.rejected());
// TEMP-ELAB-STUB: download omitted for memory-bounded elaboration only.
assign valid_bus[4]=1'b0;
assign peer4=32'd0;assign sp4=16'd0;assign dp4=16'd0;assign len4=11'd0;assign b4=4128'd0;
assign download_active=1'b0;assign download_idle=1'b1;assign download_complete=1'b0;assign download_failed=1'b0;
assign download_file=2'd0;assign download_address=16'd0;assign download_length=16'd0;
assign download_data=8'd0;assign download_name=256'd0;

afdx_rtc_ntp #(.CLK_HZ(CLK_HZ),.RESPONSE_TIMEOUT(TIMEOUT_CYCLES),.MAC_TIMESTAMPS(MAC_TIMESTAMPS)) ntp(.clk(clk),.rst(rst),.poll(rtc_poll),.server_ip(time_server_ip),.tx_valid(valid_bus[3]),.tx_ready(ready_bus[3]),.tx_bytes(ntp_packet),
.tx_timestamp_valid(tx_timestamp_valid),.tx_timestamp(tx_timestamp),.tx_origin(tx_origin),.tx_peer_ip(tx_peer_ip),.rx_timestamp_valid(rx_valid),.rx_timestamp(rx_timestamp),
.rx_valid(rx_valid&&rx_dport==40001),.rx_source_ip(rx_ip),.rx_source_port(rx_sport),.rx_length(rx_length>255?8'hff:rx_length[7:0]),.rx_bytes(rx_bytes[383:0]),
.utc_ntp(utc_ntp),.monotonic_ticks(monotonic_ticks),.synchronized(rtc_locked),.sync_event(),.reject_event(),.timeout_event(),.last_offset(measured_offset),.last_delay(measured_delay),.sync_count(measured_syncs),.reject_count(),.timeout_count(),.busy(ntp_busy));
endmodule

