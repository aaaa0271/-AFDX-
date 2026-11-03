`timescale 1ns/1ps
module tb_defense_boundary;
reg clk=0;always #5 clk=~clk;reg rst=1;reg [63:0] cycle=0;
reg [7:0] data=0;reg valid=0,ai_block=0;
reg cv=0,cw=0;reg [15:0] ca=0;reg [31:0] wd=0;wire cr,ce;wire [31:0] rd;
wire out_valid;wire [7:0] out_data;wire [63:0] delay;
wire [31:0] forwarded,blocked,timeouts,overflows,ai_denied,stale;
integer errors=0,cases=0,i,k,emitted=0;reg [7:0] frame[0:71];reg [31:0] crc;
reg [63:0] rid;reg [31:0] generation;
afdx_defense_gate #(.DEADLINE_CYCLES(180)) dut(
 .clk(clk),.rst(rst),.cycle(cycle),.policy_epoch(32'd1),.a_data(data),.a_valid(valid),.a_error(1'b0),.b_data(8'd0),.b_valid(1'b0),.b_error(1'b0),
 .a_delay(64'd7),.b_delay(64'd0),.ai_block(ai_block),.out_a(out_data),.out_b(),.out_av(out_valid),.out_bv(),.out_ae(),.out_be(),.out_a_delay(delay),.out_b_delay(),
 .cfg_valid(cv),.cfg_write(cw),.cfg_addr(ca),.cfg_wdata(wd),.cfg_ready(cr),.cfg_error(ce),.cfg_rdata(rd),.idle(),.request_valid(),
 .forwarded(forwarded),.blocked(blocked),.timeouts(timeouts),.ai_blocked(ai_denied),.stale_responses(stale),.overflows(overflows),.last_request(),.last_latency(),.last_reason());
function [31:0] crcbyte;input [31:0] c;input [7:0] x;reg [31:0] v;integer n;begin v=c^x;for(n=0;n<8;n=n+1)v=v[0]?(v>>1)^32'hedb88320:v>>1;crcbyte=v;end endfunction
task fail;input [511:0] why;begin errors=errors+1;$display("FAIL DEFENSE_BOUNDARY %0s",why);end endtask
always @(posedge clk)begin if(rst)cycle<=100;else cycle<=cycle+1'b1;end
always @(negedge clk)if(out_valid)begin
 if(out_data!==frame[emitted%72])fail("whole-frame replay content");
 if(delay<7)fail("original arrival delay lost");
 emitted=emitted+1;
end
task write;input [15:0] address;input [31:0] value;begin
 @(negedge clk);ca=address;wd=value;cv=1;cw=1;#1;if(ce)fail("unexpected CSR rejection");
 @(negedge clk);cv=0;cw=0;
end endtask
task send_frame;begin
 for(k=0;k<72;k=k+1)begin @(negedge clk);data=frame[k];valid=1;end
 @(negedge clk);valid=0;
 while(dut.state!=2)@(negedge clk);
 rid=dut.request_id;generation=dut.generation_q;
end endtask
task vote;input integer executor;input allow_value;input integer epoch_delta;input [31:0] digest;begin
 write(16'h1100+executor*64,rid[31:0]);write(16'h1104+executor*64,rid[63:32]);
 write(16'h1108+executor*64,1+epoch_delta);write(16'h110c+executor*64,generation);write(16'h1110+executor*64,allow_value);
 for(i=0;i<8;i=i+1)write(16'h1114+executor*64+i*4,digest+i);
 write(16'h1040,1<<executor);
end endtask
task finish_request;begin
 while(dut.state!=3)@(negedge clk);
 write(16'h1044,1);repeat(100)@(negedge clk);
end endtask
initial begin
 for(k=0;k<72;k=k+1)frame[k]=0;
 for(k=0;k<7;k=k+1)frame[k]=8'h55;frame[7]=8'hd5;
 crc=32'hffffffff;for(k=8;k<68;k=k+1)crc=crcbyte(crc,frame[k]);crc=~crc;
 for(k=0;k<4;k=k+1)frame[68+k]=crc>>(k*8);
 repeat(4)@(negedge clk);rst=0;
 cases=cases+1;send_frame;repeat(8)@(negedge clk);if(emitted!=0)fail("released before quorum");
 vote(0,1,0,32'h1234);vote(1,1,0,32'h1234);finish_request;
 if(forwarded!=1||emitted!=72)fail("healthy quorum not forwarded exactly once");
 cases=cases+1;send_frame;vote(0,1,0,32'h4321);vote(1,1,-1,32'h4321);finish_request;
 if(forwarded!=1||timeouts!=1||stale==0||emitted!=72)fail("stale epoch supplied quorum");
 cases=cases+1;ai_block=1;send_frame;vote(0,1,0,32'h5678);vote(1,1,0,32'h5678);finish_request;ai_block=0;
 if(ai_denied!=1||forwarded!=1||emitted!=72)fail("AI block did not control frame release");
 cases=cases+1;send_frame;vote(0,0,0,32'h8765);vote(1,0,0,32'h8765);finish_request;
 if(forwarded!=1||blocked!=3||emitted!=72)fail("semantic denial overridden");
 cases=cases+1;send_frame;finish_request;
 if(timeouts!=2||emitted!=72)fail("missing host result failed open");
 cases=cases+1;send_frame;vote(0,1,0,32'h1111);vote(1,1,0,32'h2222);finish_request;
 if(timeouts!=3||emitted!=72)fail("different semantic digests counted as quorum");
 cases=cases+1;send_frame;vote(0,1,0,32'h3333);vote(1,1,0,32'h3333);
 while(dut.state!=3)@(negedge clk);
 write(16'h1048,4'hb);
 @(negedge clk);ca=16'h1044;wd=1;cv=1;cw=1;#1;if(!ce)fail("active set changed without new generation");
 @(negedge clk);cv=0;cw=0;
 write(16'h104c,generation+1);write(16'h1044,1);repeat(100)@(negedge clk);
 if(dut.active_mask!=4'hb||dut.generation!=generation+1)fail("frame-boundary replacement failed");
 if(overflows!=0)fail("unexpected queue overflow");
 $display("DEFENSE_BOUNDARY_CASES=%0d emitted=%0d",cases,emitted);
 if(errors==0)$display("TB_DEFENSE_BOUNDARY_PASS");$finish;
end
initial begin #200000;fail("watchdog");$finish;end
endmodule
