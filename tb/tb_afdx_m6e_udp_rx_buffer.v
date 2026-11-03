`timescale 1ns/1ps
module tb_afdx_m6e_udp_rx_buffer;
localparam integer MAX=96;
reg clk=0, rst=1, busy=0, meta_valid=0, payload_valid=0, payload_sof=0, payload_eof=0, frame_done=0, frame_valid=0;
reg [31:0] src_ip=0; reg [15:0] sport=0, dport=0; reg [10:0] plen=0; reg [7:0] pdata=0;
wire ready, commit; wire [MAX*8-1:0] msg; wire [10:0] msg_len; wire [31:0] out_ip; wire [15:0] out_port;
integer fails=0, commits=0, cases=0, k, c0, last_commit;
reg [7:0] exp [0:MAX-1]; reg [MAX*8-1:0] old_msg; reg [10:0] old_len; reg [31:0] old_ip; reg [15:0] old_port;

afdx_m6e_udp_rx_buffer #(.MAX_SNMP_BYTES(MAX)) dut(
 .clk(clk),.rst(rst),.m6e_busy(busy),.meta_valid(meta_valid),.src_ip(src_ip),.udp_src_port(sport),.udp_dst_port(dport),.payload_length(plen),
 .payload_data(pdata),.payload_valid(payload_valid),.payload_ready(ready),.payload_sof(payload_sof),.payload_eof(payload_eof),.frame_done(frame_done),.frame_valid(frame_valid),
 .rx_commit(commit),.active_msg_bytes(msg),.active_msg_length(msg_len),.active_requester_ip(out_ip),.active_requester_port(out_port));
always #5 clk=~clk;
always @(posedge clk) if(commit) commits=commits+1;
task tick; begin @(negedge clk); end endtask

task send_frame;
 input integer n; input integer port; input integer valid; input integer sof_ok; input integer eof_ok; input integer done_same; input integer bval; input integer ipval; input integer mutate;
 integer i;
 begin
   cases=cases+1; dport=port; sport=16'h1234; src_ip=ipval; plen=n; frame_valid=valid; busy=bval; meta_valid=1; tick; meta_valid=0;
   for(i=0;i<n;i=i+1) begin pdata=8'h40+i; payload_valid=1; payload_sof=(i==0)&&sof_ok; payload_eof=(i==n-1)&&eof_ok; if(mutate && i==n/2) begin src_ip=32'hdeadbeef; sport=16'h9999; plen=n+1; end
     if(done_same && i==n-1) frame_done=1; tick; payload_valid=0; payload_sof=0; payload_eof=0; frame_done=0; end
   if(!done_same) begin frame_done=1; tick; frame_done=0; end
   payload_valid=0; frame_valid=0; busy=0;
 end
endtask

task expect_commit;
 input integer n; input [31:0] ip; input [15:0] port; integer i;
 begin
  if(!commit) begin $display("FAIL no commit case %0d",cases); fails=fails+1; end
  if(msg_len!==n || out_ip!==ip || out_port!==port) begin $display("FAIL metadata case %0d",cases); fails=fails+1; end
  for(i=0;i<n;i=i+1) if(msg[i*8 +: 8] !== (8'h40+i)) begin $display("FAIL byte %0d case %0d",i,cases); fails=fails+1; end
  tick; if(commit) begin $display("FAIL commit wider than pulse"); fails=fails+1; end
 end
endtask

task expect_no_change;
 begin
  if(commit) begin $display("FAIL unexpected commit case %0d",cases); fails=fails+1; end
  if(msg!==old_msg || msg_len!==old_len || out_ip!==old_ip || out_port!==old_port) begin $display("FAIL active changed case %0d",cases); fails=fails+1; end
  tick; if(commit) begin $display("FAIL quiet repeat"); fails=fails+1; end
 end
endtask

initial begin
 repeat(2) tick; rst=0; tick;
 send_frame(4,161,1,1,1,0,0,32'h01020304,0); expect_commit(4,32'h01020304,16'h1234);
 old_msg=msg; old_len=msg_len; old_ip=out_ip; old_port=out_port;
 send_frame(1,161,1,1,1,1,0,32'h11111111,0); expect_commit(1,32'h11111111,16'h1234);
 send_frame(96,161,1,1,1,1,0,32'h22222222,0); expect_commit(96,32'h22222222,16'h1234);
 old_msg=msg; old_len=msg_len; old_ip=out_ip; old_port=out_port;
 send_frame(3,160,1,1,1,1,0,32'h33333333,0); expect_no_change;
 send_frame(3,161,0,1,1,1,0,32'h44444444,0); expect_no_change;
 send_frame(97,161,1,1,1,1,0,32'h55555555,0); expect_no_change;
 old_msg=msg; old_len=msg_len; old_ip=out_ip; old_port=out_port;
 busy=1; send_frame(3,161,1,1,1,1,1,32'h66666666,0); expect_no_change;
 send_frame(3,161,1,1,1,1,0,32'h77777777,0); expect_commit(3,32'h77777777,16'h1234);
 send_frame(3,161,1,1,1,1,0,32'h88888888,1); expect_commit(3,32'h88888888,16'h1234);
 old_msg=msg; old_len=msg_len; old_ip=out_ip; old_port=out_port;
 send_frame(3,161,1,0,1,1,0,32'h99999999,0); expect_no_change;
 old_msg=msg; old_len=msg_len; old_ip=out_ip; old_port=out_port;
 send_frame(3,161,1,1,0,1,0,32'haaaaaaaa,0); expect_no_change;
 old_msg=msg; old_len=msg_len; old_ip=out_ip; old_port=out_port;
 send_frame(3,161,1,1,1,1,0,32'hbbbbbbbb,0); expect_commit(3,32'hbbbbbbbb,16'h1234);
 send_frame(4,161,1,1,1,1,0,32'hcccccccc,0); expect_commit(4,32'hcccccccc,16'h1234);
 send_frame(4,161,1,1,1,1,0,32'hdddddddd,0); expect_commit(4,32'hdddddddd,16'h1234);
 $display("M6E_CASES=%0d COMMITS=%0d FAILS=%0d",cases,commits,fails);
 if(fails!=0) $display("M6E_TB_FAIL"); else $display("M6E_TB_PASS");
 #20 $finish;
end
endmodule
