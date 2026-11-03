`timescale 1ns / 1ps
module tb_afdx_m6e_integration;
    reg clk=0;
    always #4 clk=~clk;
    reg rst=1, meta_valid=0, payload_valid=0, payload_sof=0, payload_eof=0;
    reg frame_done=0, frame_valid=0;
    reg [31:0] src_ip=0;
    reg [15:0] udp_src_port=0, udp_dst_port=161;
    reg [10:0] payload_length=46;
    reg [7:0] payload_data=0;
    reg [47:0] cfg_src_mac=48'h020000000001, cfg_dst_mac=48'h020000000002;
    reg [31:0] cfg_src_ip=32'hc0a80101;
    wire payload_ready, busy, rx_commit, response_done, response_valid, response_error;
    wire [7:0] response_error_code, gmii_txd, sequence_num;
    wire builder_start, builder_done, gmii_tx_en, gmii_tx_er, tx_frame_done, underrun;
    afdx_m6e_integration #(.BAG_CYCLES(1200)) dut (
        .clk(clk), .rst(rst), .meta_valid(meta_valid), .src_ip(src_ip),
        .udp_src_port(udp_src_port), .udp_dst_port(udp_dst_port),
        .payload_length(payload_length), .payload_data(payload_data),
        .payload_valid(payload_valid), .payload_sof(payload_sof), .payload_eof(payload_eof),
        .payload_ready(payload_ready), .frame_done(frame_done), .frame_valid(frame_valid),
        .cfg_src_mac(cfg_src_mac), .cfg_dst_mac(cfg_dst_mac), .cfg_src_ip(cfg_src_ip),
        .busy(busy), .rx_commit(rx_commit), .response_done(response_done),
        .response_valid(response_valid), .response_error(response_error), .response_error_code(response_error_code),
        .builder_start(builder_start), .builder_done(builder_done), .gmii_txd(gmii_txd),
        .gmii_tx_en(gmii_tx_en), .gmii_tx_er(gmii_tx_er), .tx_frame_done(tx_frame_done),
        .underrun(underrun), .sequence_num(sequence_num),
        .m5_network_a_enable(1'b0), .m5_network_b_enable(1'b0), .m5_degraded_mode(1'b0),
        .m5_redundancy_ok(1'b0), .m5_frame_count_match(1'b0), .m5_active_byte_count_match(1'b0),
        .m5_fault_applied_event(1'b0), .m5_rx_accepted_count(32'b0),
        .m5_rx_accepted_a_count(32'b0), .m5_rx_accepted_b_count(32'b0),
        .m5_rx_duplicate_count(32'b0), .m5_rx_cross_network_duplicate_count(32'b0),
        .m5_rx_same_network_repeat_count(32'b0), .m5_rx_stale_count(32'b0),
        .m5_rx_sequence_gap_count(32'b0), .m5_tx_a_frame_count(32'b0), .m5_tx_b_frame_count(32'b0),
        .m5_tx_a_active_byte_count(32'b0), .m5_tx_b_active_byte_count(32'b0),
        .m5_tx_byte_mismatch_count(32'b0), .m5_tx_frame_skew_cycle_count(32'b0),
        .m5_tx_frame_done_skew_count(32'b0), .m5_tx_er_mismatch_count(32'b0),
        .m5_tx_a_error_cycle_count(32'b0), .m5_tx_b_error_cycle_count(32'b0),
        .m5_tx_a_underrun_count(32'b0), .m5_tx_b_underrun_count(32'b0)
    );
    localparam [367:0] GET1=368'h302c02010104067075626c6963a01f0204123456780201000201003011300f060b2b0601040181fd590101010500;
    localparam [367:0] GET2=368'h302c02010104067075626c6963a01f0204234567890201000201003011300f060b2b0601040181fd590101060500;
    localparam [391:0] RESP1=392'h302f02010104067075626c6963a22202041234567802010002010030143012060b2b0601040181fd590101010203060a01;
    localparam [375:0] RESP2=376'h302d02010104067075626c6963a22002042345678902010002010030123010060b2b0601040181fd59010106410100;
    integer errors=0, physical=0, commits=0, reqs=0, responses=0, starts=0, builds=0, frames=0, rejects=0;
    integer idx=0, idle_cycles=100, expected_len=104, case_errors=0;
    reg in_tx=0, previous_done=0, holding=0;
    reg [7:0] expected [0:127];
    reg [207:0] context_q;
    reg [767:0] message_q;
    reg [7:0] seq_q;
    task fail;
        input [511:0] reason;
        begin errors=errors+1; $display("M6E_01D_ERROR t=%0t %0s", $time, reason); end
    endtask
    // 期望来自固定golden BER与测试配置，绝不读取DUT输出生成期望。
    task make_expected;
        input integer which;
        integer n, k, j, sum, body;
        reg [31:0] crc, dip;
        reg [15:0] port;
        begin
            n=49; dip=32'hc0a80164; port=40000;
            if (which==1) begin n=47; dip=32'hc0a80165; port=40001; end
            body=43+n; expected_len=body+12;
            for(k=0;k<128;k=k+1) expected[k]=0;
            for(k=0;k<7;k=k+1) expected[k]=8'h55;
            expected[7]=8'hd5;
            expected[8]=2; expected[13]=2; expected[14]=2; expected[19]=1;
            expected[20]=8'h08;
            expected[22]=8'h45; expected[25]=28+n;
            expected[30]=8'h40; expected[31]=8'h11;
            expected[34]=192; expected[35]=168; expected[36]=1; expected[37]=1;
            for(k=0;k<4;k=k+1) expected[38+k]=dip[31-k*8 -: 8];
            expected[43]=161; expected[44]=port[15:8]; expected[45]=port[7:0];
            expected[47]=8+n;
            sum=0;
            for(k=22;k<42;k=k+2) sum=sum+{expected[k],expected[k+1]};
            sum=(sum & 65535)+(sum >> 16); sum=(sum & 65535)+(sum >> 16);
            {expected[32],expected[33]}=~sum;
            for(k=0;k<n;k=k+1)
                if(which==0) expected[50+k]=RESP1[391-k*8 -: 8];
                else expected[50+k]=RESP2[375-k*8 -: 8];
            expected[50+n]=which;
            // 独立逐位CRC，覆盖整个body和最后sequence字节。
            crc=32'hffffffff;
            for(k=8;k<8+body;k=k+1)
                for(j=0;j<8;j=j+1)
                    if(crc[0]^expected[k][j]) crc=(crc>>1)^32'hedb88320;
                    else crc=crc>>1;
            crc=~crc;
            for(k=0;k<4;k=k+1) expected[8+body+k]=crc[k*8 +: 8];
        end
    endtask
    // 调用点和所有输入变化都在negedge；紧接前一报文结束可注入metadata。
    task datagram;
        input [367:0] bytes;
        input [31:0] ip;
        input [15:0] port, dst;
        integer k;
        begin
            physical=physical+1;
            meta_valid=1; src_ip=ip; udp_src_port=port; udp_dst_port=dst;
            @(negedge clk); meta_valid=0;
            for(k=0;k<46;k=k+1) begin
                payload_valid=1; payload_sof=(k==0); payload_eof=(k==45);
                payload_data=bytes[367-k*8 -: 8];
                @(negedge clk);
            end
            payload_valid=0; payload_sof=0; payload_eof=0;
            frame_done=1; frame_valid=1;
            @(negedge clk); frame_done=0; frame_valid=0;
        end
    endtask
    // 先采样握手，再于NBA之后检查GMII注册输出。
    always @(posedge clk) if(!rst) begin
        if (rx_commit) begin
            commits=commits+1;
            if(holding) fail("重复commit");
            holding=1;
            context_q={cfg_src_mac,cfg_dst_mac,cfg_src_ip,dut.active_requester_ip,16'd161,dut.active_requester_port};
            message_q=dut.active_msg_bytes; seq_q=sequence_num;
        end
        if(dut.u_m6d.req) reqs=reqs+1;
        if(response_done) begin
            responses=responses+1;
            if(response_error) begin
                rejects=rejects+1;
                if(response_valid || response_error_code!=2) fail("community拒绝类型错误");
                holding=0;
            end
        end
        if(builder_start) starts=starts+1;
        if(builder_done) builds=builds+1;
        if(tx_frame_done) holding=0;
        #1;
        if(holding) begin
            if(!busy) fail("事务未结束busy提前释放");
            if({dut.src_mac_q,dut.dst_mac_q,dut.src_ip_q,dut.requester_ip_q,dut.src_port_q,dut.requester_port_q} !== context_q)
                fail("锁存context发生变化");
            if(dut.active_msg_bytes !== message_q || sequence_num !== seq_q) fail("活动请求或sequence被覆盖");
        end
        if(rx_commit && !busy) fail("commit窗口busy未覆盖");
        if(underrun!==0) begin fail("正常路径underrun fatal"); $finish; end
        if(payload_ready!==1 || gmii_tx_er!==0) fail("ready/tx_er错误");
        if(tx_frame_done && previous_done) fail("frame_done不是单拍");
        previous_done=tx_frame_done;
        if(gmii_tx_en) begin
            if(!in_tx) begin
                if(idle_cycles<12) fail("IFG少于12拍");
                if(frames>=2) fail("额外GMII帧");
                in_tx=1; idx=0;
            end
            idle_cycles=0;
            if(idx>=expected_len || gmii_txd!==expected[idx]) begin
                $display("BYTE frame=%0d index=%0d got=%02x expected=%02x",frames,idx,gmii_txd,expected[idx]);
                fail("GMII字节不匹配");
            end
            if(tx_frame_done !== (idx==expected_len-1)) fail("frame_done未严格对应最后FCS");
            if(!busy) fail("GMII期间busy为0");
            idx=idx+1;
        end else begin
            idle_cycles=idle_cycles+1;
            if(tx_frame_done) fail("frame_done没有tx_en");
            if(in_tx) begin
                if(idx!=expected_len) fail("帧内tx_en不连续或长度错误");
                in_tx=0;
            end
        end
        if(tx_frame_done) begin
            frames=frames+1;
            $display("GMII_DONE frame=%0d bytes=%0d body=%0d",frames,idx,idx-12);
        end
    end
    reg [367:0] bad_community;
    initial begin
        make_expected(0);
        repeat(5) @(negedge clk); rst=0;
        repeat(3) @(negedge clk);
        case_errors=errors;
        datagram(GET1,32'hc0a80164,16'd40000,16'd161);
        if(!rx_commit || !busy) fail("未命中commit准入边界");
        // 第二物理报文在commit采样同拍提供metadata，必须被busy丢弃。
        fork
            datagram(GET2,32'h0a000099,16'd49999,16'd161);
            begin
                @(negedge clk);
                cfg_src_mac=48'hdeadbeef0011; cfg_dst_mac=48'hdeadbeef0022;
                cfg_src_ip=32'h0a000001;
            end
        join
        wait(frames==1); repeat(20) @(negedge clk);
        if(commits!=1 || reqs!=1 || responses!=1 || starts!=1 || builds!=1 || busy || sequence_num!=1)
            fail("第一事务与busy-drop计数错误");
        if(errors==case_errors) $display("CASE_FIRST_GET_BUSY_DROP_CFG_LOCK_PASS");
        cfg_src_mac=48'h020000000001; cfg_dst_mac=48'h020000000002;
        cfg_src_ip=32'hc0a80101;
        case_errors=errors;
        datagram(GET2,32'hc0a80165,16'd40001,16'd162);
        repeat(20) @(negedge clk);
        if(commits!=1 || reqs!=1 || responses!=1 || starts!=1 || frames!=1 || busy || sequence_num!=1)
            fail("unsupported port未丢弃");
        if(errors==case_errors) $display("CASE_PORT_DROP_PASS");
        case_errors=errors;
        bad_community=GET2; bad_community[367-7*8 -: 8]=8'h78;
        datagram(bad_community,32'hc0a80166,16'd40002,16'd161);
        wait(responses==2); repeat(20) @(negedge clk);
        if(commits!=2 || reqs!=2 || rejects!=1 || busy || starts!=1 || frames!=1 || sequence_num!=1)
            fail("community reject未释放或误发响应");
        if(errors==case_errors) $display("CASE_COMMUNITY_REJECT_PASS");
        case_errors=errors; make_expected(1);
        datagram(GET2,32'hc0a80165,16'd40001,16'd161);
        wait(frames==2); repeat(300) @(negedge clk);
        if(physical!=5 || commits!=3 || reqs!=3 || responses!=3 || starts!=2 || builds!=2 || frames!=2 || rejects!=1 || busy || sequence_num!=2)
            fail("最终统计或quiet重复响应错误");
        if(errors==case_errors) $display("CASE_SECOND_GET_RECOVERY_QUIET_PASS");
        $display("COUNTS physical=%0d commits=%0d m6d_req=%0d m6d_done=%0d builder_start=%0d builder_done=%0d gmii_done=%0d reject=%0d sequence=%0d",physical,commits,reqs,responses,starts,builds,frames,rejects,sequence_num);
        $display("M6E_01D_FAILS=%0d",errors);
        if(errors==0) $display("M6E_01D_TB_PASS");
        else $display("M6E_01D_TB_FAIL errors=%0d",errors);
        $finish;
    end
    initial begin
        #490000;
        $display("M6E_01D_TB_TIMEOUT errors=%0d physical=%0d commits=%0d responses=%0d frames=%0d",errors,physical,commits,responses,frames);
        $finish;
    end
endmodule
