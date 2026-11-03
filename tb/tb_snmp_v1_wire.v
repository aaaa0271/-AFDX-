`timescale 1ns/1ps
module tb_snmp_v1_wire;
 reg clk=0;always #5 clk=~clk;reg rst=1,req=0;reg [10:0] len=49;reg [4095:0] bytes=0;
 wire busy,done,valid,error;wire [7:0] code;wire [10:0] rlen;wire [4095:0] response;wire [31:0] snaps;integer errors=0,t;
 afdx_snmp_extended dut(.clk(clk),.rst(rst),.request_valid(req),.request_length(len),.request_bytes(bytes),
  .community_length(6'd11),.community_bytes({168'd0,88'h747365742d746867696c66}),.mib_values(800'd0),
  .busy(busy),.done(done),.response_valid(valid),.error(error),.error_code(code),.response_length(rlen),.response_bytes(response),.snapshot_event(),.snapshot_count(snaps),.version_override(2'd0));
 initial begin
  bytes=4096'h000501010159fd81010401062b0b060f3011300001020001027fff02021da0747365742d746867696c660b040001022f30;
  repeat(4)@(negedge clk);rst=0;@(negedge clk);req=1;@(negedge clk);req=0;
  t=0;while(!done&&t<10000)begin @(negedge clk);t=t+1;end
  if(!done||!valid||error)begin errors=errors+1;$display("FAIL v1 response code=%h",code);end
  if(response[4*8+:8]!==8'd0)begin errors=errors+1;$display("FAIL v1 response version=%h",response[4*8+:8]);end
  $display("SNMP_V1_RESPONSE len=%0d first=%h errors=%0d",rlen,response[0+:8],errors);
  if(errors==0)$display("TB_SNMP_V1_WIRE_PASS");else $display("TB_SNMP_V1_WIRE_FAIL");$finish;
 end
 initial begin #1000000;$display("SNMP_V1_TIMEOUT");$finish;end
endmodule
