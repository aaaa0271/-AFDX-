`timescale 1ns/1ps
// Declared RTC profile: NTPv4 CLIENT only (transmits Mode 3 client requests,
// accepts Mode 4 server responses), one configured server, no NTP
// authentication/peer election and no server mode. UTC may step;
// monotonic_ticks never steps.
module afdx_rtc_ntp #(
 parameter integer CLK_HZ=100000000,
 parameter integer RESPONSE_TIMEOUT=100000000,
 parameter integer HOLDOVER_CYCLES=400000000,
 parameter integer MAC_TIMESTAMPS=0,
 parameter [63:0] INITIAL_TIME=64'h0000000100000000
)(
 input wire clk,rst,poll,input wire [31:0] server_ip,
 output reg tx_valid,input wire tx_ready,output reg [383:0] tx_bytes,
 input wire rx_valid,input wire [31:0] rx_source_ip,input wire [15:0] rx_source_port,
 input wire [7:0] rx_length,input wire [383:0] rx_bytes,
 output reg [63:0] utc_ntp,monotonic_ticks,
 output reg synchronized,output reg sync_event,reject_event,timeout_event,
 output reg signed [63:0] last_offset,output reg [63:0] last_delay,
 output reg [31:0] sync_count,reject_count,timeout_count,
 output wire busy,
 input wire tx_timestamp_valid,input wire [63:0] tx_timestamp,tx_origin,
 input wire [31:0] tx_peer_ip,
 input wire rx_timestamp_valid,input wire [63:0] rx_timestamp
);
localparam [63:0] SECOND=64'h0000000100000000;
localparam [63:0] STEP=SECOND/CLK_HZ;
localparam [63:0] REMAINDER=SECOND%CLK_HZ;
reg [63:0] frac_remainder,t1,request_origin;
reg [31:0] age,holdover_age,peer_q;reg waiting,stamp_known;
wire [63:0] correction_tick=STEP+((frac_remainder+REMAINDER>=CLK_HZ)?64'd1:64'd0);
assign busy=waiting||tx_valid;
function [63:0] network_timestamp;
 input [383:0] packet;input integer offset;integer j;reg [63:0] value;
 begin value=0;for(j=0;j<8;j=j+1)value={value[55:0],packet[(offset+j)*8+:8]};network_timestamp=value;end
endfunction
wire [63:0] origin=network_timestamp(rx_bytes,24);
wire [63:0] t2=network_timestamp(rx_bytes,32);
wire [63:0] t3=network_timestamp(rx_bytes,40);
wire [63:0] t4=MAC_TIMESTAMPS?rx_timestamp:utc_ntp;
wire signed [63:0] d21=$signed(t2-t1),d34=$signed(t3-t4);
wire signed [64:0] sum_offset={d21[63],d21}+{d34[63],d34};
wire signed [63:0] offset=sum_offset>>>1;
wire signed [63:0] path_delay=$signed(t4-t1)-$signed(t3-t2);
wire [7:0] flags=rx_bytes[7:0];wire [7:0] stratum=rx_bytes[15:8];
wire acceptable=waiting && stamp_known && (!MAC_TIMESTAMPS||rx_timestamp_valid) &&
 rx_length==48 && rx_source_ip==peer_q && rx_source_port==123 &&
 flags[2:0]==4 && flags[5:3]==4 && flags[7:6]!=3 && stratum>=1 && stratum<=15 &&
 origin==request_origin && t2!=0 && t3!=0 && $signed(t3-t2)>=0 && path_delay>=0;
integer i;
always @(posedge clk)begin
 if(rst)begin
  utc_ntp<=INITIAL_TIME;monotonic_ticks<=0;frac_remainder<=0;t1<=0;request_origin<=0;stamp_known<=0;age<=0;holdover_age<=0;peer_q<=0;waiting<=0;
  tx_valid<=0;tx_bytes<=0;synchronized<=0;sync_event<=0;reject_event<=0;timeout_event<=0;
  last_offset<=0;last_delay<=0;sync_count<=0;reject_count<=0;timeout_count<=0;
 end else begin
  utc_ntp<=utc_ntp+correction_tick;monotonic_ticks<=monotonic_ticks+1'b1;
  if(frac_remainder+REMAINDER>=CLK_HZ)frac_remainder<=frac_remainder+REMAINDER-CLK_HZ;
  else frac_remainder<=frac_remainder+REMAINDER;
  sync_event<=0;reject_event<=0;timeout_event<=0;
  if(holdover_age<HOLDOVER_CYCLES)holdover_age<=holdover_age+1'b1;
  else synchronized<=0;
  if(poll&&!busy)begin
   tx_valid<=1;tx_bytes<=0;tx_bytes[7:0]<=8'h23;tx_bytes[2*8+:8]<=6;tx_bytes[3*8+:8]<=8'hec;
   request_origin<=utc_ntp;peer_q<=server_ip;stamp_known<=0;
   for(i=0;i<8;i=i+1)tx_bytes[(40+i)*8+:8]<=utc_ntp[63-i*8-:8];
  end
  if(tx_valid&&tx_ready)begin
   tx_valid<=0;waiting<=1;age<=0;
   // Datagram-only users define their observation point at this handshake.
   if(!MAC_TIMESTAMPS)begin t1<=utc_ntp;stamp_known<=1;end
  end
  // The immutable wire timestamp is an origin token. T1 is the actual MAC
  // departure, after all arbitration and store-and-forward buffering.
  if(MAC_TIMESTAMPS&&waiting&&!stamp_known&&tx_timestamp_valid&&
     tx_origin==request_origin&&tx_peer_ip==peer_q)begin
   t1<=tx_timestamp;stamp_known<=1;age<=0;
  end
  if(waiting)begin
   if(age>=RESPONSE_TIMEOUT-1&&!(rx_valid&&acceptable))begin
    waiting<=0;timeout_event<=1;timeout_count<=timeout_count+1'b1;
   end else if(!(MAC_TIMESTAMPS&&tx_timestamp_valid&&!stamp_known&&tx_origin==request_origin&&tx_peer_ip==peer_q))age<=age+1'b1;
  end
  if(rx_valid)begin
   if(acceptable)begin
    utc_ntp<=utc_ntp+offset+correction_tick;last_offset<=offset;last_delay<=path_delay;
    waiting<=0;synchronized<=1;holdover_age<=0;sync_event<=1;sync_count<=sync_count+1'b1;
   end else begin reject_event<=1;reject_count<=reject_count+1'b1;end
  end
 end
end
endmodule

// Observe only the final MAC stream. No packet rewriting is needed: the
// origin token binds the measured departure to one pending NTP request.
module afdx_ntp_tx_timestamp(
 input wire clk,rst,input wire [63:0] utc,
 input wire [7:0] data,input wire valid,error,
 output reg event_valid,output reg [63:0] timestamp,origin,
 output reg [31:0] peer_ip
);
reg previous,bad;reg [10:0] count;reg [63:0] first,token;
reg [31:0] destination,crc;reg [15:0] sport,dport,udp_length;
reg [7:0] flags;
function [31:0] crcbyte;input [31:0] c;input [7:0] x;reg [31:0] v;integer k;begin
 v=c^x;for(k=0;k<8;k=k+1)v=v[0]?(v>>1)^32'hedb88320:v>>1;crcbyte=v;
end endfunction
always @(posedge clk)begin
 if(rst)begin previous<=0;bad<=0;count<=0;first<=0;token<=0;destination<=0;crc<=32'hffffffff;sport<=0;dport<=0;udp_length<=0;flags<=0;event_valid<=0;timestamp<=0;origin<=0;peer_ip<=0;end
 else begin
  previous<=valid;event_valid<=0;
  if(valid)begin
   if(!previous)begin first<=utc;count<=1;bad<=error||data!=8'h55;crc<=32'hffffffff;end
   else begin
    if(count<1535)count<=count+1'b1;else bad<=1;
    if(error||(count<7&&data!=8'h55)||(count==7&&data!=8'hd5))bad<=1;
    if(count>=8)crc<=crcbyte(crc,data);
    if(count==20&&data!=8'h08)bad<=1;
    if(count==21&&data!=0)bad<=1;
    if(count==22&&data!=8'h45)bad<=1;
    if(count==31&&data!=17)bad<=1;
    if(count>=38&&count<=41)destination<={destination[23:0],data};
    if(count==42||count==43)sport<={sport[7:0],data};
    if(count==44||count==45)dport<={dport[7:0],data};
    if(count==46||count==47)udp_length<={udp_length[7:0],data};
    if(count==50)flags<=data;
    if(count>=90&&count<=97)token<={token[55:0],data};
   end
  end else if(previous&&!bad&&count==103&&crc==32'hdebb20e3&&sport==40001&&dport==123&&udp_length==56&&flags==8'h23)begin
   event_valid<=1;timestamp<=first;origin<=token;peer_ip<=destination;
  end
 end
end
endmodule
