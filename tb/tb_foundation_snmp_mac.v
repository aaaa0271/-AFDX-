`timescale 1ns/1ps
module tb_foundation_snmp_mac;
wire [31:0] errors;wire finished;
model_foundation_system #(.MODE(0)) exercise(.errors(errors),.finished(finished));
initial begin wait(finished);if(errors==0)$display("TB_FOUNDATION_SNMP_MAC_PASS");else $display("TB_FOUNDATION_SNMP_MAC_FAIL");$finish;end
initial begin #100000000;$display("FOUNDATION_TIMEOUT");$finish;end
endmodule
