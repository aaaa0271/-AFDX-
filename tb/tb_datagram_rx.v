`timescale 1ns/1ps
module tb_datagram_rx;
reg clk=0;always #40 clk=~clk;reg rst=1,ready=1;reg [7:0] a=0,b=0;reg av=0,bv=0;reg [671:0] cfg=0;
wire [7:0] data;wire valid,sof,eof,net;wire [15:0] length;wire [1:0] port;
wire [31:0] accepted,duplicate,stale,messages,dropped,overflows,reassembly_errors,timeouts;
integer errors=0,case_id=0,delivered=0,expect_count=0,byte_index=0,i,t;
integer exp_len[0:15],exp_seed[0:15],exp_port[0:15];reg [7:0] vector_mem[0:300000];
reg stalled=0;reg [7:0] held_data;reg held_sof,held_eof;reg [15:0] held_length;reg [1:0] held_port;
afdx_datagram_rx #(.REASSEMBLY_TIMEOUT(20000)) dut(.clk(clk),.rst(rst),.network_cfg(cfg),.a_data(a),.b_data(b),.a_valid(av),.b_valid(bv),.a_error(1'b0),.b_error(1'b0),
.payload_data(data),.payload_valid(valid),.payload_sof(sof),.payload_eof(eof),.payload_network(net),.payload_ready(ready),.read_request(1'b0),.read_port(2'd0),.read_ready(),.payload_fresh(),.payload_length(length),.payload_vl(port),
.accepted_a_frames(),.accepted_b_frames(),.cross_duplicates(),.same_repeats(),.sequence_gaps(),.accepted_frames(accepted),.duplicate_frames(duplicate),.stale_frames(stale),.messages(messages),.dropped(dropped),.overflows(overflows),.reassembly_errors(reassembly_errors),.timeouts(timeouts));
task fail;input [511:0] why;begin errors=errors+1;$display("FAIL DATAGRAM_RX case=%0d %0s",case_id,why);end endtask
task new_case;input integer id;begin @(negedge clk);rst=1;av=0;bv=0;ready=1;repeat(5)@(negedge clk);case_id=id;delivered=0;expect_count=0;byte_index=0;stalled=0;rst=0;repeat(5)@(negedge clk);end endtask
task expected;input integer n,seed,vl;begin exp_len[expect_count]=n;exp_seed[expect_count]=seed;exp_port[expect_count]=vl;expect_count=expect_count+1;end endtask
task send_frame;input integer offset,n,mask,bad_a;integer j;begin
 for(j=0;j<n;j=j+1)begin @(negedge clk);a=vector_mem[offset+j]^((bad_a&&j==55)?8'h01:8'h00);b=vector_mem[offset+j];av=mask&1;bv=(mask>>1)&1;end
 @(negedge clk);av=0;bv=0;repeat(12)@(negedge clk);
end endtask
task finish_case;input integer wanted;begin
 t=0;while(delivered<wanted&&t<100000)begin @(negedge clk);t=t+1;end
 repeat(3000)@(negedge clk);
 if(delivered!=wanted||messages!=wanted)begin $display("RX_DEBUG accepted=%0d duplicate=%0d stale=%0d dropped=%0d overflows=%0d errors=%0d timeouts=%0d messages=%0d delivered=%0d state=%0d",accepted,duplicate,stale,dropped,overflows,reassembly_errors,timeouts,messages,delivered,dut.state);fail("message count/timeout");end
 $display("DATAGRAM_RX_CASE=%0d DELIVERED=%0d REJECTS=%0d OVERFLOWS=%0d REASSEMBLY_REJECTIONS=%0d TIMEOUTS=%0d ERRORS=%0d",case_id,delivered,dropped,overflows,reassembly_errors,timeouts,errors);
end endtask
always @(posedge clk)if(!rst)begin
 if(stalled&&(!valid||data!==held_data||sof!==held_sof||eof!==held_eof||length!==held_length||port!==held_port))fail("output changed under backpressure");
 stalled=valid&&!ready;if(stalled)begin held_data=data;held_sof=sof;held_eof=eof;held_length=length;held_port=port;end
 if(valid&&ready)begin
  if(delivered>=expect_count)fail("unexpected/partial message");
  else begin
   if(sof)byte_index=0;
   if(data!==((exp_seed[delivered]+byte_index*7)&255)||length!==exp_len[delivered]||port!==exp_port[delivered])fail("independent payload/port/length");
   if(sof!==(byte_index==0)||eof!==(byte_index==exp_len[delivered]-1))fail("message boundary");
   byte_index=byte_index+1;
   if(eof)delivered=delivered+1;
  end
 end
end
reg [47:0] mac;reg [31:0] ip;reg [15:0] dp;
initial begin
 for(i=0;i<4;i=i+1)begin mac=48'h030000000002+i;ip=32'h0a000002+i;dp=i==0?10001:i==1?20001:20002+i;cfg[i*168+:168]={16'd1518,dp,16'd10000,ip,32'h0a000001,mac,8'h03};end
 $readmemh("rx_frames.hex",vector_mem);
 `include "rx_cases.vh"
 if(errors==0)$display("TB_DATAGRAM_RX_PASS");else $display("TB_DATAGRAM_RX_FAIL");$finish;
end
initial begin #200000000;$display("DATAGRAM_RX_TIMEOUT");$finish;end
endmodule