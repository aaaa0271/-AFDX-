`timescale 1ns/1ps
module tb_datagram_source_ids;
reg clk=0;always #40 clk=~clk;reg rst=1;
reg [7:0] ba=0,bb=0,md=0;reg av=0,bv=0,ae=0,be=0,mv=0;
wire admit;wire [7:0] a,b;wire aen,ben,aer,ber;wire [31:0] overflow,af,bf;
reg [7:0] raw[0:5000];reg [31:0] ac=32'hffffffff,bc=32'hffffffff;reg [47:0] sa=0,sb=0;
integer ai=0,bi=0,completed=0,case_id=0,errors=0,k,t;reg ap=0,bp=0,seen_ae=0,seen_be=0;
afdx_shared_tx_mux #(.REWRITE_SOURCE(1),.SOURCE_USER_ID(16'h1234)) dut(
.clk(clk),.rst(rst),.network_a_enable(1'b1),.network_b_enable(1'b1),.business_bags(128'd0),.business_macs(192'd0),
.business_a(ba),.business_b(bb),.business_a_en(av),.business_b_en(bv),.business_a_er(ae),.business_b_er(be),
.management_data(md),.management_en(mv),.management_er(1'b0),.service_data(8'd0),.service_en(1'b0),.service_er(1'b0),
.business_admit(admit),.management_admit(),.service_admit(),.a_data(a),.b_data(b),.a_en(aen),.b_en(ben),.a_er(aer),.b_er(ber),.a_done(),.b_done(),.overflow_count(overflow),.a_frames(af),.b_frames(bf));
function [31:0] crcbyte;input [31:0] c;input [7:0] x;reg [31:0] v;integer j;begin v=c^x;for(j=0;j<8;j=j+1)v=v[0]?(v>>1)^32'hedb88320:v>>1;crcbyte=v;end endfunction
task fail;input [511:0] why;begin errors=errors+1;$display("FAIL SOURCE_ID case=%0d %0s",case_id,why);end endtask
always @(negedge clk)if(!rst)begin
 if(aen)begin if(ai>=8)ac=crcbyte(ac,a);if(ai>=14&&ai<=19)sa={sa[39:0],a};ai=ai+1;if(aer)seen_ae=1;end
 else if(ap)begin
  if(sa!==48'h020000123420||ai!=72)fail("A source interface or frame length");
  if((ac==32'hdebb20e3)!==(case_id!=2&&case_id!=5))fail("A FCS was repaired or broken");
  if(seen_ae!==(case_id==4))fail("A error isolation");
 end
 if(ben)begin if(bi>=8)bc=crcbyte(bc,b);if(bi>=14&&bi<=19)sb={sb[39:0],b};bi=bi+1;if(ber)seen_be=1;end
 else if(bp)begin
  if(sb!==48'h020000123440||bi!=72)fail("B source interface or frame length");
  if((bc==32'hdebb20e3)!==(case_id!=1&&case_id!=5))fail("B FCS was repaired or broken");
  if(seen_be!==(case_id==3))fail("B error isolation");completed=completed+1;
 end
 ap=aen;bp=ben;
end
initial begin
 $readmemh("port_frames.hex",raw);
 for(case_id=0;case_id<6;case_id=case_id+1)begin
  @(posedge clk);#1;rst=1;av=0;bv=0;mv=0;repeat(4)@(posedge clk);#1;ai=0;bi=0;ap=0;bp=0;seen_ae=0;seen_be=0;ac=32'hffffffff;bc=32'hffffffff;sa=0;sb=0;completed=0;rst=0;
  for(k=0;k<72;k=k+1)begin
   @(posedge clk);#1;av=case_id!=5;bv=case_id!=5;mv=case_id==5;
   ba=raw[k]^((case_id==2&&k==55)?8'h01:8'h00);bb=raw[k]^((case_id==1&&k==55)?8'h01:8'h00);md=raw[k]^((case_id==5&&k==71)?8'h01:8'h00);
   ae=case_id==4&&k==30;be=case_id==3&&k==30;
  end
  @(posedge clk);#1;av=0;bv=0;mv=0;ae=0;be=0;t=0;
  while(completed==0&&t<1000)begin @(posedge clk);#1;t=t+1;end
  repeat(10)@(posedge clk);#1;if(completed!=1||af!=1||bf!=1||overflow!=0)fail("frame/overflow counts");
  $display("SOURCE_INTERFACE_CASE=%0d ERRORS=%0d",case_id,errors);
 end
 if(errors==0)$display("TB_DATAGRAM_SOURCE_IDS_PASS");else $display("TB_DATAGRAM_SOURCE_IDS_FAIL");$finish;
end
initial begin #10000000;$display("SOURCE_INTERFACE_TIMEOUT");$finish;end
endmodule