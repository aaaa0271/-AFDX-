`timescale 1ns/1ps
// Standalone policy evidence for the version/security admission gate.
// This is deliberately not a wire-engine test: it proves only the declared
// admission matrix and keeps v1/v2c/v3 implementation claims separate.
module tb_afdx_snmp_wire_policy;
 reg request_valid;
 reg [7:0] version;
 reg [2:0] pdu_kind;
 reg community_ok,usm_authenticated,usm_privacy_ok;
 wire response_valid,accepted;
 wire [7:0] error_code;
 wire [1:0] message_model,security_model;
 integer errors=0,cases=0;

 afdx_snmp_version_gate dut(
  .request_valid(request_valid),.version(version),.pdu_kind(pdu_kind),
  .community_ok(community_ok),.usm_authenticated(usm_authenticated),
  .usm_privacy_ok(usm_privacy_ok),.response_valid(response_valid),
  .accepted(accepted),.error_code(error_code),.message_model(message_model),
  .security_model(security_model));

 task check;
  input [255:0] name;
  input [7:0] v;
  input [2:0] pdu;
  input comm,auth,priv;
  input exp_accept;
  input [7:0] exp_error;
  input [1:0] exp_model,exp_sec;
  begin
   version=v;pdu_kind=pdu;community_ok=comm;usm_authenticated=auth;usm_privacy_ok=priv;request_valid=1'b1;#1;
   cases=cases+1;
   $display("SNMP_GATE_CASE name=%0s version=%0d pdu=%0d community=%0d auth=%0d priv=%0d accepted=%0d error=%0d model=%0d security=%0d",name,v,pdu,comm,auth,priv,accepted,error_code,message_model,security_model);
   if(!response_valid||accepted!==exp_accept||error_code!==exp_error||message_model!==exp_model||security_model!==exp_sec) begin
    errors=errors+1;$display("SNMP_GATE_MISMATCH name=%0s",name);
   end
   request_valid=1'b0;#1;
   if(response_valid)begin errors=errors+1;$display("SNMP_GATE_RESPONSE_STUCK name=%0s",name);end
  end
 endtask

 initial begin
  request_valid=0;version=0;pdu_kind=0;community_ok=0;usm_authenticated=0;usm_privacy_ok=0;#1;
  check("v1_get",8'd0,3'd0,1,0,0,1,8'h00,0,1);
  check("v1_set",8'd0,3'd3,1,0,0,1,8'h00,0,1);
  check("v1_bad_community",8'd0,3'd0,0,0,0,0,8'h01,0,1);
  check("v1_bad_pdu",8'd0,3'd4,1,0,0,0,8'h01,0,1);
  check("v2c_get",8'd1,3'd0,1,0,0,1,8'h00,1,2);
  check("v2c_bulk",8'd1,3'd5,1,0,0,1,8'h00,1,2);
  check("v2c_bad_community",8'd1,3'd0,0,0,0,0,8'h02,1,2);
  check("v2c_bad_pdu",8'd1,3'd6,1,0,0,0,8'h02,1,2);
  check("v3_auth_priv",8'd3,3'd0,0,1,1,1,8'h00,3,3);
  check("v3_auth_priv_bulk",8'd3,3'd5,0,1,1,1,8'h00,3,3);
  check("v3_no_auth",8'd3,3'd0,0,0,1,0,8'h03,3,3);
  check("v3_no_priv",8'd3,3'd0,0,1,0,0,8'h03,3,3);
  check("v3_bad_pdu",8'd3,3'd6,0,1,1,0,8'h03,3,3);
  check("unknown_v2",8'd2,3'd0,1,0,0,0,8'h04,0,0);
  check("unknown_255",8'd255,3'd0,1,0,0,0,8'h04,0,0);
  if(errors==0)$display("SNMP_WIRE_POLICY_MATRIX_PASS cases=%0d",cases);else $display("SNMP_WIRE_POLICY_MATRIX_FAIL cases=%0d errors=%0d",cases,errors);
  $finish;
 end
endmodule
