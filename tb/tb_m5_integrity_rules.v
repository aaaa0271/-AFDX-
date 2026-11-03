`timescale 1ns/1ps
module tb_m5_integrity_rules;
reg clk=0;always #5 clk=~clk;reg rst_n=0,clear=0,rx_valid=0,network=0,out_ready=1;
reg [1:0] vl=0;reg [7:0] sn=0;reg [31:0] payload=0;
wire ready,accept,dup,stale,gap,out_valid;wire [1:0] ov;wire [7:0] os;wire [31:0] od;wire onet;
wire [31:0] ac,aa,ab,dc,xc,sc,st,gc;
integer errors=0,cases=0,prev,nextsn,expected,j;
afdx_rx_redundancy_eliminator #(.HISTORY_TIMEOUT_CYCLES(32)) dut(
.clk(clk),.rst_n(rst_n),.clear(clear),.rx_valid(rx_valid),.rx_ready(ready),.rx_network(network),.rx_vl_id(vl),.rx_seq(sn),.rx_payload(payload),
.out_valid(out_valid),.out_ready(out_ready),.out_vl_id(ov),.out_seq(os),.out_payload(od),.out_network(onet),
.accept_event(accept),.duplicate_event(dup),.stale_event(stale),.gap_event(gap),
.accepted_count(ac),.accepted_a_count(aa),.accepted_b_count(ab),.duplicate_count(dc),.cross_network_duplicate_count(xc),.same_network_repeat_count(sc),.stale_count(st),.sequence_gap_count(gc),
.last_valid0_dbg(),.last_valid1_dbg(),.last_valid2_dbg(),.last_valid3_dbg(),.last_seq0_dbg(),.last_seq1_dbg(),.last_seq2_dbg(),.last_seq3_dbg(),.seen_mask0_dbg(),.seen_mask1_dbg(),.seen_mask2_dbg(),.seen_mask3_dbg());
task fail;input [511:0] why;begin errors=errors+1;$display("FAIL case=%0d prev=%0d sn=%0d %0s",cases,prev,sn,why);if(errors>6)$finish;end endtask
task wipe;begin @(negedge clk);clear=1;rx_valid=0;@(negedge clk);clear=0;end endtask
// 0 = accept, 1 = duplicate, 2 = integrity/stale reject.
task frame;input net;input [1:0] v;input [7:0] s;input integer result;begin
 @(negedge clk);network=net;vl=v;sn=s;payload={22'd0,v,s};rx_valid=1;
 #1;if(!ready)fail("unexpected backpressure");
 @(posedge clk);#1;cases=cases+1;
 if(accept!==(result==0)||dup!==(result==1)||stale!==(result==2))fail("classification");
 if(result==0 && (!out_valid||os!=s||ov!=v||onet!=net||od!={22'd0,v,s}))fail("output ownership/data");
 @(negedge clk);rx_valid=0;
end endtask
function integer inc;input integer v;begin inc=v==255?1:v+1;end endfunction
initial begin
 repeat(3)@(negedge clk);rst_n=1;
 // Exhaust every possible physical previous/current pair independently of RTL math.
 for(prev=0;prev<256;prev=prev+1)for(nextsn=0;nextsn<256;nextsn=nextsn+1)begin
  wipe;frame(0,0,prev,0);
  expected=(nextsn==prev)?1:((nextsn==0||nextsn==inc(prev)||nextsn==inc(inc(prev)))?0:2);
  frame(0,0,nextsn,expected);
 end
 wipe;frame(0,0,100,0);frame(1,0,100,1);frame(0,0,0,0);frame(0,0,1,0);
 frame(1,0,0,1);frame(1,0,1,1); // delayed reset copy must not roll back
 frame(0,0,2,0);if(gc!=0)fail("reset/wrap reported loss");
 // Orphaned reset marker: the SN=0 copies were lost on both networks, A's
 // SN=1 established the logical stream, then B's SN=0/SN=1 arrive late.
 // Neither may be re-delivered; the stream must continue at SN=2.
 wipe;frame(0,0,1,0);frame(1,0,0,1);frame(1,0,1,1);frame(0,0,2,0);
 if(ac!=2||os!=2||gc!=0)fail("orphan reset copy replay");
 if(xc!=2)fail("orphan reset copy not classified cross-network duplicate");
 wipe;frame(0,0,254,0);frame(1,0,254,1);frame(0,0,1,0);
 if(gc!=1||!gap)fail("254->1 is one loss, not two");frame(1,0,1,1);
 // A's gap of three is rejected; B's independent stream is unaffected.
 wipe;frame(0,0,10,0);frame(1,0,10,1);frame(0,0,13,2);frame(1,0,11,0);frame(0,0,14,0);
 if(gc!=2)fail("logical gaps after physical recovery");
 frame(1,0,14,2);frame(1,0,15,0); // rejected 14 still advances B PSN
 frame(0,1,200,0);frame(0,0,15,1); // VL isolation
 // A stream of IC-invalid packets must not suppress SkewMax recovery.
 wipe;frame(0,0,100,0);frame(1,0,100,1);
 repeat(36)@(negedge clk);
 frame(0,0,200,0);frame(1,0,200,1); // BOTH IC states reset
 // Backpressure must not advance PSN/history or replace the held output.
 wipe;out_ready=0;frame(0,0,10,0);
 @(negedge clk);sn=11;rx_valid=1;
 repeat(3)begin @(posedge clk);#1;if(ready||ac!=1||os!=10)fail("backpressure history");end
 @(negedge clk);out_ready=1;@(posedge clk);#1;if(ac!=2||os!=11)fail("backpressure release");
 @(negedge clk);rx_valid=0;
 $display("M5_RULE_CASES=%0d ERRORS=%0d",cases,errors);
 if(errors==0)$display("M5_RULES_REPAIR_PASS");else $display("M5_RULES_REPAIR_FAIL");$finish;
end
initial begin #10000000;$display("M5_RULES_TIMEOUT");$finish;end
endmodule
