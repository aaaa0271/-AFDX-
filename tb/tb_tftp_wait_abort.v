`timescale 1ns/1ps
module tb_tftp_wait_abort;
reg clk=0;always #5 clk=~clk;reg rst=1,start=0,rx=0,ready=1;
reg [31:0] ip=32'h0a000001;reg [15:0] sp=30000,dp=40000;reg [10:0] len=0;reg [4127:0] bytes=0;
wire tv,busy,done,error,valid,idle,waiting,remote_abort;wire [15:0] status,abort_status,port,flen;
wire [31:0] retries,rejected;wire [10:0] tl;wire [4127:0] tx;
integer errors=0,t,i,tx_count=0,abort_count=0;
afdx_tftp_client #(.TIMEOUT_CYCLES(24),.CLK_HZ(10),.MAX_RETRIES(2),.MAX_WAIT_RESPONSES(2)) dut(
 .clk(clk),.rst(rst),.start(start),.read_not_write(1'b1),.server_ip(32'h0a000001),.local_tid(16'd40000),
 .filename_length(6'd5),.filename(256'h50554c2e41),.put_length(16'd0),.put_address(),.put_data(8'd0),
 .tx_valid(tv),.tx_ready(ready),.tx_length(tl),.tx_bytes(tx),.tx_destination_ip(),.tx_source_port(),.tx_destination_port(port),
 .rx_valid(rx),.rx_source_ip(ip),.rx_source_port(sp),.rx_destination_port(dp),.rx_length(len),.rx_bytes(bytes),
 .busy(busy),.done(done),.error(error),.file_valid(valid),.file_length(flen),.file_crc(),.read_address(16'd0),.read_data(),
 .retries(retries),.duplicates(),.rejected(rejected),.idle(idle),.wait_active(waiting),.remote_abort(remote_abort),.error_code(status),.abort_status(abort_status));
always @(posedge clk)if(!rst)begin if(tv&&ready)tx_count=tx_count+1;if(remote_abort)abort_count=abort_count+1;end
task fail;input [511:0] why;begin errors=errors+1;$display("FAIL WAIT_ABORT %0s",why);end endtask
task begin_file;begin
 @(negedge clk);start=1;@(negedge clk);start=0;
 if(!tv||tx[15:8]!=1||!busy)fail("RRQ launch");@(negedge clk);
end endtask
task packet;begin @(negedge clk);rx=1;@(negedge clk);rx=0;end endtask
task wait_error;input [7:0] digit;begin
 bytes=0;bytes[15:8]=5;bytes[32+:40]=40'h3a54494157;bytes[72+:8]=digit;len=11;packet;
end endtask
task abort_error;begin
 bytes=0;bytes[15:8]=5;bytes[32+:80]=80'h343030313a54524f4241;len=15;packet;
end endtask
task success;begin
 bytes=0;bytes[15:8]=3;bytes[31:24]=1;bytes[39:32]=8'h5a;len=5;packet;
 t=0;while(!done&&t<50)begin @(negedge clk);t=t+1;end
 if(!done||error||!valid||flen!=1)fail("recovery payload");
 repeat(28)@(negedge clk);if(!idle)fail("dally did not expire");
end endtask
initial begin
 repeat(4)@(negedge clk);rst=0;
 begin_file;wait_error("2");if(!waiting||!busy||idle)fail("WAIT state");
 repeat(18)begin @(negedge clk);if(tv||!waiting)fail("early WAIT retry");end
 t=0;while(!tv&&t<10)begin @(negedge clk);t=t+1;end
 if(!tv||port!=69||tx[15:8]!=1||retries!=1)fail("WAIT must retry original RRQ");@(negedge clk);success;
 begin_file;wait_error("9");ip=32'h0a000002;abort_error;
 if(!waiting||error||remote_abort)fail("wrong peer aborted WAIT");
 ip=32'h0a000001;abort_error;
 if(!error||busy||valid||!remote_abort||abort_status!=16'h1004)fail("remote ABORT while waiting");
 repeat(2)@(negedge clk);begin_file;success;
 // Repeated WAIT responses cannot extend the transfer forever.
 begin_file;
 for(i=0;i<2;i=i+1)begin wait_error("0");repeat(3)@(negedge clk);end
 wait_error("0");if(!error||busy||status!=16'h8003)fail("bounded WAIT budget");
 // Traffic for another endpoint cannot suspend this transfer's timeout.
 begin_file;ip=32'h0a000002;bytes=0;len=4;rx=1;
 repeat(100)@(negedge clk);rx=0;ip=32'h0a000001;
 if(!error||busy||status!=16'h8001)fail("unrelated traffic stopped timeout");
 begin_file;success;
 $display("WAIT_ABORT_EVENTS=%0d errors=%0d",abort_count,errors);
 if(errors==0)$display("TB_TFTP_WAIT_ABORT_PASS");else $display("TB_TFTP_WAIT_ABORT_FAIL");$finish;
end
initial begin #100000;errors=errors+1;$display("FAIL wait/abort watchdog");$finish;end
endmodule
