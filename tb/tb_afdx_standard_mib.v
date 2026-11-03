`timescale 1ns/1ps
module tb_afdx_standard_mib;
 reg clk=0,rst=1,request_valid=0,request_next=0,set_request=0;reg [7:0] request_index=0;reg [31:0] set_value=0;wire response_valid,response_error;wire [7:0] error_code,response_index,object_subid,asn1_type;wire [3:0] mib_group;wire [1:0] access_mode;wire table_object,index_required;wire [31:0] value32;integer errors=0,i;wire gate_valid,gate_accepted;wire [7:0] gate_error;wire [1:0] gate_model,gate_sec;
 always #5 clk=~clk;
 afdx_standard_mib_bank dut(.*);
 afdx_snmp_version_gate gate(.request_valid(1'b1),.version(8'd0),.pdu_kind(3'd0),.community_ok(1'b1),.usm_authenticated(1'b0),.usm_privacy_ok(1'b0),.response_valid(gate_valid),.accepted(gate_accepted),.error_code(gate_error),.message_model(gate_model),.security_model(gate_sec));
 task get;input [7:0] idx;input nxt;begin @(negedge clk);request_index=idx;request_next=nxt;request_valid=1;@(negedge clk);request_valid=0;#1;end endtask
 initial begin
  repeat(3)@(negedge clk);rst=0;get(0,0);if(!response_valid||response_error||response_index!=1)errors=errors+1;
  for(i=1;i<64;i=i+1)begin get(i,1);if(!response_valid||response_error||response_index!=i+1)errors=errors+1;end
  get(64,1);if(!response_error||error_code!=2)errors=errors+1;
  get(1,0);set_request=1;@(negedge clk);request_valid=1;@(negedge clk);request_valid=0;#1;if(!response_error||error_code!=3)errors=errors+1;set_request=0;
  if(!gate_accepted||gate_model!=0||gate_sec!=1)errors=errors+1;
  if(errors==0)$display("TB_STANDARD_MIB_SNMP_VERSIONS_PASS");else $display("TB_STANDARD_MIB_SNMP_VERSIONS_FAIL errors=%0d",errors);$finish;end
endmodule
