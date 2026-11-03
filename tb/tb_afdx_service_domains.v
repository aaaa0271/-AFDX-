`timescale 1ns/1ps
module tb_afdx_service_domains;
 reg clk=0,rst=1,cfg_we=0,cfg_kind=0,cfg_commit=0,cfg_enable=0,select_valid=0,select_kind=0,tx_event=0;
 reg [2:0] cfg_domain=0,select_domain=0; reg [3:0] cfg_vl=0; reg [7:0] cfg_sequence_domain=0,cfg_retry=0; reg [47:0] cfg_mac=0; reg [31:0] cfg_ip=0,cfg_timeout=0; reg [15:0] cfg_udp=0,cfg_tid=0;
 wire cfg_ready,cfg_error,commit_pulse,selected_valid; wire [3:0] selected_vl; wire [7:0] selected_sequence_domain,selected_sequence,selected_retry; wire [47:0] selected_mac; wire [31:0] selected_ip,selected_timeout; wire [15:0] selected_udp,selected_tid;
 integer errors=0;
 always #5 clk=~clk;
 afdx_service_domain_table #(.DOMAINS(4)) dut(.*);
 task write_profile;
  input [2:0] d; input k; input [3:0] vl; input [7:0] sd; input [31:0] ip; input [15:0] udp,tid; input [47:0] mac; input [31:0] timeout; input [7:0] retry;
  begin
   @(negedge clk); cfg_domain=d;cfg_kind=k;cfg_vl=vl;cfg_sequence_domain=sd;cfg_ip=ip;cfg_udp=udp;cfg_tid=tid;cfg_mac=mac;cfg_timeout=timeout;cfg_retry=retry;cfg_enable=1;cfg_we=1;
   @(negedge clk); cfg_we=0;
  end
 endtask
 task select_check;
  input k;input [2:0] d;input [3:0] vl;input [7:0] sd;input [31:0] ip;input [15:0] udp,tid;
  begin
   @(negedge clk); select_valid=1;select_kind=k;select_domain=d;#1;
   if(!selected_valid||selected_vl!=vl||selected_sequence_domain!=sd||selected_ip!=ip||selected_udp!=udp||selected_tid!=tid) begin $display("SELFAIL k=%0d d=%0d valid=%0d vl=%0d/%0d sd=%0d/%0d ip=%h/%h udp=%0d/%0d tid=%0d/%0d",k,d,selected_valid,selected_vl,vl,selected_sequence_domain,sd,selected_ip,ip,selected_udp,udp,selected_tid,tid); errors=errors+1; end
  end
 endtask
 initial begin
  repeat(3) @(negedge clk); rst=0;
  write_profile(0,0,4'd1,8'd11,32'h0a000101,16'd4000,16'd5100,48'h020000000101,32'd1000,8'd3);
  write_profile(1,0,4'd2,8'd12,32'h0a000102,16'd4001,16'd5101,48'h020000000102,32'd2000,8'd4);
  write_profile(0,1,4'd3,8'd21,32'h0a000201,16'd123,16'd6100,48'h020000000201,32'd3000,8'd5);
  write_profile(1,1,4'd4,8'd22,32'h0a000202,16'd124,16'd6101,48'h020000000202,32'd4000,8'd6);
  @(negedge clk); cfg_commit=1;
  @(negedge clk); cfg_commit=0; #1;
  if(!commit_pulse) begin $display("COMMITFAIL"); errors=errors+1; end
  select_check(0,0,1,11,32'h0a000101,4000,5100); tx_event=1;
  @(negedge clk); tx_event=0; #1;
  if(selected_sequence!=1) begin $display("SEQFAIL %0d",selected_sequence); errors=errors+1; end
  select_check(0,1,2,12,32'h0a000102,4001,5101);
  select_check(1,0,3,21,32'h0a000201,123,6100);
  select_check(1,1,4,22,32'h0a000202,124,6101);
  select_valid=0;
  write_profile(2,0,4'd5,8'd13,32'h0a000101,16'd4000,16'd5100,48'h020000000103,32'd5000,8'd7);
  #1;
  if(!cfg_error) begin $display("DUPFAIL"); errors=errors+1; end
  @(negedge clk); cfg_commit=1;
  @(negedge clk); cfg_commit=0; #1;
  if(cfg_error) begin $display("COMMITERR"); errors=errors+1; end
  if(errors==0) $display("TB_SERVICE_DOMAIN_TABLE_PASS"); else $display("TB_SERVICE_DOMAIN_TABLE_FAIL errors=%0d",errors);
  $finish;
 end
endmodule
