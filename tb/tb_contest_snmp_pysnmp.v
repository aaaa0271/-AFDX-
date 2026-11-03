`timescale 1ns/1ps
module tb_contest_snmp_pysnmp;
localparam MAX_MSG_BYTES=128,MAX_VB_BYTES=64,MAX_RESPONSE_BYTES=96;
reg clk=0;always #5 clk=~clk;reg rst_n=0,req=0,fault=0,net_a=0;
reg [31:0] rx_count=0,tx_count=0;reg [7:0] msg_length=0;reg [1023:0] msg_bytes=0;
wire response_done,response_valid,response_error;wire [7:0] response_error_code,response_length;wire [767:0] response_bytes;
integer errors=0,cases=0,j,t;
    afdx_m6d_integration #(
        .MAX_MSG_BYTES(MAX_MSG_BYTES), .MAX_VB_BYTES(MAX_VB_BYTES),
        .MAX_RESPONSE_BYTES(MAX_RESPONSE_BYTES), .CLK_HZ(1000)
    ) dut (
        .clk(clk), .rst_n(rst_n), .req(req), .msg_length(msg_length), .msg_bytes(msg_bytes),
        .response_done(response_done), .response_valid(response_valid),
        .response_error(response_error), .response_error_code(response_error_code),
        .response_length(response_length), .response_bytes(response_bytes),
        .m5_network_a_enable(net_a), .m5_network_b_enable(1'b0), .m5_degraded_mode(1'b0),
        .m5_redundancy_ok(1'b0), .m5_frame_count_match(1'b0),
        .m5_active_byte_count_match(1'b0), .m5_fault_applied_event(fault),
        .m5_rx_accepted_count(rx_count), .m5_rx_accepted_a_count(32'd0),
        .m5_rx_accepted_b_count(32'd0), .m5_rx_duplicate_count(32'd0),
        .m5_rx_cross_network_duplicate_count(32'd0), .m5_rx_same_network_repeat_count(32'd0),
        .m5_rx_stale_count(32'd0), .m5_rx_sequence_gap_count(32'd0),
        .m5_tx_a_frame_count(tx_count), .m5_tx_b_frame_count(32'd0),
        .m5_tx_a_active_byte_count(32'd0), .m5_tx_b_active_byte_count(32'd0),
        .m5_tx_byte_mismatch_count(32'd0), .m5_tx_frame_skew_cycle_count(32'd0),
        .m5_tx_frame_done_skew_count(32'd0), .m5_tx_er_mismatch_count(32'd0),
        .m5_tx_a_error_cycle_count(32'd0), .m5_tx_b_error_cycle_count(32'd0),
        .m5_tx_a_underrun_count(32'd0), .m5_tx_b_underrun_count(32'd0)
    );


task query;input [1023:0] bytes;input integer len;begin
 @(negedge clk);msg_bytes=bytes;msg_length=len;req=1;@(negedge clk);req=0;t=0;
 while(!response_done&&t<300)begin @(negedge clk);t=t+1;end
 if(!response_done||!response_valid||response_error)begin errors=errors+1;$display("FAIL third-party request case=%0d",cases);end
 $write("PYSNMP_RESPONSE case=%0d hex=",cases);for(j=0;j<response_length;j=j+1)$write("%02x",response_bytes[767-j*8-:8]);$display("");
 cases=cases+1;repeat(3)@(negedge clk);
end endtask
initial begin repeat(4)@(negedge clk);rst_n=1;
query(1024'h000501010159fd81010401062b0b060f3011300001020001020101021ca063696c62757006040101022930,43);
query(1024'h00050e010159fd81010401062b0b060f30000506010159fd81010401062b0b060f302230000102000102800002022ea063696c62757006040101023b30,61);
query(1024'h000559fd81010401062b08060c300e300001020001027fff02021aa163696c62757006040101022730,41);
query(1024'h000505010159fd81010401062b0b060f3011300001020001020000800004021fa163696c62757006040101022c30,46);
query(1024'h00051a010159fd81010401062b0b060f3011300001020001027f01021ca063696c62757006040101022930,43);
query(1024'h000519010159fd81010401062b0b060f301130000102000102ff01021ca163696c62757006040101022930,43);
if(errors==0)$display("TB_CONTEST_SNMP_PYSNMP_PASS");else $display("TB_CONTEST_SNMP_PYSNMP_FAIL");$finish;end
initial begin #200000;$display("SNMP_TIMEOUT");$finish;end
endmodule
