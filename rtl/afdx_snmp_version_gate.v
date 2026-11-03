`timescale 1ns/1ps
// SNMP message-version admission and PDU policy. v1 and v2c are accepted in
// community mode; v3 is accepted only when the USM/auth/priv policy is met.
module afdx_snmp_version_gate(
 input wire request_valid,input wire [7:0] version,input wire [2:0] pdu_kind,
 input wire community_ok,input wire usm_authenticated,input wire usm_privacy_ok,
 output reg response_valid,output reg accepted,output reg [7:0] error_code,
 output reg [1:0] message_model,output reg [1:0] security_model
);
 always @* begin
  response_valid=request_valid;accepted=0;error_code=0;message_model=0;security_model=0;
  if(request_valid) begin
   if(version==0) begin message_model=0;security_model=1;if(community_ok&&(pdu_kind<=3))accepted=1;else error_code=8'h01;end
   else if(version==1) begin message_model=1;security_model=2;if(community_ok&&(pdu_kind<=5))accepted=1;else error_code=8'h02;end
   else if(version==3) begin message_model=3;security_model=3;if(usm_authenticated&&usm_privacy_ok&&(pdu_kind<=5))accepted=1;else error_code=8'h03;end
   else error_code=8'h04;
  end
 end
endmodule
