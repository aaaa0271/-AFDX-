`timescale 1ns/1ps
module tb_datagram_mac_joint;
wire [31:0] errors;wire finished;
model_foundation_system #(.MODE(1),.MESSAGE_BYTES(8192)) exercise(.errors(errors),.finished(finished));
initial begin wait(finished);if(errors==0)$display("TB_DATAGRAM_MAC_JOINT_PASS");else $display("TB_DATAGRAM_MAC_JOINT_FAIL");$finish;end
initial begin #200000000;$display("DATAGRAM_JOINT_TIMEOUT");$finish;end
endmodule
