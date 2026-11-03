`timescale 1ns/1ps
module tb_615a_control_recovery;
reg clk=0;always #5 clk=~clk;reg rst=1,rx=0;
reg [31:0] ip=32'h0a000001;reg [15:0] sp=32000,dp=69;reg [10:0] len=0;reg [4127:0] bytes=0;
wire init,lur,tv;wire [10:0] tl;wire [4127:0] tx;
integer errors=0,initializations=0,requests=0;
afdx_615a_control_tftp #(.TIMEOUT_CYCLES(20)) dut(.clk(clk),.rst(rst),.loader_ip(32'h0a000001),
 .rx_valid(rx),.rx_ip(ip),.rx_sport(sp),.rx_dport(dp),.rx_length(len),.rx_bytes(bytes),
 .tx_valid(tv),.tx_ready(1'b1),.tx_ip(),.tx_sport(),.tx_dport(),.tx_length(tl),.tx_bytes(tx),
 .initialize(init),.lui_valid(1'b0),.lui_ready(),.lui_bytes(80'd0),
 .lur_valid(lur),.lur_length(),.lur_bytes(),.lur_accept(1'b0),.lur_reject(1'b0),.loading(1'b0));
always @(posedge clk)if(!rst)begin if(init)initializations=initializations+1;if(lur)requests=requests+1;end
task control;input integer op;input [79:0] name;
 begin
  @(negedge clk);rx=1;dp=69;len=19;bytes=0;bytes[15:8]=op;
  bytes[16+:80]=name;bytes[104+:48]=48'h00746574636f;
  @(negedge clk);rx=0;repeat(3)@(negedge clk);
 end
endtask
initial begin
 repeat(4)@(negedge clk);rst=0;
 control(1,80'h49554c2e544547524154);
 repeat(25)@(negedge clk);
 control(1,80'h49554c2e544547524154);
 if(initializations!=2)begin errors=errors+1;$display("FAIL LUI response stall recovery");end
 repeat(25)@(negedge clk);
 control(2,80'h52554c2e544547524154);
 @(negedge clk);rx=1;dp=41000;len=5;bytes=0;bytes[15:8]=3;bytes[31:24]=1;
 @(negedge clk);rx=0;repeat(25)@(negedge clk);
 control(1,80'h49554c2e544547524154);
 if(initializations!=3||requests!=1)begin errors=errors+1;$display("FAIL LUR application stall recovery");end
 repeat(25)@(negedge clk);ip=32'h0a000002;
 control(1,80'h49554c2e544547524154);
 if(initializations!=3)begin errors=errors+1;$display("FAIL wrong Loader admitted");end
 if(errors==0)$display("TB_615A_CONTROL_RECOVERY_PASS");else $display("TB_615A_CONTROL_RECOVERY_FAIL");$finish;
end
endmodule
