`timescale 1ns/1ps
module tb_m6e_01d_mechanics;
 reg clk=0,rst=1;
 always #4 clk=~clk;
 reg meta_valid=0,payload_valid=0,payload_sof=0,payload_eof=0,frame_done=0,frame_valid=0;
 reg [31:0] src_ip=0;
 reg [15:0] udp_src_port=0,udp_dst_port=161;
 reg [10:0] payload_length=3;
 reg [7:0] payload_data=0;
 wire payload_ready,busy,rx_commit,response_done,response_valid,response_error;
 wire [7:0] response_error_code,gmii_txd,sequence_num;
 wire builder_start,builder_done,gmii_tx_en,gmii_tx_er,tx_frame_done,underrun;
 afdx_m6e_integration #(.BAG_CYCLES(600)) dut (
 .clk(clk),.rst(rst),.meta_valid(meta_valid),.src_ip(src_ip),.udp_src_port(udp_src_port),.udp_dst_port(udp_dst_port),
 .payload_length(payload_length),.payload_data(payload_data),.payload_valid(payload_valid),.payload_sof(payload_sof),.payload_eof(payload_eof),
 .payload_ready(payload_ready),.frame_done(frame_done),.frame_valid(frame_valid),
 .cfg_src_mac(48'h020000000001),.cfg_dst_mac(48'h020000000002),.cfg_src_ip(32'hc0a80101),
 .busy(busy),.rx_commit(rx_commit),.response_done(response_done),.response_valid(response_valid),.response_error(response_error),
 .response_error_code(response_error_code),.builder_start(builder_start),.builder_done(builder_done),
 .gmii_txd(gmii_txd),.gmii_tx_en(gmii_tx_en),.gmii_tx_er(gmii_tx_er),.tx_frame_done(tx_frame_done),.underrun(underrun),.sequence_num(sequence_num),
 .m5_network_a_enable(1'b0),.m5_network_b_enable(1'b0),.m5_degraded_mode(1'b0),.m5_redundancy_ok(1'b0),
 .m5_frame_count_match(1'b0),.m5_active_byte_count_match(1'b0),.m5_fault_applied_event(1'b0),
 .m5_rx_accepted_count(32'b0),.m5_rx_accepted_a_count(32'b0),.m5_rx_accepted_b_count(32'b0),
 .m5_rx_duplicate_count(32'b0),.m5_rx_cross_network_duplicate_count(32'b0),.m5_rx_same_network_repeat_count(32'b0),
 .m5_rx_stale_count(32'b0),.m5_rx_sequence_gap_count(32'b0),.m5_tx_a_frame_count(32'b0),.m5_tx_b_frame_count(32'b0),
 .m5_tx_a_active_byte_count(32'b0),.m5_tx_b_active_byte_count(32'b0),.m5_tx_byte_mismatch_count(32'b0),
 .m5_tx_frame_skew_cycle_count(32'b0),.m5_tx_frame_done_skew_count(32'b0),.m5_tx_er_mismatch_count(32'b0),
 .m5_tx_a_error_cycle_count(32'b0),.m5_tx_b_error_cycle_count(32'b0),.m5_tx_a_underrun_count(32'b0),.m5_tx_b_underrun_count(32'b0));
 integer errors=0,physical=0,accepted=0,reqs=0,valids=0,rejects=0,starts=0,completed=0,releases=0;
 integer cycle=0,last_start=-600,pending_wait=0,build_gap=0,drops=0,idx=0,idle_cycles=100,expected_len=0;
 integer group_errors,base_a,base_r,base_s,base_c,base_d,base_wait,g;
 integer perturb_cycles=0,expected_transactions,expected_frames;
 reg prev_req=0,prev_start=0,prev_done=0,in_tx=0,owned=0,captured=0,body_finished=0;
 reg [767:0] message_q,response_q;
 reg [10:0] msg_len_q;
 reg [31:0] ip_q;
 reg [15:0] port_q;
 reg [7:0] len_q,old_seq;
 reg [7:0] expected[0:159];
 reg release_now,tx_release;
 task fail;
 input [511:0] why;
 begin errors=errors+1; $display("M6E_01D_ERROR t=%0t %0s",$time,why); end
 endtask
 // 每个字节均从刺激独立生成，含padding、sequence和逐位Ethernet CRC。
 task make_expected;
 input integer n,seed,seq;
 input [31:0] ip;
 input [15:0] port;
 integer k,j,body,sum;
 reg [31:0] crc;
 begin
 body=43+n; if(body<60) body=60; expected_len=body+12;
 for(k=0;k<160;k=k+1) expected[k]=0;
 for(k=0;k<7;k=k+1) expected[k]=8'h55;
 expected[7]=8'hd5; expected[8]=2; expected[13]=2; expected[14]=2; expected[19]=1; expected[20]=8'h08;
 expected[22]=8'h45; expected[25]=28+n; expected[30]=8'h40; expected[31]=8'h11;
 expected[34]=192; expected[35]=168; expected[36]=1; expected[37]=1;
 for(k=0;k<4;k=k+1) expected[38+k]=ip[31-k*8 -: 8];
 expected[43]=161; expected[44]=port[15:8]; expected[45]=port[7:0]; expected[47]=8+n;
 sum=0; for(k=22;k<42;k=k+2) sum=sum+{expected[k],expected[k+1]};
 sum=(sum&65535)+(sum>>16); sum=(sum&65535)+(sum>>16); {expected[32],expected[33]}=~sum;
 for(k=0;k<n;k=k+1) expected[50+k]=seed+k;
 expected[8+body-1]=seq;
 crc=32'hffffffff;
 for(k=8;k<8+body;k=k+1) for(j=0;j<8;j=j+1)
 if(crc[0]^expected[k][j]) crc=(crc>>1)^32'hedb88320; else crc=crc>>1;
 crc=~crc; for(k=0;k<4;k=k+1) expected[8+body+k]=crc[k*8 +: 8];
 end
 endtask
 task datagram;
 input integer n,delay_cycles,seed,bytes;
 input [31:0] ip;
 input [15:0] port,dst;
 input good;
 integer k;
 begin
 physical=physical+1; meta_valid=1; src_ip=ip; udp_src_port=port; udp_dst_port=dst; payload_length=bytes;
 @(negedge clk); meta_valid=0;
 for(k=0;k<bytes;k=k+1) begin
 payload_valid=1; payload_sof=(k==0); payload_eof=(k==bytes-1);
 case(k) 0:payload_data=n; 1:payload_data=delay_cycles; default:payload_data=seed; endcase
 @(negedge clk);
 end
 payload_valid=0; payload_sof=0; payload_eof=0; frame_done=1; frame_valid=good;
 @(negedge clk); frame_done=0; frame_valid=0;
 end
 endtask
 task success;
 input integer n,seed;
 input [31:0] ip;
 input [15:0] port;
 integer target;
 begin
 target=completed+1; make_expected(n,seed,completed,ip,port);
 datagram(n,4,seed,3,ip,port,161,1);
 wait(completed==target); repeat(3) @(negedge clk);
 end
 endtask
 task group_begin;
 input integer number;
 begin
 g=number; group_errors=errors; base_a=accepted; base_r=reqs; base_s=starts; base_c=completed; base_d=drops; base_wait=pending_wait;
 end
 endtask
 task group_end;
 begin
 expected_transactions=1; if(g==6) expected_transactions=4; if(g==8) expected_transactions=2;
 expected_frames=expected_transactions; if(g==2) expected_frames=0;
 if(accepted-base_a!=expected_transactions || reqs-base_r!=expected_transactions || starts-base_s!=expected_frames || completed-base_c!=expected_frames)
 fail("分组计数不匹配");
 $display("01D-0%0d %0s accepted=%0d req=%0d started=%0d completed=%0d busy_drops=%0d bag_wait_cycles=%0d",g,
 (errors==group_errors)?"PASS":"FAIL",accepted-base_a,reqs-base_r,starts-base_s,completed-base_c,drops-base_d,pending_wait-base_wait);
 end
 endtask
 // 握手在采样沿检查；注册GMII在NBA之后检查。
 always @(posedge clk) if(!rst) begin
 cycle=cycle+1; old_seq=sequence_num;
 tx_release=tx_frame_done;
 release_now=tx_frame_done || (response_done && !response_valid);
 if(dut.m6d_req && prev_req) fail("req非单拍");
 if(builder_start && prev_start) fail("start非单拍");
 prev_req=dut.m6d_req; prev_start=builder_start;
 if(rx_commit) begin
 if(owned || !busy) fail("ownership/commit窗口错误");
 owned=1; accepted=accepted+1; message_q=dut.active_msg_bytes; msg_len_q=dut.active_msg_length;
 ip_q=dut.active_requester_ip; port_q=dut.active_requester_port;
 end
 if(dut.m6d_req) begin reqs=reqs+1; if(rx_commit || dut.state!=1) fail("req直接来自commit或状态错误"); end
 if(response_done) begin
 if(response_valid) begin valids=valids+1; captured=1; end
 else rejects=rejects+1;
 end
 if(dut.state==3 && !builder_start) begin
 pending_wait=pending_wait+1;
 if(dut.u_bag.bag_counter==0) fail("伪BAG等待");
 end
 if(builder_start) begin
 if(cycle-last_start<600) fail("BAG发送间隔不足");
 last_start=cycle; starts=starts+1;
 if(!captured || dut.state!=3) fail("无response启动TX");
 end
 if(builder_done) begin body_finished=1; if(!busy || tx_frame_done) fail("builder done提前释放"); end
 if(body_finished && !tx_frame_done) build_gap=build_gap+1;
 if(release_now) begin
 if(!owned) fail("重复释放");
 owned=0; captured=0; body_finished=0; releases=releases+1;
 end
 #1;
 // sequence仅在刚才采样到frame_done的沿推进。
 if(tx_release) begin
 if(sequence_num!==(old_seq==255?8'd1:old_seq+8'd1)) fail("frame完成未恰好推进sequence");
 end else if(sequence_num!==old_seq) fail("sequence额外推进");
 if(release_now && busy) fail("释放后busy未撤销");
 if(owned) begin
 if(!busy) fail("ownership提前释放");
 if(dut.active_msg_bytes!==message_q || dut.active_msg_length!==msg_len_q || dut.active_requester_ip!==ip_q || dut.active_requester_port!==port_q)
 fail("活动请求逐拍稳定性失败");
 if(dut.requester_ip_q!==ip_q || dut.requester_port_q!==port_q) fail("requester锁存不稳定");
 end
 if(underrun || gmii_tx_er) begin fail("正常路径underrun/tx_er fatal"); $finish; end
 if(!payload_ready) fail("RX未完整drain");
 if(tx_frame_done && prev_done) fail("frame_done非单拍"); prev_done=tx_frame_done;
 if(gmii_tx_en) begin
 if(!in_tx) begin if(idle_cycles<12) fail("IFG不足"); in_tx=1; idx=0; end
 idle_cycles=0;
 if(idx>=expected_len || gmii_txd!==expected[idx]) begin
 $display("BYTE frame=%0d index=%0d got=%02x expected=%02x",completed,idx,gmii_txd,expected[idx]); fail("独立GMII scoreboard失败"); end
 if(tx_frame_done!==(idx==expected_len-1)) fail("done不在最后FCS");
 if(!busy) fail("GMII期间无ownership"); idx=idx+1;
 end else begin
 idle_cycles=idle_cycles+1;
 if(tx_frame_done) fail("done无tx_en");
 if(in_tx) begin if(idx!=expected_len) fail("tx_en不连续/帧长错误"); in_tx=0; end
 end
 if(tx_frame_done) begin completed=completed+1; $display("MECHANICS_GMII_DONE frame=%0d bytes=%0d",completed,idx); end
 end
 // 独立capture稳定性监视器，避开主计数监视器中的阻塞赋值次序。
 reg capture_hold=0;
 always @(posedge clk) if(!rst) begin
 if(tx_frame_done) capture_hold=0;
 if(response_done && response_valid) begin
 #1; response_q=dut.response_q; len_q=dut.length_q; capture_hold=1;
 end else begin
 #1; if(capture_hold) begin
 if(dut.response_q!==response_q || dut.length_q!==len_q) fail("capture后response被覆盖");
 if(dut.response_length!=len_q) perturb_cycles=perturb_cycles+1;
 end
 end
 end
 initial begin
 repeat(5) @(negedge clk); rst=0; repeat(3) @(negedge clk);
 group_begin(1); success(18,32,32'h0a000001,40001); group_end;
 group_begin(2);
 datagram(0,4,0,3,32'h0a000002,40002,161,1); wait(rejects==1); repeat(3) @(negedge clk);
 if(starts!=base_s || completed!=base_c || busy || sequence_num!=completed) fail("拒绝误发TX");
 // invalid、非161和oversize均不能增加req或sequence。
 datagram(18,4,0,3,32'h0a000002,40002,162,1);
 datagram(18,4,0,3,32'h0a000002,40002,161,0);
 datagram(18,4,0,97,32'h0a000002,40002,161,1);
 repeat(3) @(negedge clk);
 if(accepted!=base_a+1 || reqs!=base_r+1 || starts!=base_s || sequence_num!=completed) fail("invalid/drop额外请求");
 group_end;
 group_begin(3); make_expected(17,48,completed,32'h0a000003,40003);
 datagram(17,80,48,3,32'h0a000003,40003,161,1);
 wait(dut.state==2); @(negedge clk);
 datagram(96,4,99,3,32'hdeadbeef,49999,161,1); drops=drops+1;
 wait(completed==base_c+1); repeat(3) @(negedge clk);
 if(reqs!=base_r+1 || accepted!=base_a+1) fail("M6D_WAIT busy drop失败"); group_end;
 group_begin(4); make_expected(18,64,completed,32'h0a000004,40004);
 datagram(18,4,64,3,32'h0a000004,40004,161,1);
 wait(dut.state==3 && !builder_start); @(negedge clk);
 datagram(96,4,99,3,32'hdeadbeef,49999,161,1); drops=drops+1;
 if(dut.state!=3 || builder_start) fail("未在实际BAG等待期间完整drain");
 wait(completed==base_c+1); repeat(3) @(negedge clk);
 if(reqs!=base_r+1 || accepted!=base_a+1 || pending_wait==base_wait) fail("TX_PENDING drop失败"); group_end;
 group_begin(5); make_expected(96,80,completed,32'h0a000005,40005);
 datagram(96,4,80,3,32'h0a000005,40005,161,1);
 wait(dut.state==4); @(negedge clk);
 datagram(1,4,99,3,32'hdeadbeef,49999,161,1); drops=drops+1;
 wait(completed==base_c+1); repeat(3) @(negedge clk);
 if(reqs!=base_r+1 || accepted!=base_a+1) fail("TX_WAIT drop失败"); group_end;
 group_begin(6);
 success(1,96,32'h0a000006,40006); success(17,112,32'h0a000007,40007);
 success(18,128,32'h0a000008,40008); success(96,144,32'h0a000009,40009); group_end;
 group_begin(7); success(18,160,32'hc1234567,16'hcdef); group_end;
 group_begin(8); success(17,176,32'h0a010203,41000); success(18,192,32'h0a020304,42000);
 repeat(650) @(negedge clk); group_end;
 if(accepted!=reqs || valids!=starts || starts!=completed || accepted!=releases || sequence_num!=completed || busy || drops!=3 || build_gap!=4*completed || perturb_cycles==0)
 fail("最终invariant失败");
 $display("COUNTS physical=%0d accepted=%0d req=%0d valid_responses=%0d TX_started=%0d completed=%0d rejects=%0d releases=%0d busy_drops=%0d BAG_wait=%0d builder_FCS_hold=%0d sequence=%0d",physical,accepted,reqs,valids,starts,completed,rejects,releases,drops,pending_wait,build_gap,sequence_num);
 $display("CAPTURE_OUTPUT_PERTURB_CYCLES=%0d",perturb_cycles);
 $display("M6E_01D_FAILS=%0d",errors);
 if(errors==0) $display("M6E_01D_TB_PASS"); else $display("M6E_01D_TB_FAIL");
 $finish;
 end
 initial begin #490000; $display("M6E_01D_TB_TIMEOUT"); $finish; end
endmodule
