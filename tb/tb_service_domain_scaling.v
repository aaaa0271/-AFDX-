`timescale 1ns/1ps
// Parameterized profile-table and frame-arbiter checks; run DOMAINS=1,2,4,5,8,9.
module tb_service_domain_scaling #(parameter integer DOMAINS=2);
 localparam integer DW=$clog2(DOMAINS+1);
 reg clk=0,rst=1;always #5 clk=~clk;
 integer errors=0,d,k,t,round,frames=0,offset=0,expected=0;
 reg cfg_we=0,cfg_kind=0,cfg_commit=0,cfg_enable=1,select_valid=0,select_kind=0,tx_event=0;
 reg [DW-1:0] cfg_domain=0,select_domain=0;
 reg [3:0] cfg_vl=0;reg [7:0] cfg_sequence_domain=0,cfg_retry=0;
 reg [47:0] cfg_mac=0;reg [31:0] cfg_ip=0,cfg_timeout=0;reg [15:0] cfg_udp=0,cfg_tid=0;
 wire cfg_ready,cfg_error,commit_pulse,selected_valid;
 wire [3:0] selected_vl;wire [7:0] selected_sequence_domain,selected_sequence,selected_retry;
 wire [47:0] selected_mac;wire [31:0] selected_ip,selected_timeout;wire [15:0] selected_udp,selected_tid;
 afdx_service_domain_table #(.DOMAINS(DOMAINS)) table_dut(.*);
 reg tx_admit=0;reg [DOMAINS*8-1:0] lane_data=0;reg [DOMAINS-1:0] lane_en=0,lane_er=0;
 wire [DOMAINS-1:0] lane_admit;wire [7:0] tx_data;wire tx_en,tx_er,idle;wire [31:0] overflows;
 afdx_service_domain_tx_mux #(.DOMAINS(DOMAINS),.MAX_FRAME_BYTES(32)) mux_dut(.*);
 task fail;input [511:0] msg;begin errors=errors+1;$display("FAIL SCALE D=%0d %0s",DOMAINS,msg);end endtask
 task select_zero;
 begin #1;if({selected_valid,selected_vl,selected_sequence_domain,selected_mac,selected_ip,selected_udp,selected_tid,selected_timeout,selected_retry,selected_sequence}!==0)fail("invalid profile selector");end
 endtask
 reg previous=0;reg monitor=0;
 always @(negedge clk)if(!rst&&monitor)begin
  if(tx_en)begin
   if(tx_data!==(expected*16+offset))fail("frame byte / domain arbitration order");
   if(tx_er!==(expected==DOMAINS-1))fail("whole-frame error propagation");
   offset=offset+1;
   // Withdraw downstream admission as soon as the first byte appears.
   // The current frame must still finish without a gap or truncation.
   tx_admit=0;
  end else if(previous)begin
   if(offset!=12)fail("truncated frame");
   offset=0;frames=frames+1;expected=(expected+1)%DOMAINS;
  end
  previous=tx_en;
 end
 initial begin
  repeat(3)@(negedge clk);rst=0;
  if($bits(cfg_domain)!=DW||$bits(lane_admit)!=DOMAINS)fail("derived widths");
  for(k=0;k<2;k=k+1)for(d=0;d<DOMAINS;d=d+1)begin
   @(negedge clk);cfg_we=1;cfg_domain=d;cfg_kind=k;
   cfg_vl=d;cfg_sequence_domain=k*32+d;cfg_ip=32'h0a000001+k*256+d;
   cfg_mac=48'h030000000010+k*256+d;cfg_udp=100+k;cfg_tid=200+d;cfg_timeout=300+d;cfg_retry=d;
   @(negedge clk);cfg_we=0;#1;if(cfg_error||!cfg_ready)fail("valid profile write");
  end
  select_valid=1;select_domain=DOMAINS-1;#1;if(selected_valid)fail("shadow profile leaked before commit");
  @(negedge clk);cfg_commit=1;@(negedge clk);cfg_commit=0;#1;if(!commit_pulse)fail("profile commit");
  for(k=0;k<2;k=k+1)for(d=0;d<DOMAINS;d=d+1)begin
   @(negedge clk);select_kind=k;select_domain=d;#1;
   if(!selected_valid||selected_ip!==32'h0a000001+k*256+d||selected_sequence_domain!==k*32+d||
      selected_mac!==48'h030000000010+k*256+d||selected_udp!==100+k||selected_tid!==200+d||
      selected_timeout!==300+d||selected_retry!==d||selected_sequence!==0)fail("profile selection / index truncation");
   tx_event=1;@(negedge clk);tx_event=0;#1;if(selected_sequence!==1)fail("independent sequence");
  end
  for(d=DOMAINS;d<(1<<DW);d=d+1)begin select_domain=d;select_zero;end
  select_domain={DW{1'bx}};select_zero;
  select_domain={DW{1'bz}};select_zero;
  @(negedge clk);cfg_domain=DOMAINS;cfg_we=1;#1;if(cfg_ready)fail("invalid profile ready");
  @(negedge clk);cfg_we=0;#1;if(!cfg_error)fail("invalid profile write");
  select_domain=0;select_kind=0;#1;if(selected_sequence!==1)fail("invalid selection corrupted domain zero");
  // Two rounds exercise wraparound, every domain, full backpressure, and errors.
  monitor=1;
  for(round=0;round<2;round=round+1)begin
   @(posedge clk);#1;if(lane_admit!=={DOMAINS{1'b1}})fail("lanes not admitted");
   for(k=0;k<12;k=k+1)begin
    @(posedge clk);#1;lane_en={DOMAINS{1'b1}};
    for(d=0;d<DOMAINS;d=d+1)begin lane_data[d*8+:8]=d*16+k;lane_er[d]=(d==DOMAINS-1&&k==11);end
   end
   @(posedge clk);#1;lane_en=0;lane_er=0;
   repeat(20)@(posedge clk);#1;if(tx_en||idle||lane_admit!==0)fail("backpressure buffering");
   for(d=0;d<DOMAINS;d=d+1)begin
    tx_admit=1;t=0;
    while(frames<round*DOMAINS+d+1&&t<100)begin @(posedge clk);#1;t=t+1;end
    if(t==100)fail("arbiter starvation / truncated frame");
    repeat(15)@(posedge clk);#1;
   end
  end
  if(!idle||overflows!==0||frames!=2*DOMAINS)fail("arbiter completion");
  monitor=0;
  // Oversize frames are discarded whole and the lane recovers for next use.
  for(k=0;k<33;k=k+1)begin @(negedge clk);lane_en=1;lane_data=8'h55;end
  @(negedge clk);lane_en=0;repeat(4)@(negedge clk);
  if(overflows!==1||!idle||lane_admit!=={DOMAINS{1'b1}})fail("overflow recovery");
  $display("DOMAIN_SCALING domains=%0d width=%0d frames=%0d errors=%0d",DOMAINS,DW,frames,errors);
  if(errors==0)$display("TB_SERVICE_DOMAIN_SCALING_PASS");else $display("TB_SERVICE_DOMAIN_SCALING_FAIL");$finish;
 end
 initial begin #200000;fail("watchdog");$finish;end
endmodule
