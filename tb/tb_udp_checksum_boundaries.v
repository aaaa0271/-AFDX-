`timescale 1ns/1ps
module tb_udp_checksum_boundaries;
reg clk=0;always #5 clk=~clk;reg rst=1;reg [7:0] sd=0;reg sv=0,ss=0,se=0,pr=1;reg [10:0] fl=0;
wire sr,done,good,ce,pv,ps,pe;wire [7:0] pd;wire [15:0] uc;wire structural;
reg [7:0] bytes[0:1513];integer errors=0,cases=0,n,i,j,bl,sum,chk,got_payload,cycles=0;
integer stalls=0,expected_payload;reg [31:0] sum_ref;
afdx_eth_ipv4_udp_parser dut(.clk(clk),.rst(rst),.s_data(sd),.s_valid(sv),.s_ready(sr),.s_sof(ss),.s_eof(se),.s_frame_length(fl),
.dst_mac(),.src_mac(),.ether_type(),.ip_total_length(),.ip_ttl(),.ip_protocol(),.ip_header_checksum(),.src_ip(),.dst_ip(),.udp_src_port(),.udp_dst_port(),.udp_length(),.udp_checksum(uc),
.payload_length(),.padding_length(),.afdx_sequence(),.meta_valid(),.payload_data(pd),.payload_valid(pv),.payload_ready(pr),.payload_sof(ps),.payload_eof(pe),.frame_done(done),.frame_valid(good),
.ether_type_error(),.ip_version_error(),.ip_ihl_error(),.ip_checksum_error(),.ip_protocol_error(),.ip_length_error(),.udp_length_error(),.udp_checksum_error(ce),.structure_error(structural));
task fail;input [639:0] why;begin errors=errors+1;$display("FAIL case=%0d n=%0d %0s",cases,n,why);if(errors>6)$finish;end endtask
function integer fold;input integer v;integer t;begin t=(v&65535)+(v>>16);t=(t&65535)+(t>>16);fold=t;end endfunction
always @(posedge clk)if(!rst&&pv&&pr)begin
 if(pd!==bytes[42+got_payload] || ps!==(got_payload==0) || pe!==(got_payload==n-1))fail("payload/stall handshake");
 got_payload=got_payload+1;
end
always @(negedge clk) begin cycles=cycles+1;pr=cycles%5!=0;end
task run_case;input integer length;input integer mode; // 0 valid,1 corrupt checksum,2 disabled,3 payload corruption,4 pseudoheader source change
 integer x,t;begin
 n=length;cases=cases+1;got_payload=0;bl=n<=17?60:n+43;
 for(x=0;x<bl;x=x+1)bytes[x]=0;
 bytes[0]=2;bytes[5]=2;bytes[6]=2;bytes[11]=1;bytes[12]=8;
 bytes[14]=8'h45;bytes[16]=(n+28)>>8;bytes[17]=n+28;bytes[22]=64;bytes[23]=17;
 bytes[26]=10;bytes[29]=1;bytes[30]=10;bytes[33]=2;
 bytes[34]=8'h27;bytes[35]=8'h10;bytes[36]=8'h27;bytes[37]=8'h11;
 bytes[38]=(n+8)>>8;bytes[39]=n+8;
 for(x=0;x<n;x=x+1)bytes[42+x]=(x*31+n*3)&255;
 bytes[bl-1]=8'h81;
 // Independent UDP reference, using datagram bytes plus IPv4 pseudoheader.
 sum=0;for(x=26;x<34;x=x+2)sum=sum+{bytes[x],bytes[x+1]};sum=sum+17+n+8;
 for(x=34;x<42+n;x=x+2)begin
  sum=sum+(bytes[x]<<8);if(x+1<42+n)sum=sum+bytes[x+1];
 end
 chk=65535-fold(sum);if(chk==0)chk=65535;
 if(mode==1)chk=chk^1;
 if(mode==2)chk=0;
 bytes[40]=chk>>8;bytes[41]=chk;
 if(mode==3)bytes[42+n/2]=bytes[42+n/2]^8'h10;
 if(mode==4)bytes[29]=2; // Keep IP checksum valid, but invalidate UDP pseudoheader.
 sum=0;for(x=14;x<34;x=x+2)sum=sum+{bytes[x],bytes[x+1]};chk=65535-fold(sum);bytes[24]=chk>>8;bytes[25]=chk;
 for(x=0;x<bl;x=x+1)begin
  @(negedge clk);sv=1;ss=x==0;se=x==bl-1;fl=bl;sd=bytes[x];
  begin:wait_ready
   for(t=0;t<100;t=t+1)begin @(posedge clk);if(sr)disable wait_ready;end
   fail("stalled forever");
  end
 end
 #1;
 if(!done||good!==((mode==0)||(mode==2))||ce!==((mode==1)||(mode==3)||(mode==4)))fail("checksum acceptance");
 if(got_payload!=n)fail("internal payload length");
 @(negedge clk);sv=0;ss=0;se=0;repeat(2)@(negedge clk);
end endtask
initial begin
 repeat(4)@(negedge clk);rst=0;
 for(i=1;i<=19;i=i+1)for(j=0;j<5;j=j+1)run_case(i,j);
 run_case(96,0);run_case(97,0);run_case(255,0);run_case(256,0);run_case(1470,0);run_case(1471,0);run_case(1471,1);
 $display("UDP_CASES=%0d ERRORS=%0d",cases,errors);
 if(errors==0)$display("UDP_CHECKSUM_REPAIR_PASS");else $display("UDP_CHECKSUM_REPAIR_FAIL");$finish;
end
initial begin #500000;$display("UDP_CHECKSUM_TIMEOUT");$finish;end
endmodule
