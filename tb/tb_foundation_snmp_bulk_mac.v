`timescale 1ns/1ps
module tb_foundation_snmp_bulk_mac;
wire [31:0] errors;wire finished;
model_foundation_system #(.MODE(0),.BULK_TEST(1)) exercise(.errors(errors),.finished(finished));
initial begin wait(finished);if(errors==0)$display("TB_FOUNDATION_SNMP_BULK_MAC_PASS");else $display("TB_FOUNDATION_SNMP_BULK_MAC_FAIL");$finish;end
initial begin #100000000;$display("BULK_MAC_TIMEOUT");$finish;end
endmodule
