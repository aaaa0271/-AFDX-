`timescale 1ns/1ps
module tb_m6_business_varlen;
reg clk=0;always #5 clk=~clk;reg rst=1,enable=0,na=1,nb=1,cwe=0,we=0,sof=0,eof=0;
reg [1:0] cvl=0,vl=0;reg [31:0] bag=2000;reg [15:0] lmax=1518,len=0;reg [7:0] dest=2,data=0;
wire ready,accepted,err,busy,start;wire [7:0] ad,bd,sn;wire ae,be,ax,bx,af,bf,au,bu;wire [1:0] tv;
wire aa,bb,degraded;
integer wrap_frame,offered_frames=0;
integer expected_frame_length[0:511],expected_frame_seed[0:511],expected_frame_vl[0:511];
always @(posedge clk)if(!rst && dut.app_wr_accept && !dut.cap_bad && dut.body_valid && dut.body_ready)
 if(dut.wr_address=={dut.selected_vl,dut.tx_slot,dut.read_index})fail("RAM read/write collision on owned TX slot");
integer errors=0,frames=0,bytes=0,cycles=0,cases=0,idx=0,k,n,waits,current_vl;
reg [7:0] capture[0:1537];reg prev_en=0;
integer expected_len[0:3],expected_seed[0:3],expected_sn[0:3],last_start[0:3];
reg [31:0] crc;reg [15:0] ip_sum;integer sum;
afdx_business_tx_varlen dut(.network_cfg(672'd0),.clk(clk),.rst(rst),.tx_enable(enable),.network_a_enable(na),.network_b_enable(nb),
.cfg_we(cwe),.cfg_vl_id(cvl),.cfg_bag(bag),.cfg_lmax(lmax),.cfg_destination(dest),
.app_wr_en(we),.app_wr_vl_id(vl),.app_wr_data(data),.app_wr_len(len),.app_wr_sof(sof),.app_wr_eof(eof),.app_wr_ready(ready),.app_wr_accept(accepted),.app_len_error(err),
.gmii_a_txd(ad),.gmii_b_txd(bd),.gmii_a_tx_en(ae),.gmii_b_tx_en(be),.gmii_a_tx_er(ax),.gmii_b_tx_er(bx),.gmii_a_frame_done(af),.gmii_b_frame_done(bf),.gmii_a_underrun(au),.gmii_b_underrun(bu),
.network_a_active(aa),.network_b_active(bb),.degraded_mode(degraded),.busy(busy),.frame_start(start),.selected_vl(tv),.selected_seq(sn));
function [31:0] crcbyte;input [31:0] c;input [7:0] b;reg [31:0] x;integer t;begin
 x=c^b;for(t=0;t<8;t=t+1)x=x[0]?(x>>1)^32'hedb88320:x>>1;crcbyte=x;end endfunction
task fail;input [639:0] why;begin errors=errors+1;$display("FAIL frame=%0d idx=%0d %0s",frames,idx,why);if(errors>8)$finish;end endtask
always @(posedge clk) begin
 #1;cycles=cycles+1;
 if(!rst)begin
  if(ax||bx||au||bu)fail("GMII underrun/error");
  if(aa&&bb && (ae!==be || (ae && ad!==bd)))fail("A/B physical byte mismatch");
  if(ae||be)begin
   if(!prev_en)begin idx=0;current_vl=tv;
    if(cycles-last_start[tv]<bag)fail("per-VL BAG spacing");last_start[tv]=cycles;
   end
   capture[idx]=ae?ad:bd;idx=idx+1;
  end else if(prev_en)begin
   frames=frames+1;n=expected_frame_length[frames-1];
   if(current_vl!=expected_frame_vl[frames-1])fail("queue packet ordering");
   if(idx!=(n<=17?72:n+55))fail("actual wire length");
   for(k=0;k<7;k=k+1)if(capture[k]!=8'h55)fail("preamble");if(capture[7]!=8'hd5)fail("SFD");
   if(capture[13]!=current_vl+2 || capture[25]!=((n+28)&255) || capture[24]!=((n+28)>>8) ||
      capture[47]!=((n+8)&255)||capture[46]!=((n+8)>>8))fail("network lengths/address");
   sum=0;for(k=22;k<42;k=k+2)sum=sum+{capture[k],capture[k+1]};
   sum=(sum&65535)+(sum>>16);sum=(sum&65535)+(sum>>16);if(sum!=65535)fail("IPv4 checksum");
   for(k=0;k<n;k=k+1)if(capture[50+k]!==((expected_frame_seed[frames-1]+k*7)&255))fail("real payload byte/FIFO");
   for(k=50+n;k<idx-5;k=k+1)if(capture[k]!=0)fail("padding");
   if(capture[idx-5]!=expected_sn[current_vl])fail("per-VL sequence");
   expected_sn[current_vl]=expected_sn[current_vl]==255?1:expected_sn[current_vl]+1;
   crc=32'hffffffff;for(k=8;k<idx;k=k+1)crc=crcbyte(crc,capture[k]);if(crc!=32'hdebb20e3)fail("Ethernet FCS");
  end
  prev_en=ae||be;
 end
end
task cfg;input [1:0] v;input [15:0] maxlen;begin @(negedge clk);cvl=v;lmax=maxlen;dest=v+2;cwe=1;@(negedge clk);cwe=0;end endtask
task put_frame;input [1:0] v;input integer length;input integer seed;integer j,t;begin
 expected_len[v]=length;expected_seed[v]=seed;cases=cases+1;
 expected_frame_length[offered_frames]=length;expected_frame_seed[offered_frames]=seed;expected_frame_vl[offered_frames]=v;
 offered_frames=offered_frames+1;
 for(j=0;j<length;j=j+1)begin
  @(negedge clk);we=1;vl=v;len=length;sof=j==0;eof=j==length-1;data=(seed+j*7)&255;
  t=0;#1;while(!ready&&t<10000)begin @(negedge clk);t=t+1;end
  if(!ready)fail("ingress deadlock");
 end
 @(negedge clk);we=0;sof=0;eof=0;
end endtask
task drain;integer t;begin t=0;while((busy||dut.count[0]!=0||dut.count[1]!=0||dut.count[2]!=0||dut.count[3]!=0)&&t<20000)begin @(negedge clk);t=t+1;end if(t>=20000)fail("drain timeout");repeat(4)@(negedge clk);end endtask
task reject_length;input integer length;begin
 @(negedge clk);we=1;sof=1;eof=1;len=length;vl=0;#1;if(accepted)fail("illegal length accepted");
 @(posedge clk);#1;if(!err)fail("missing length error");@(negedge clk);we=0;sof=0;eof=0;
end endtask
initial begin
 for(k=0;k<4;k=k+1)begin expected_sn[k]=0;last_start[k]=-100000;expected_len[k]=0;expected_seed[k]=0;end
 repeat(4)@(negedge clk);rst=0;
 for(k=0;k<4;k=k+1)cfg(k,1518);enable=1;
 put_frame(0,1,3);drain;put_frame(1,4,19);drain;put_frame(2,17,50);drain;put_frame(3,18,77);drain;
 put_frame(0,96,13);drain;put_frame(0,97,9);drain;put_frame(0,255,36);drain;put_frame(0,256,41);drain;put_frame(0,512,83);drain;put_frame(0,1471,101);drain;
 reject_length(0);reject_length(1472);
 cfg(0,64);reject_length(18);put_frame(0,17,26);drain;cfg(0,65);put_frame(0,18,46);drain;cfg(0,1518);
 // Hold two complete payloads while globally disabled. Full FIFO backpressures
 // a third SOF and does not overwrite either queued frame.
 enable=0;put_frame(0,32,66);put_frame(0,32,151);
 @(negedge clk);we=1;sof=1;eof=0;len=32;vl=0;#1;if(ready||accepted)fail("full FIFO must backpressure");
 repeat(3)@(negedge clk);we=0;sof=0;enable=1;drain;
 // Degradation changes are latched at a frame boundary.
 na=0;nb=1;put_frame(1,24,89);drain;na=1;nb=0;put_frame(2,64,111);drain;
 na=1;nb=1;put_frame(3,64,129);wait(ae);@(negedge clk);nb=0;drain;
 na=1;nb=1;bag=100;cfg(0,1518);
 // Second slot receives a distinct full packet while the first is transmitting.
 put_frame(0,512,71);put_frame(0,512,139);drain;
 for(wrap_frame=0;wrap_frame<260;wrap_frame=wrap_frame+1)begin put_frame(0,1,wrap_frame);drain;end
 if(frames!=279)fail("lost/extra frame");
 $display("BUSINESS_FRAMES=%0d ERRORS=%0d",frames,errors);
 if(errors==0)$display("M6_BUSINESS_REPAIR_PASS");else $display("M6_BUSINESS_REPAIR_FAIL");$finish;
end
initial begin #2000000;$display("BUSINESS_TIMEOUT");$finish;end
endmodule
