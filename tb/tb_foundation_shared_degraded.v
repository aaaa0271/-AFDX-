`timescale 1ns/1ps
module tb_foundation_shared_degraded;
wire [31:0] errors;wire finished;
model_foundation_system #(.MODE(2)) exercise(.errors(errors),.finished(finished));
initial begin wait(finished);if(errors==0)$display("TB_FOUNDATION_SHARED_DEGRADED_PASS");else $display("TB_FOUNDATION_SHARED_DEGRADED_FAIL");$finish;end
initial begin #100000000;$display("FOUNDATION_TIMEOUT");$finish;end
endmodule
