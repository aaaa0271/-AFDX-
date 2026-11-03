`timescale 1ns/1ps
module tb_snmp_versions #(parameter integer MAC=0);
reg clk=0;always #5 clk=~clk;reg rst=1,req=0;
reg [10:0] len=0;reg [4095:0] bytes=0;wire done,valid,error,busy;
wire [10:0] rlen;wire [4095:0] response;wire [31:0] snapshots;
reg [799:0] mib=800'd123456;integer errors=0,cases=0,t,j;
wire peer_ready;
generate if(!MAC)begin:DIRECT
 afdx_snmp_wire #(.CLK_HZ(10000000)) dut(.clk(clk),.rst(rst),.request_valid(req),.request_length(len),.request_bytes(bytes),
 .community_length(6'd6),.community_bytes(256'h63696c627570),.mib_values(mib),.busy(busy),.done(done),.response_valid(valid),.error(error),.error_code(),
 .response_length(rlen),.response_bytes(response),.snapshot_event(),.snapshot_count(snapshots));
 assign peer_ready=1;
end else begin:WIRE
 wire [7:0] to_target,to_peer;wire to_target_en,to_target_er,to_peer_en,to_peer_er;
 wire received;wire [10:0] received_length;wire [4127:0] received_bytes;
 reg got=0;reg [10:0] saved_len=0;reg [4095:0] saved_bytes=0;
 afdx_snmp_mac #(.CLK_HZ(10000000),.BAG_CYCLES(1)) dut(.clk(clk),.rst(rst),.tx_admit(1'b1),
 .community_length(6'd6),.community_bytes(256'h63696c627570),.mib_values(mib),
 .rxd(to_target),.dv(to_target_en),.er(to_target_er),.txd(to_peer),.txen(to_peer_en),.txer(to_peer_er),.tx_done(),
 .busy(busy),.busy_drops(),.snapshots(snapshots));
 afdx_service_gmii #(.LOCAL_MAC(48'h030000000011),.SOURCE_MAC(48'h020000000073),.PEER_MAC(48'h030000000001),
 .LOCAL_IP(32'hc0a80173),.BAG_CYCLES(1)) peer(.clk(clk),.rst(rst),.tx_admit(1'b1),
 .gmii_rxd(to_peer),.gmii_rx_dv(to_peer_en),.gmii_rx_er(to_peer_er),.gmii_txd(to_target),.gmii_tx_en(to_target_en),.gmii_tx_er(to_target_er),.tx_done(),
 .rx_valid(received),.rx_ip(),.rx_sport(),.rx_dport(),.rx_length(received_length),.rx_bytes(received_bytes),
 .tx_valid(req),.tx_ready(peer_ready),.tx_ip(32'hc0a80101),.tx_sport(16'd32000),.tx_dport(16'd161),.tx_length(len),.tx_bytes({32'd0,bytes}),.received(),.rejected(),.idle());
 always @(posedge clk)begin
  if(rst||req)got<=0;
  else if(received)begin got<=1;saved_len<=received_length;saved_bytes<=received_bytes[4095:0];end
 end
 assign done=got;assign valid=got;assign error=0;assign rlen=saved_len;assign response=saved_bytes;
end endgenerate
 task query;input integer id;input [4095:0] b;input integer n,drop;
 begin
  @(negedge clk);bytes=b;len=n;req=1;#1;
  t=0;while(!peer_ready&&t<20000)begin @(negedge clk);t=t+1;end
  @(negedge clk);req=0;t=0;
  while(!done&&t<20000)begin @(negedge clk);t=t+1;end
  if(drop)begin
   if((!MAC&&(!done||!error||valid))||(MAC&&done))begin errors=errors+1;$display("FAIL rejected request produced response id=%0d",id);end
   $display("VERSION_RESPONSE id=%0d drop=1 hex=",id);
  end else begin
   if(!done||!valid||error)begin errors=errors+1;$display("FAIL response id=%0d done=%b valid=%b error=%b",id,done,valid,error);end
   $write("VERSION_RESPONSE id=%0d drop=0 hex=",id);
   for(j=0;j<rlen;j=j+1)$write("%02x",response[j*8+:8]);$display("");
  end
  cases=cases+1;repeat(20)@(negedge clk);
 end endtask
 initial begin
  repeat(5)@(negedge clk);rst=0;
  `include "snmp_versions.vh"
  $display("SNMP_VERSION_CASES=%0d MAC=%0d errors=%0d snapshots=%0d",cases,MAC,errors,snapshots);
  if(errors==0)$display("TB_SNMP_VERSIONS_PASS");else $display("TB_SNMP_VERSIONS_FAIL");$finish;
 end
 initial begin #50000000;errors=errors+1;$display("FAIL SNMP versions watchdog");$finish;end
endmodule
