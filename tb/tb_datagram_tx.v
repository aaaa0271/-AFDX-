`timescale 1ns/1ps
module tb_datagram_tx;
reg clk=0;always #40 clk=~clk;reg rst=1,enable=1,a_enable=1,b_enable=1,cfg_we=0;
reg [671:0] cfg=0;reg [1:0] cfg_vl=0,port=0;reg [15:0] lmax=1518,len=0;reg [31:0] bag=12500;
reg en=0,sof=0,eof=0;reg [7:0] data=0;wire ready,accept,len_error;
wire [7:0] a,b;wire av,bv,ae,be,ad,bd,busy;wire [31:0] messages,frames,errors_count;
integer errors=0,case_id=0,expected_messages=0,i,k,t,stall_cycles=0,ids[0:3],wirefile,j,n=0;
reg previous=0;reg [7:0] captured[0:1535];
afdx_datagram_tx #(.SAMPLING_MASK(4'b1000)) dut(.clk(clk),.rst(rst),.tx_enable(enable),.network_a_enable(a_enable),.network_b_enable(b_enable),.network_cfg(cfg),
.cfg_we(cfg_we),.cfg_vl_id(cfg_vl),.cfg_bag(bag),.cfg_lmax(lmax),.app_wr_en(en),.app_wr_vl_id(port),.app_wr_data(data),.app_wr_len(len),.app_wr_sof(sof),.app_wr_eof(eof),
.app_wr_ready(ready),.app_wr_accept(accept),.app_len_error(len_error),.a_data(a),.b_data(b),.a_en(av),.b_en(bv),.a_er(ae),.b_er(be),.a_done(ad),.b_done(bd),.busy(busy),.messages(messages),.frames(frames),.errors(errors_count));
task fail;input [511:0] why;begin errors=errors+1;$display("FAIL DATAGRAM_TX case=%0d %0s",case_id,why);end endtask
always @(negedge clk)if(!rst)begin
 if(av!==bv||(av&&a!==b)||ae||be)fail("A/B physical copy mismatch/error");
 if(av)begin captured[n]=a;n=n+1;end
 else if(previous)begin
  $fwrite(wirefile,"%0d %0t %0d ",case_id,$time,lmax);for(j=0;j<n;j=j+1)$fwrite(wirefile,"%02x",captured[j]);$fwrite(wirefile,"\n");n=0;
 end
 previous=av;
end
task new_case;input integer id,limit;begin
 @(negedge clk);rst=1;en=0;sof=0;eof=0;enable=1;repeat(4)@(negedge clk);rst=0;case_id=id;expected_messages=0;n=0;previous=0;lmax=limit;
 for(i=0;i<4;i=i+1)begin ids[i]=0;cfg_we=1;cfg_vl=i;@(negedge clk);cfg_we=0;@(negedge clk);end
end endtask
task send;input integer n,seed,vl;integer b,ticks;begin
 $display("TX_EXPECT case=%0d vl=%0d id=%0d bytes=%0d seed=%0d",case_id,vl,ids[vl],n,seed);ids[vl]=ids[vl]+1;expected_messages=expected_messages+1;
 for(b=0;b<n;b=b+1)begin
  @(negedge clk);en=1;sof=b==0;eof=b==n-1;len=n;port=vl;data=(seed+b*7)&255;#1;ticks=0;
  while(!ready&&ticks<100000)begin @(negedge clk);#1;ticks=ticks+1;stall_cycles=stall_cycles+1;end
  if(!ready)fail("input admission timeout");
 end
 @(negedge clk);en=0;sof=0;eof=0;
end endtask
task drain;begin
 t=0;while((dut.count[0]!=0||dut.count[1]!=0||dut.count[2]!=0||dut.count[3]!=0||busy)&&t<600000)begin @(negedge clk);t=t+1;end
 repeat(30)@(negedge clk);if(t>=600000||messages!=expected_messages)fail("drain/message cardinality");
end endtask
reg [47:0] mac;reg [31:0] ip;reg [15:0] dp;
initial begin
 wirefile=$fopen("tx_wire.txt","w");for(i=0;i<4;i=i+1)begin mac=48'h030000000002+i;ip=32'h0a000002+i;dp=10001+i;cfg[i*168+:168]={16'd1518,dp,16'd10000,ip,32'h0a000001,mac,8'h03};end
 new_case(0,1518);send(1,1,0);drain;send(17,2,0);drain;send(18,3,0);drain;send(1471,4,0);drain;send(1472,5,0);drain;send(8191,6,0);drain;send(8192,7,0);drain;
 new_case(1,64);send(16,21,0);drain;send(17,22,0);drain;send(18,23,0);drain;send(129,24,0);drain;
 new_case(2,256);send(209,31,1);drain;send(210,32,1);drain;send(8192,33,1);drain;
 new_case(3,1518);enable=0;send(1000,41,0);send(1001,42,0);
 fork begin send(1002,43,0);end begin repeat(200)@(negedge clk);enable=1;end join
 send(8192,44,1);send(8191,45,2);send(1471,46,3);drain;if(stall_cycles==0)fail("queue backpressure not exercised");
 new_case(4,1518);
 for(k=0;k<3;k=k+1)begin @(negedge clk);port=0;len=10;data=k;en=1;sof=k==0;eof=k==2;end
 @(negedge clk);en=0;sof=0;eof=0;repeat(5)@(negedge clk);if(messages!=0||errors_count==0)fail("early EOF admitted");
 send(63,51,0);drain;
 new_case(5,1518);@(negedge clk);en=1;sof=1;eof=0;port=3;len=1472;#1;if(ready)fail("sampling fragmentation accepted");
 @(negedge clk);en=0;sof=0;repeat(3)@(negedge clk);if(messages!=0||errors_count==0)fail("sampling rejection not reported");send(1471,61,3);drain;
 new_case(6,1518);enable=0;send(17,71,3);send(18,72,3);send(19,73,3);
 $display("TX_SUPERSEDED case=6 vl=3 id=0");$display("TX_SUPERSEDED case=6 vl=3 id=1");
 enable=1;drain;
 new_case(7,1518);send(1471,81,3);repeat(20)@(negedge clk);enable=0;
 send(129,82,3);send(130,83,3);$display("TX_SUPERSEDED case=7 vl=3 id=1");enable=1;drain;
 new_case(8,1518);enable=0;send(17,91,3);
 for(k=0;k<3;k=k+1)begin @(negedge clk);port=3;len=20;data=k;en=1;sof=k==0;eof=k==2;end
 @(negedge clk);en=0;sof=0;eof=0;repeat(5)@(negedge clk);if(errors_count==0)fail("invalid sample update accepted");enable=1;drain;
 new_case(9,1518);@(negedge clk);en=1;sof=1;eof=0;port=0;len=8193;#1;if(ready)fail("over-capacity message accepted");
 @(negedge clk);en=0;sof=0;repeat(3)@(negedge clk);if(messages!=0||errors_count==0)fail("maximum length error missing");drain;
 new_case(10,1518);cfg[1*168+1]=0;@(negedge clk);en=1;sof=1;eof=1;port=1;len=1;#1;if(ready)fail("disabled TX VL ready");
 @(negedge clk);en=0;sof=0;eof=0;repeat(3)@(negedge clk);if(messages!=0||errors_count==0)fail("disabled TX VL not rejected");cfg[1*168+1]=1;send(1,101,1);drain;
 $fclose(wirefile);$display("DATAGRAM_TX_CASES=11 STALL_CYCLES=%0d ERRORS=%0d",stall_cycles,errors);
 if(errors==0)$display("TB_DATAGRAM_TX_PASS");else $display("TB_DATAGRAM_TX_FAIL");$finish;
end
initial begin #500000000;$display("DATAGRAM_TX_TIMEOUT");$finish;end
endmodule