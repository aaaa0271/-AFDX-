`timescale 1ns/1ps
module tb_review_tftp_budget;
reg clk=0;always #5 clk=~clk;
reg rst=1,start=0,rx=0,ready=1,get_mode=1;
reg [15:0] source=30000;reg [10:0] length=5;reg [4127:0] packet=0;
wire tx,busy,done,error,file_valid;wire [15:0] file_length;wire [31:0] retries,duplicates;
integer errors=0,cases=0,k,n;
afdx_tftp_client #(.TIMEOUT_CYCLES(20),.MAX_RETRIES(3)) dut(
 .clk(clk),.rst(rst),.start(start),.read_not_write(get_mode),.server_ip(32'h0a000001),.local_tid(16'd40000),
 .filename_length(6'd1),.filename(256'h41),.put_length(16'd0),.put_data(8'd0),
 .tx_valid(tx),.tx_ready(ready),.rx_valid(rx),.rx_source_ip(32'h0a000001),.rx_source_port(source),
 .rx_destination_port(16'd40000),.rx_length(length),.rx_bytes(packet),.busy(busy),.done(done),.error(error),
 .file_valid(file_valid),.file_length(file_length),.read_address(16'd0),.retries(retries),.duplicates(duplicates));
task fail;input [511:0] why;begin errors=errors+1;$display("FAIL TFTP_BUDGET %0s",why);end endtask
task reset_case;input mode;begin
 cases=cases+1;rst=1;start=0;rx=0;ready=1;get_mode=mode;source=30000;
 repeat(3)@(negedge clk);rst=0;start=1;@(negedge clk);start=0;
 while(tx)@(negedge clk);
end endtask
task data;input [15:0] block;input [10:0] size;begin
 packet=0;packet[15:8]=3;packet[23:16]=block[15:8];packet[31:24]=block[7:0];packet[39:32]=8'h5a;length=size;rx=1;
 @(negedge clk);rx=0;
end endtask
always @(negedge clk)if(!rst&&error&&file_valid)fail("error and file_valid asserted together");
initial begin
 for(k=18;k<=19;k=k+1)begin
  reset_case(1);while(dut.attempts<3||tx)@(negedge clk);
  while(dut.timer<k)@(negedge clk);data(1,5);repeat(5)@(negedge clk);
  if(error||!file_valid||file_length!=1)fail("expected DATA lost at final deadline");
 end
 reset_case(1);repeat(100)@(negedge clk);data(1,5);repeat(5)@(negedge clk);
 if(busy||!error||file_valid)fail("late DATA resurrected failed transfer");
 for(k=0;k<3;k=k+1)begin
  reset_case(1);data(1,516);while(dut.state!=1||tx)@(negedge clk);
  if(k==1)source=30001;
  for(n=0;n<40;n=n+1)begin
   repeat(4)@(negedge clk);data(1,516);
   if(k==2&&n==0)ready=0;
   @(negedge clk);
  end
  if(busy||!error||file_valid)fail("non-progress traffic renewed budget");
  ready=1;
 end
 reset_case(1);data(1,5);while(tx||dut.state!=4)@(negedge clk);
 for(n=0;n<20;n=n+1)begin repeat(2)@(negedge clk);data(1,5);end
 if(dut.state!=0||error||!file_valid)fail("duplicate final DATA extended dally");
 reset_case(0);while(dut.attempts<3||tx)@(negedge clk);
 while(dut.timer<19)@(negedge clk);
 packet=0;packet[15:8]=4;length=4;rx=1;@(negedge clk);rx=0;repeat(5)@(negedge clk);
 if(error||dut.block_number!=1)fail("WRQ ACK lost at final deadline");
 $display("TFTP_BUDGET_CASES=%0d",cases);
 if(errors==0)$display("TB_REVIEW_TFTP_BUDGET_PASS");$finish;
end
initial begin #100000;fail("watchdog");$finish;end
endmodule
