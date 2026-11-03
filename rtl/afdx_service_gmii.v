`timescale 1ns/1ps
// Independent MAC-side service channel for loader and RTC. Incoming bytes are
// committed only after FCS + IPv4 + UDP validation; no test-double protocol path.
module afdx_service_gmii #(
 parameter [47:0] LOCAL_MAC=48'h030000000010,PEER_MAC=48'h020000000002,
 parameter [47:0] SOURCE_MAC=LOCAL_MAC,
 parameter [31:0] LOCAL_IP=32'h0a000010,
 parameter integer BAG_CYCLES=100000,
 parameter integer SPLIT_CLOCK=0,
 parameter [47:0] CLOCK_LOCAL_MAC=LOCAL_MAC,CLOCK_PEER_MAC=PEER_MAC,
 parameter integer EXTERNAL_ADMISSION=0
)(
 input wire clk,rst,input wire tx_admit,input wire [7:0] gmii_rxd,input wire gmii_rx_dv,gmii_rx_er,
 output wire [7:0] gmii_txd,output wire gmii_tx_en,gmii_tx_er,output wire tx_done,
 output reg rx_valid,output reg [31:0] rx_ip,output reg [15:0] rx_sport,rx_dport,
 output reg [10:0] rx_length,output reg [4127:0] rx_bytes,
 input wire tx_valid,output wire tx_ready,input wire [31:0] tx_ip,input wire [15:0] tx_sport,tx_dport,
 input wire [10:0] tx_length,input wire [4127:0] tx_bytes,
 output reg [31:0] received,rejected,
 output wire idle,
 input wire [63:0] gmii_rx_timestamp,output reg [63:0] rx_timestamp
);
wire [7:0] bd,pd;wire bv,br,bs,be,pm,pv,ps,pe,pdone,pgood;wire [10:0] bl,pl;
wire [47:0] dm;wire [31:0] sip,dip;wire [15:0] usp,udp;wire crc_error;
reg [4127:0] buffer_q;reg [10:0] count,length_q;reg admitted,bad;
reg [31:0] source_q;reg [15:0] sport_q,dport_q;
wire [63:0] body_timestamp;reg [63:0] timestamp_q;
gmii_rx_adapter u_l2(.clk(clk),.rst(rst),.gmii_rxd(gmii_rxd),.gmii_rx_dv(gmii_rx_dv),.gmii_rx_er(gmii_rx_er),
.m_data(bd),.m_valid(bv),.m_ready(br),.m_sof(bs),.m_eof(be),.m_frame_length(bl),.crc_error(crc_error),.good_frame(),.output_frame_done(),.format_error(),.length_error(),.rx_error(),.overflow_error(),
.gmii_timestamp(gmii_rx_timestamp),.m_timestamp(body_timestamp));
afdx_eth_ipv4_udp_parser #(.MAX_PAYLOAD_BYTES(516)) u_parser(.clk(clk),.rst(rst),.s_data(bd),.s_valid(bv),.s_ready(br),.s_sof(bs),.s_eof(be),.s_frame_length(bl),
.dst_mac(dm),.src_mac(),.ether_type(),.ip_total_length(),.ip_ttl(),.ip_protocol(),.ip_header_checksum(),.src_ip(sip),.dst_ip(dip),
.udp_src_port(usp),.udp_dst_port(udp),.udp_length(),.udp_checksum(),.payload_length(pl),.padding_length(),.afdx_sequence(),.meta_valid(pm),
.payload_data(pd),.payload_valid(pv),.payload_ready(1'b1),.payload_sof(ps),.payload_eof(pe),.frame_done(pdone),.frame_valid(pgood),
.ether_type_error(),.ip_version_error(),.ip_ihl_error(),.ip_checksum_error(),.ip_protocol_error(),.ip_length_error(),.udp_length_error(),.udp_checksum_error(),.structure_error());
always @(posedge clk)begin
 if(rst)begin rx_valid<=0;rx_ip<=0;rx_sport<=0;rx_dport<=0;rx_length<=0;rx_bytes<=0;buffer_q<=0;count<=0;length_q<=0;admitted<=0;bad<=0;source_q<=0;sport_q<=0;dport_q<=0;received<=0;rejected<=0;timestamp_q<=0;rx_timestamp<=0;end
 else begin
  rx_valid<=0;
  if(bv&&br&&bs)timestamp_q<=body_timestamp;
  if(crc_error)rejected<=rejected+1'b1;
  if(pm)begin
   count<=0;length_q<=pl;buffer_q<=0;bad<=0;source_q<=sip;sport_q<=usp;dport_q<=udp;
   admitted<=(dm==LOCAL_MAC||(SPLIT_CLOCK&&dm==CLOCK_LOCAL_MAC))&&dip==LOCAL_IP&&pl>0&&pl<=516;
  end
  if(pv)begin
   if(pm||count<516)buffer_q[(pm?0:count)*8+:8]<=pd;else bad<=1;
   if(ps!==(pm||count==0))bad<=1;
   count<=pm?11'd1:count+1'b1;
  end
  if(pdone)begin
   admitted<=0;
   if(pgood&&admitted&&!bad&&count==length_q)begin
    rx_valid<=1;rx_ip<=source_q;rx_sport<=sport_q;rx_dport<=dport_q;rx_length<=length_q;rx_bytes<=buffer_q;rx_timestamp<=timestamp_q;received<=received+1'b1;
   end else rejected<=rejected+1'b1;
  end
 end
end
wire [7:0] td;wire tv,te,tr,fb_busy,fb_done,underrun;
reg in_flight;reg [4:0] retire;reg [31:0] bag;
reg [7:0] sequence_num,clock_sequence;
wire clock_packet=SPLIT_CLOCK&&tx_sport==16'd40001;
// Guard the bounded two-buffer RX replay and parser tail after raw input stops.
// This includes bubbles that cannot be observed from payload-valid alone.
reg [12:0] rx_guard;
always @(posedge clk)begin
 if(rst)rx_guard<=0;
 else if(gmii_rx_dv||bv||pm||pv||pdone||rx_valid)rx_guard<=13'd4096;
 else if(rx_guard!=0)rx_guard<=rx_guard-1'b1;
end
assign idle=!in_flight&&!tx_valid&&!gmii_rx_dv&&rx_guard==0;
wire launch=tx_valid&&tx_ready;
assign tx_ready=!rst&&!in_flight&&bag==0&&(!EXTERNAL_ADMISSION||tx_admit)&&tx_length>=1&&tx_length<=516;
always @(posedge clk)begin
 if(rst)begin in_flight<=0;retire<=0;bag<=0;sequence_num<=0;clock_sequence<=0;end
 else begin
  if(bag!=0)bag<=bag-1'b1;
  if(launch)begin in_flight<=1;bag<=BAG_CYCLES>0?BAG_CYCLES-1:0;if(clock_packet)clock_sequence<=clock_sequence==255?8'd1:clock_sequence+1'b1;else sequence_num<=sequence_num==255?8'd1:sequence_num+1'b1;end
  if(tx_done)retire<=14;
  else if(retire!=0)begin retire<=retire-1'b1;if(retire==1)in_flight<=0;end
 end
end
afdx_service_frame_builder u_builder(.clk(clk),.rst(rst),.start(launch),.seq_num(clock_packet?clock_sequence:sequence_num),
.cfg_dst_mac(clock_packet?CLOCK_PEER_MAC:PEER_MAC),.cfg_src_mac(SOURCE_MAC),.cfg_src_ip(LOCAL_IP),.cfg_dst_ip(tx_ip),.cfg_src_port(tx_sport),.cfg_dst_port(tx_dport),
.payload_length(tx_length),.payload_bytes(tx_bytes),.tx_data(td),.tx_valid(tv),.tx_eof(te),.tx_ready(tr),.busy(fb_busy),.done(fb_done));
gmii_tx_adapter_varlen u_tx(.clk(clk),.rst(rst),.s_data(td),.s_valid(tv),.s_eof(te),.s_ready(tr),.gmii_txd(gmii_txd),.gmii_tx_en(gmii_tx_en),.gmii_tx_er(gmii_tx_er),.frame_done(tx_done),.underrun(underrun));
endmodule
