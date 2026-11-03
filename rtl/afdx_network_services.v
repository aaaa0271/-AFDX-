`timescale 1ns/1ps
module afdx_network_services #(
 parameter integer CLK_HZ=100000000,TIMEOUT_CYCLES=100000000
)(
 input wire clk,rst,input wire [31:0] loader_ip,time_server_ip,
 input wire [15:0] expected_image_length,input wire [31:0] expected_image_crc,
 input wire rtc_poll,output wire rtc_locked,output wire [63:0] utc_ntp,monotonic_ticks,
 output wire image_valid,output wire [15:0] image_length,output wire [31:0] image_crc,
 input wire [15:0] image_read_address,output wire [7:0] image_read_data,
 output wire loading,load_complete,load_failed,
 output wire tx_valid,input wire tx_ready,output wire [31:0] tx_ip,output wire [15:0] tx_sport,tx_dport,
 output wire [10:0] tx_length,output wire [4127:0] tx_bytes,
 input wire rx_valid,input wire [31:0] rx_ip,input wire [15:0] rx_sport,rx_dport,
 input wire [10:0] rx_length,input wire [4127:0] rx_bytes
);
wire init,iv,ir,lv,la,lr,sv,sready;wire [79:0] ib;wire [1023:0] lb,sb;wire [15:0] ll;wire [7:0] sl;
wire core_image_valid,core_complete,core_failed;wire [7:0] raw_image_data;
wire v0,v1,v2,r0,r1,r2;wire [31:0] ip0,ip1,ip2;wire [15:0] sp0,sp1,sp2,dp0,dp1,dp2;wire [10:0] len0,len1,len2;wire [4127:0] bytes0,bytes1,bytes2;
reg [1:0] owner,last_owner;reg report_inflight,final_report,final_ack,report_error;
wire report_busy,report_done,report_failed;wire [15:0] report_address;
wire report_start=sv&&!report_inflight&&!report_busy&&!v2&&!report_error;
assign sready=report_done;
assign image_valid=core_image_valid&&final_ack&&!report_error;
assign image_read_data=image_valid?raw_image_data:8'd0;
assign load_complete=core_complete&&final_ack&&!report_error;
assign load_failed=core_failed||report_error;
assign tx_valid=owner==1?v0:(owner==2?v1:(owner==3?v2:1'b0));
assign tx_ip=owner==1?ip0:(owner==2?ip1:ip2);
assign tx_sport=owner==1?sp0:(owner==2?sp1:sp2);
assign tx_dport=owner==1?dp0:(owner==2?dp1:dp2);
assign tx_length=owner==1?len0:(owner==2?len1:len2);
assign tx_bytes=owner==1?bytes0:(owner==2?bytes1:bytes2);
assign r0=owner==1&&tx_ready;assign r1=owner==2&&tx_ready;assign r2=owner==3&&tx_ready;
always @(posedge clk)begin
 if(rst)begin owner<=0;last_owner<=0;report_inflight<=0;final_report<=0;final_ack<=0;report_error<=0;end
 else begin
  if(init)begin final_ack<=0;report_error<=0;end
  if(owner==0)begin
   // Rotate report/data priority; control exchanges remain bounded packets.
   if(v0)owner<=1;
   else if(v1&&v2)owner<=last_owner==2?3:2;
   else if(v1)owner<=2;else if(v2)owner<=3;
  end else if(tx_valid&&tx_ready)begin last_owner<=owner;owner<=0;end
  if(report_start)begin report_inflight<=1;final_report<={sb[55:48],sb[63:56]}==3;end
  if(report_done)begin report_inflight<=0;if(report_failed)report_error<=1;else if(final_report)final_ack<=1;end
 end
end
afdx_615a_control_tftp #(.TIMEOUT_CYCLES(TIMEOUT_CYCLES)) u_control(.clk(clk),.rst(rst),.loader_ip(loader_ip),
.rx_valid(rx_valid),.rx_ip(rx_ip),.rx_sport(rx_sport),.rx_dport(rx_dport),.rx_length(rx_length),.rx_bytes(rx_bytes),
.tx_valid(v0),.tx_ready(r0),.tx_ip(ip0),.tx_sport(sp0),.tx_dport(dp0),.tx_length(len0),.tx_bytes(bytes0),
.initialize(init),.lui_valid(iv),.lui_ready(ir),.lui_bytes(ib),.lur_valid(lv),.lur_length(ll),.lur_bytes(lb),.lur_accept(la),.lur_reject(lr),.loading(loading));
afdx_load_rtc_services #(.CLK_HZ(CLK_HZ),.TFTP_TIMEOUT(TIMEOUT_CYCLES),.NTP_TIMEOUT(TIMEOUT_CYCLES)) u_core(
.clk(clk),.rst(rst),.loader_initialize(init),.lui_valid(iv),.lui_ready(ir),.lui_bytes(ib),.lur_valid(lv),.lur_length(ll),.lur_bytes(lb),.lur_accept(la),.lur_reject(lr),
.lus_valid(sv),.lus_ready(sready),.lus_length(sl),.lus_bytes(sb),.loader_ip(loader_ip),.expected_image_length(expected_image_length),.expected_image_crc(expected_image_crc),
.image_valid(core_image_valid),.image_length(image_length),.image_crc(image_crc),.image_read_address(image_read_address),.image_read_data(raw_image_data),.loading(loading),.load_complete(core_complete),.load_failed(core_failed),
.rtc_poll(rtc_poll),.time_server_ip(time_server_ip),.utc_ntp(utc_ntp),.monotonic_ticks(monotonic_ticks),.rtc_locked(rtc_locked),
.tx_valid(v1),.tx_ready(r1),.tx_length(len1),.tx_bytes(bytes1),.tx_destination_ip(ip1),.tx_source_port(sp1),.tx_destination_port(dp1),
.rx_valid(rx_valid),.rx_source_ip(rx_ip),.rx_source_port(rx_sport),.rx_destination_port(rx_dport),.rx_length(rx_length),.rx_bytes(rx_bytes));
afdx_tftp_client #(.MAX_FILE_BYTES(128),.TIMEOUT_CYCLES(TIMEOUT_CYCLES)) u_reports(
.clk(clk),.rst(rst),.start(report_start),.read_not_write(1'b0),.server_ip(loader_ip),.local_tid(16'd40002),
.filename_length(6'd10),.filename({176'd0,80'h53554c2e544547524154}),.put_length({8'd0,sl}),.put_address(report_address),.put_data(sb[report_address*8+:8]),
.tx_valid(v2),.tx_ready(r2),.tx_length(len2),.tx_bytes(bytes2),.tx_destination_ip(ip2),.tx_source_port(sp2),.tx_destination_port(dp2),
.rx_valid(rx_valid&&rx_dport==40002),.rx_source_ip(rx_ip),.rx_source_port(rx_sport),.rx_destination_port(rx_dport),.rx_length(rx_length),.rx_bytes(rx_bytes),
.busy(report_busy),.done(report_done),.error(report_failed),.file_valid(),.file_length(),.file_crc(),.read_address(16'd0),.read_data(),.retries(),.duplicates(),.rejected());
endmodule
