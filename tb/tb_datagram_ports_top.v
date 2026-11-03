`timescale 1ns/1ps
module tb_datagram_ports_top;
reg clk=0;always #40 clk=~clk;reg rst=1,ready=1,read_request=0;reg [1:0] read_port=0;
reg [7:0] rx=0;reg dv=0;reg [671:0] cfg=0;wire read_ready;
wire [7:0] data;wire valid,sof,eof,net,fresh;wire [15:0] length;wire [1:0] port;
wire [31:0] messages,dropped;
reg input_en=0;reg [1:0] input_port=0;wire input_ready,input_accept,input_error;
reg cfg_write=0,cfg_seal=0,cfg_we=0;reg [1:0] cfg_index=0;reg [31:0] cfg_bag=12500;wire cfg_ready,cfg_error;
assign messages=dut.u_core.rx.messages;assign dropped=dut.u_core.rx.dropped;
integer errors=0,delivered=0,byte_index=0,expect_n=0,expect_seed=0,expect_port=0,expect_fresh=0,i,t;
reg [7:0] vector_mem[0:5000];reg [7:0] hold_data;reg hold_valid=0;reg hold_sof,hold_eof,hold_fresh;
AFDX_competition_top #(.SAMPLING_MASK(4'b0001),.EXPLICIT_PORT_READ(1),.FRESHNESS_CYCLES(4000)) dut(
.clk(clk),.rst(rst),.cfg_rx_write(cfg_write),.cfg_rx_seal(cfg_seal),.cfg_rx_index(cfg_index),.cfg_rx_entry(cfg[cfg_index*168+:168]),.cfg_rx_ready(cfg_ready),.cfg_rx_error(cfg_error),
.tx_enable(1'b1),.network_a_enable(1'b1),.network_b_enable(1'b1),.cfg_we(cfg_we),.cfg_vl_id(cfg_index),.cfg_bag(cfg_bag),.cfg_destination(8'd2),.cfg_lmax(16'd1518),
.app_wr_en(input_en),.app_wr_vl_id(input_port),.app_wr_data(8'd5),.app_wr_len(16'd1),.app_wr_sof(1'b1),.app_wr_eof(1'b1),.app_wr_ready(input_ready),.app_wr_accept(input_accept),.app_len_error(input_error),.fault_enable(1'b0),
.data_a_rxd(rx),.data_b_rxd(rx),.data_a_rx_dv(dv),.data_b_rx_dv(dv),.data_a_rx_er(1'b0),.data_b_rx_er(1'b0),.data_a_txd(),.data_b_txd(),.data_a_tx_en(),.data_b_tx_en(),.data_a_tx_er(),.data_b_tx_er(),.data_a_done(),.data_b_done(),
.payload_data(data),.payload_valid(valid),.payload_sof(sof),.payload_eof(eof),.payload_network(net),.payload_ready(ready),.payload_length(length),.payload_vl(port),.payload_fresh(fresh),.app_read_request(read_request),.app_read_port(read_port),.app_read_ready(read_ready),
.management_busy(),.snmp_snapshots(),.snmp_busy_drops(),.shared_rx_accepted(),.shared_rx_duplicates(),.shared_rx_dropped(),.shared_tx_overflows(),.physical_a_frames(),.physical_b_frames(),
.loader_ip(32'h0a000001),.time_server_ip(32'h0a000001),.hardware_length(6'd3),.hardware_id({232'd0,24'h4d4953}),.app_file(2'd0),.rtc_poll(1'b0),.rtc_locked(),.utc_ntp(),.monotonic_ticks(),.image_valid(),.image_length(),.image_crc(),.package_generation(),.package_file_count(),.image_read_address(16'd0),.image_read_data(),.loading(),.load_complete(),.load_failed());

task fail;input [511:0] why;begin errors=errors+1;$display("FAIL PORTS %0s",why);end endtask
task send_frame;input integer offset,n;integer k;begin
 for(k=0;k<n;k=k+1)begin @(negedge clk);rx=vector_mem[offset+k];dv=1;end
 @(negedge clk);dv=0;repeat(12)@(negedge clk);
end endtask
`include "port_vectors.vh"
task request_read;input integer n,seed,vl,is_fresh;begin
 expect_n=n;expect_seed=seed;expect_port=vl;expect_fresh=is_fresh;
 @(negedge clk);read_port=vl;#1;t=0;while(!read_ready&&t<4000)begin @(negedge clk);#1;t=t+1;end
 if(!read_ready)fail("read command never ready");read_request=1;
 @(negedge clk);read_request=0;
end endtask
task drain;input integer count;begin
 t=0;while(delivered<count&&t<10000)begin @(negedge clk);t=t+1;end
 if(delivered!=count)fail("application read timeout");repeat(10)@(negedge clk);
end endtask
always @(posedge clk)if(!rst)begin
 if(hold_valid&&(!valid||data!==hold_data||sof!==hold_sof||eof!==hold_eof||fresh!==hold_fresh))fail("sample changed while reader stalled");
 hold_valid=valid&&!ready;if(hold_valid)begin hold_data=data;hold_sof=sof;hold_eof=eof;hold_fresh=fresh;end
 if(valid&&ready)begin
  if(sof)byte_index=0;
  if(data!==((expect_seed+byte_index*7)&255)||length!==expect_n||port!==expect_port||fresh!==expect_fresh)fail("sampling/FIFO data freshness or port");
  if(sof!==(byte_index==0)||eof!==(byte_index==expect_n-1))fail("read boundaries");
  byte_index=byte_index+1;if(eof)delivered=delivered+1;
 end
end
reg [47:0] mac;reg [31:0] ip;reg [15:0] dp;
initial begin
 for(i=0;i<4;i=i+1)begin mac=48'h030000000002+i;ip=32'h0a000002+i;dp=i==0?10001:i==1?20001:20002+i;cfg[i*168+:168]={16'd1518,dp,16'd10000,ip,32'h0a000001,mac,8'h03};end
 $readmemh("port_frames.hex",vector_mem);
 repeat(5)@(negedge clk);rst=0;
 cfg_we=1;cfg_bag=37500;@(negedge clk);cfg_we=0;#1;if(!cfg_error)fail("non-power-of-two BAG accepted");@(negedge clk);
 cfg[3*168+:8]=0;
 cfg_bag=12500;
 for(i=0;i<4;i=i+1)begin cfg_index=i;cfg_write=1;cfg_we=1;@(negedge clk);cfg_write=0;cfg_we=0;@(negedge clk);end
 input_port=0;input_en=1;repeat(3)begin @(negedge clk);if(input_ready||input_accept)fail("application accepted before configuration seal");end
 input_en=0;if(dut.u_core.tx.messages!=0)fail("pre-seal message queued");
 cfg_seal=1;@(negedge clk);cfg_seal=0;#1;if(!cfg_ready||cfg_error)fail("configuration seal");
 input_port=3;input_en=1;@(negedge clk);#1;if(input_ready||input_accept||!input_error||dut.u_core.tx.messages!=0)fail("disabled VL accepted application message");input_en=0;
 cfg_we=1;@(negedge clk);cfg_we=0;#1;if(!cfg_error)fail("sealed TX configuration changed");
 repeat(3)@(negedge clk);if(read_ready||valid)fail("empty port advertised data");
 send_old;send_latest;repeat(500)@(negedge clk);if(valid||messages!=2)fail("sampling implicitly dequeued");
 request_read(18,20,0,1);drain(1);request_read(18,20,0,1);drain(2);
 repeat(4100)@(negedge clk);request_read(18,20,0,0);drain(3);
 send_held;repeat(500)@(negedge clk);ready=0;request_read(30,30,0,1);repeat(15)@(negedge clk);
 send_new1;send_new2;repeat(500)@(negedge clk);ready=1;drain(4);
 request_read(45,45,0,1);drain(5);
 send_bad;send_fragment;repeat(500)@(negedge clk);if(dropped<4)fail("invalid sampling updates not rejected");request_read(45,45,0,1);drain(6);
 send_queue1;send_queue2;repeat(500)@(negedge clk);request_read(12,80,1,1);drain(7);request_read(13,81,1,1);drain(8);
 repeat(3)@(negedge clk);if(read_ready)fail("queuing read did not consume FIFO");read_port=2;repeat(2)@(negedge clk);if(read_ready)fail("empty other port aliased");
 @(negedge clk);rst=1;repeat(5)@(negedge clk);rst=0;read_port=0;repeat(3)@(negedge clk);if(read_ready||valid)fail("reset retained sampling validity");
 $display("PORT_READS=%0d ERRORS=%0d",delivered,errors);if(errors==0)$display("TB_DATAGRAM_PORTS_TOP_PASS");else $display("TB_DATAGRAM_PORTS_TOP_FAIL");$finish;
end
initial begin #30000000;$display("DATAGRAM_PORTS_TOP_TIMEOUT");$finish;end
endmodule