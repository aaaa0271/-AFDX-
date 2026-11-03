`timescale 1ns/1ps
// Legacy command-level model only. This interface is NOT a 615A wire codec.
// Real control files and TFTP packets are handled by the network service.
module afdx_615a_process_engine #(
 parameter integer MAX_TARGETS=8,MAX_HEADERS=8,MAX_PARTS=8
)(
 input wire clk,input wire rst,
 input wire cmd_valid,input wire [2:0] cmd_operation,input wire [7:0] cmd_target,
 input wire [7:0] cmd_part,input wire [3:0] cmd_headers,input wire [3:0] cmd_targets,
 input wire [3:0] cmd_parts,input wire cmd_defer,input wire [7:0] cmd_error_code,
 input wire cmd_abort,input wire data_valid,input wire data_last,
 output wire cmd_ready,output reg response_valid,output reg [2:0] response_operation,
 output reg [3:0] response_status,output reg [7:0] response_reason,
 output reg [3:0] active_headers,output reg [3:0] active_targets,output reg [3:0] active_parts,
 output reg [7:0] active_target,output reg [7:0] active_part,
 output reg busy,output reg [31:0] accepted_count,completed_count,aborted_count,error_count
);
 localparam OP_INFORMATION=3'd0,OP_DOWNLOAD=3'd1,OP_ABORT=3'd2;
 localparam ST_NOT_ACCEPTED=4'd0,ST_ACCEPTED=4'd1,ST_COMPLETED=4'd2,ST_WAIT=4'd3,ST_ERROR=4'd4,ST_ABORTED=4'd5;
 localparam S_IDLE=2'd0,S_INFO=2'd1,S_DOWNLOAD=2'd2,S_WAIT=2'd3;
 reg [1:0] state; assign cmd_ready=!busy;
 always @(posedge clk) begin
  if(rst) begin state<=S_IDLE;response_valid<=0;response_operation<=0;response_status<=0;response_reason<=0;active_headers<=0;active_targets<=0;active_parts<=0;active_target<=0;active_part<=0;busy<=0;accepted_count<=0;completed_count<=0;aborted_count<=0;error_count<=0;end
  else begin
   response_valid<=0;
   if(cmd_abort && busy) begin response_valid<=1;response_operation<=OP_ABORT;response_status<=ST_ABORTED;response_reason<=8'hF0;state<=S_IDLE;busy<=0;aborted_count<=aborted_count+1'b1;end
   else if(busy) begin
    case(state)
     S_INFO: begin response_valid<=1;response_operation<=OP_INFORMATION;response_status<=ST_COMPLETED;response_reason<=0;state<=S_IDLE;busy<=0;completed_count<=completed_count+1'b1;end
     S_DOWNLOAD: begin
      if(cmd_error_code!=0) begin response_valid<=1;response_operation<=OP_DOWNLOAD;response_status<=ST_ERROR;response_reason<=cmd_error_code;state<=S_IDLE;busy<=0;error_count<=error_count+1'b1;end
      else if(cmd_defer) begin response_valid<=1;response_operation<=OP_DOWNLOAD;response_status<=ST_WAIT;response_reason<=8'h01;state<=S_WAIT;end
      else if(data_valid&&data_last) begin response_valid<=1;response_operation<=OP_DOWNLOAD;response_status<=ST_COMPLETED;response_reason<=0;state<=S_IDLE;busy<=0;completed_count<=completed_count+1'b1;end
     end
     S_WAIT: begin
      if(cmd_error_code!=0) begin response_valid<=1;response_operation<=OP_DOWNLOAD;response_status<=ST_ERROR;response_reason<=cmd_error_code;state<=S_IDLE;busy<=0;error_count<=error_count+1'b1;end
      else if(data_valid&&data_last) begin response_valid<=1;response_operation<=OP_DOWNLOAD;response_status<=ST_COMPLETED;response_reason<=0;state<=S_IDLE;busy<=0;completed_count<=completed_count+1'b1;end
     end
     default: begin state<=S_IDLE;busy<=0;end
    endcase
   end
   else if(cmd_valid) begin
    active_headers<=cmd_headers;active_targets<=cmd_targets;active_parts<=cmd_parts;active_target<=cmd_target;active_part<=cmd_part;
    if(cmd_headers==0||cmd_headers>MAX_HEADERS||cmd_targets==0||cmd_targets>MAX_TARGETS||cmd_parts==0||cmd_parts>MAX_PARTS) begin response_valid<=1;response_operation<=cmd_operation;response_status<=ST_NOT_ACCEPTED;response_reason<=8'h01;error_count<=error_count+1'b1;end
    else if(cmd_operation==OP_INFORMATION) begin response_valid<=1;response_operation<=cmd_operation;response_status<=ST_ACCEPTED;response_reason<=0;state<=S_INFO;busy<=1;accepted_count<=accepted_count+1'b1;end
    else if(cmd_operation==OP_DOWNLOAD) begin response_valid<=1;response_operation<=cmd_operation;response_status<=ST_ACCEPTED;response_reason<=0;state<=S_DOWNLOAD;busy<=1;accepted_count<=accepted_count+1'b1;end
    else begin response_valid<=1;response_operation<=cmd_operation;response_status<=ST_NOT_ACCEPTED;response_reason<=8'h02;error_count<=error_count+1'b1;end
   end
  end
 end
endmodule
