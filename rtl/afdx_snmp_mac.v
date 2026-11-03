`timescale 1ns/1ps
module afdx_snmp_mac #(
 parameter integer BAG_CYCLES=100000,
 parameter integer EXTERNAL_ADMISSION=0,
 parameter integer CLK_HZ=12500000,ENGINE_LENGTH=9,USER_LENGTH=4,
 parameter [255:0] ENGINE_ID=256'h5844464105d97e0080,USER_NAME=256'h78646661,
 parameter [30:0] ENGINE_BOOTS=1,
 parameter [47:0] SOURCE_MAC=48'h020000000010,PEER_MAC=48'h030000000011
)(
 input wire clk,rst,input wire tx_admit,
 input wire [5:0] community_length,input wire [255:0] community_bytes,input wire [799:0] mib_values,
 input wire [7:0] rxd,input wire dv,er,
 output wire [7:0] txd,output wire txen,txer,tx_done,
 output wire busy,output reg [31:0] busy_drops,output wire [31:0] snapshots
);
wire rv;wire [31:0] rip;wire [15:0] rsp,rdp;wire [10:0] rlen;wire [4127:0] rb;
wire txready,agent_done,agent_valid,agent_error,agent_busy;wire [10:0] length;wire [4095:0] bytes;
reg [1:0] state;reg fire;reg [10:0] len_q;reg [4095:0] req_q;
reg [31:0] peer;reg [15:0] port;
assign busy=state!=0;
afdx_service_gmii #(.LOCAL_MAC(48'h030000000001),.SOURCE_MAC(SOURCE_MAC),.PEER_MAC(PEER_MAC),.LOCAL_IP(32'hc0a80101),.BAG_CYCLES(BAG_CYCLES),.EXTERNAL_ADMISSION(EXTERNAL_ADMISSION)) mac(
.clk(clk),.rst(rst),.tx_admit(tx_admit),.gmii_rxd(rxd),.gmii_rx_dv(dv),.gmii_rx_er(er),.gmii_txd(txd),.gmii_tx_en(txen),.gmii_tx_er(txer),.tx_done(tx_done),
.rx_valid(rv),.rx_ip(rip),.rx_sport(rsp),.rx_dport(rdp),.rx_length(rlen),.rx_bytes(rb),
.tx_valid(state==2),.tx_ready(txready),.tx_ip(peer),.tx_sport(16'd161),.tx_dport(port),.tx_length(length),.tx_bytes({32'd0,bytes}),.received(),.rejected());
afdx_snmp_wire #(.CLK_HZ(CLK_HZ),.ENGINE_LENGTH(ENGINE_LENGTH),.USER_LENGTH(USER_LENGTH),
 .ENGINE_ID(ENGINE_ID),.USER_NAME(USER_NAME),.ENGINE_BOOTS(ENGINE_BOOTS)) agent(.clk(clk),.rst(rst),.request_valid(fire),.request_length(len_q),.request_bytes(req_q),
.community_length(community_length),.community_bytes(community_bytes),.mib_values(mib_values),.busy(agent_busy),.done(agent_done),.response_valid(agent_valid),.error(agent_error),.error_code(),.response_length(length),.response_bytes(bytes),.snapshot_event(),.snapshot_count(snapshots));
always @(posedge clk)begin
 if(rst)begin state<=0;fire<=0;len_q<=0;req_q<=0;peer<=0;port<=0;busy_drops<=0;end
 else begin
  fire<=0;
  if(rv&&rdp==161&&rlen<=512)begin
   if(state==0)begin len_q<=rlen;req_q<=rb[4095:0];peer<=rip;port<=rsp;fire<=1;state<=1;end
   else busy_drops<=busy_drops+1'b1;
  end
  if(state==1&&agent_done)state<=agent_valid&&!agent_error?2:0;
  if(state==2&&txready)state<=0;
 end
end
endmodule
