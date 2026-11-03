`timescale 1ns/1ps
module tb_afdx_udp_checksum;
  reg clk=0; always #5 clk=~clk;
  reg rst=1; reg [7:0] s_data=0; reg s_valid=0, s_sof=0, s_eof=0; reg [10:0] s_frame_length=0; wire s_ready;
  wire [7:0] payload_data; wire payload_valid,payload_sof,payload_eof; wire meta_valid,frame_done,frame_valid;
  wire [47:0] dst_mac,src_mac; wire [15:0] ether_type,ip_header_checksum,udp_src_port,udp_dst_port,udp_length,udp_checksum;
  wire [31:0] src_ip,dst_ip; wire [15:0] ip_total_length; wire [7:0] ip_ttl,ip_protocol,afdx_sequence; wire [10:0] payload_length; wire [4:0] padding_length;
  wire ether_type_error,ip_version_error,ip_ihl_error,ip_checksum_error,ip_protocol_error,ip_length_error,udp_length_error,udp_checksum_error,structure_error;
  integer i, errors; reg [7:0] frame[0:59];
  afdx_eth_ipv4_udp_parser dut(.clk(clk),.rst(rst),.s_data(s_data),.s_valid(s_valid),.s_ready(s_ready),.s_sof(s_sof),.s_eof(s_eof),.s_frame_length(s_frame_length),
    .dst_mac(dst_mac),.src_mac(src_mac),.ether_type(ether_type),.ip_total_length(ip_total_length),.ip_ttl(ip_ttl),.ip_protocol(ip_protocol),.ip_header_checksum(ip_header_checksum),.src_ip(src_ip),.dst_ip(dst_ip),
    .udp_src_port(udp_src_port),.udp_dst_port(udp_dst_port),.udp_length(udp_length),.udp_checksum(udp_checksum),.payload_length(payload_length),.padding_length(padding_length),.afdx_sequence(afdx_sequence),.meta_valid(meta_valid),
    .payload_data(payload_data),.payload_valid(payload_valid),.payload_ready(1'b1),.payload_sof(payload_sof),.payload_eof(payload_eof),.frame_done(frame_done),.frame_valid(frame_valid),
    .ether_type_error(ether_type_error),.ip_version_error(ip_version_error),.ip_ihl_error(ip_ihl_error),.ip_checksum_error(ip_checksum_error),.ip_protocol_error(ip_protocol_error),.ip_length_error(ip_length_error),.udp_length_error(udp_length_error),.udp_checksum_error(udp_checksum_error),.structure_error(structure_error));
  task build_frame; input [15:0] chk; begin
    for(i=0;i<60;i=i+1) frame[i]=0;
    frame[0]=8'h02; frame[5]=8'h02; frame[6]=8'h02; frame[11]=8'h01; frame[12]=8'h08; frame[13]=8'h00;
    frame[14]=8'h45; frame[16]=8'h00; frame[17]=8'h20; frame[22]=8'h40; frame[23]=8'h11; frame[24]=8'h66; frame[25]=8'hcb;
    frame[26]=8'h0a; frame[29]=8'h01; frame[30]=8'h0a; frame[33]=8'h02;
    frame[34]=8'h27; frame[35]=8'h10; frame[36]=8'h27; frame[37]=8'h11; frame[38]=8'h00; frame[39]=8'h0c; frame[40]=chk[15:8]; frame[41]=chk[7:0];
    frame[42]=8'hde; frame[43]=8'had; frame[44]=8'hbe; frame[45]=8'hef; frame[59]=8'h01;
  end endtask
  task run_one; input [15:0] chk; input expect_valid; begin
    build_frame(chk); @(negedge clk); s_frame_length=60; s_valid=1; s_sof=1; s_eof=0; s_data=frame[0];
    for(i=0;i<60;i=i+1) begin
      if(i>0) begin @(negedge clk); s_sof=0; s_data=frame[i]; s_eof=(i==59); end
      @(posedge clk); #1;
    end
    @(negedge clk); s_valid=0; s_sof=0; s_eof=0; s_data=0; #1;
    $display("DBG sum=%08h fold=%04h udp=%04h src=%04h dst=%04h len=%04h",dut.udp_sum,dut.udp_final_folded,udp_checksum,udp_src_port,udp_dst_port,udp_length);
    if(frame_done!==1'b1 || frame_valid!==expect_valid || udp_checksum_error!==(expect_valid?1'b0:1'b1)) begin
      $display("FAIL checksum=%04h done=%b valid=%b err=%b struct=%b",chk,frame_done,frame_valid,udp_checksum_error,structure_error); errors=errors+1;
    end else $display("UDP-CHECKSUM %04h PASS valid=%b",chk,expect_valid);
  end endtask
  initial begin errors=0; #20; rst=0; run_one(16'h0015,1'b1); run_one(16'h0014,1'b0); if(errors==0) $display("M3 UDP CHECKSUM PASS"); else $display("M3 UDP CHECKSUM FAIL errors=%0d",errors); $finish; end
endmodule
