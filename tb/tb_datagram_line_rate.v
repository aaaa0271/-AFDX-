`timescale 1ns/1ps
module tb_datagram_line_rate;
reg clk=0;always #40 clk=~clk;reg rst=1;reg [7:0] a=0,b=0;reg dv=0;reg [671:0] cfg=0;
wire [7:0] data;wire valid,sof,eof,net;wire [15:0] length;wire [1:0] port;
wire [31:0] accepted,duplicates,messages,dropped,overflows,rejections;
integer errors=0,case_id=0,delivered=0,byte_index=0,expected_length=0,cycles=0,wire_sent=0,ready_count=0,max_ready_delay=0;
integer wire_end[0:1300];integer i,k,t,delay;reg [7:0] raw[0:280000];
afdx_datagram_rx dut(.clk(clk),.rst(rst),.network_cfg(cfg),.a_data(a),.b_data(b),.a_valid(dv),.b_valid(dv),.a_error(1'b0),.b_error(1'b0),
.payload_data(data),.payload_valid(valid),.payload_sof(sof),.payload_eof(eof),.payload_network(net),.payload_ready(1'b1),.payload_length(length),.payload_vl(port),.payload_fresh(),.read_request(1'b0),.read_port(2'd0),.read_ready(),
.accepted_frames(accepted),.duplicate_frames(duplicates),.stale_frames(),.accepted_a_frames(),.accepted_b_frames(),.cross_duplicates(),.same_repeats(),.sequence_gaps(),.messages(messages),.dropped(dropped),.overflows(overflows),.reassembly_errors(rejections),.timeouts());
task fail;input [511:0] why;begin errors=errors+1;$display("FAIL LINE_RATE case=%0d %0s",case_id,why);end endtask
always @(posedge clk)if(!rst)begin
 cycles=cycles+1;
 if(dut.publish)begin
  delay=cycles-wire_end[ready_count];if(delay>max_ready_delay)max_ready_delay=delay;
  ready_count=ready_count+1;
 end
 if(valid)begin
  if(sof)byte_index=0;expected_length=case_id==0?(delivered%17)+1:1471;
  if(length!==expected_length||port!==(delivered%4)||data!==((delivered+11+byte_index*7)&255))fail("full-rate payload/port/order");
  if(sof!==(byte_index==0)||eof!==(byte_index==expected_length-1))fail("boundaries");
  byte_index=byte_index+1;if(eof)delivered=delivered+1;
 end
end
task run_case;input integer id,start,count,n;integer f,j;begin
 @(negedge clk);rst=1;dv=0;repeat(5)@(negedge clk);case_id=id;delivered=0;byte_index=0;cycles=0;wire_sent=0;ready_count=0;max_ready_delay=0;rst=0;
 for(f=0;f<count;f=f+1)begin
  for(j=0;j<n;j=j+1)begin @(negedge clk);a=raw[start+f*n*2+j];b=raw[start+f*n*2+n+j];dv=1;end
  @(negedge clk);dv=0;wire_end[wire_sent]=cycles;wire_sent=wire_sent+1;
  // Falling dv cycle plus11 more low cycles gives exactly12 idle byte clocks.
  repeat(11)@(negedge clk);
 end
 t=0;while(delivered<count&&t<200000)begin @(negedge clk);t=t+1;end
 repeat(200)@(negedge clk);
 if(delivered!=count||messages!=count||accepted!=count||duplicates!=count||overflows!=0||dropped!=0||rejections!=0||ready_count!=count)begin
  $display("RATE_DEBUG delivered=%0d messages=%0d accepted=%0d duplicates=%0d dropped=%0d overflow=%0d reject=%0d ready=%0d",delivered,messages,accepted,duplicates,dropped,overflows,rejections,ready_count);fail("line-rate counters");
 end
 if(max_ready_delay*80>=150000)fail("tested RX buffer-availability latency >=150us");
 $display("LINE_RATE_CASE=%0d FRAMES_PER_NETWORK=%0d FRAME_BYTES=%0d IFG_BYTES=12 BYTE_PERIOD_NS=80 MAX_BUFFER_READY_NS=%0d ERRORS=%0d",case_id,count,n,max_ready_delay*80,errors);
end endtask
reg [47:0] mac;reg [31:0] ip;reg [15:0] dp;
initial begin
 for(i=0;i<4;i=i+1)begin mac=48'h030000000002+i;ip=32'h0a000002+i;dp=i==0?10001:i==1?20001:20002+i;cfg[i*168+:168]={16'd1518,dp,16'd10000,ip,32'h0a000001,mac,8'h03};end
 $readmemh("line_rate.hex",raw);
 `include "line_rate_cases.vh"
 if(errors==0)$display("TB_DATAGRAM_LINE_RATE_PASS");else $display("TB_DATAGRAM_LINE_RATE_FAIL");$finish;
end
initial begin #100000000;$display("LINE_RATE_TIMEOUT");$finish;end
endmodule