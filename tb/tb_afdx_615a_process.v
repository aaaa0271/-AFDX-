`timescale 1ns/1ps
module tb_afdx_615a_process;
 reg clk=0,rst=1,cmd_valid=0,cmd_defer=0,cmd_abort=0,data_valid=0,data_last=0;reg [2:0] cmd_operation=0;reg [7:0] cmd_target=0,cmd_part=0,cmd_error_code=0;reg [3:0] cmd_headers=0,cmd_targets=0,cmd_parts=0;
 wire cmd_ready,response_valid,busy;wire [2:0] response_operation;wire [3:0] response_status,active_headers,active_targets,active_parts;wire [7:0] response_reason,active_target,active_part;wire [31:0] accepted_count,completed_count,aborted_count,error_count;integer errors=0;
 always #5 clk=~clk;
 afdx_615a_process_engine dut(.*);
 task pulse_cmd; input [2:0] op;input [3:0] h,t,p; begin @(negedge clk);cmd_operation=op;cmd_headers=h;cmd_targets=t;cmd_parts=p;cmd_valid=1;@(negedge clk);cmd_valid=0;end endtask
 initial begin
  repeat(3)@(negedge clk);rst=0;
  pulse_cmd(0,2,2,2);#1;if(!response_valid||response_status!=1||!busy) errors=errors+1;@(negedge clk);#1;if(!response_valid||response_status!=2||busy)errors=errors+1;
  pulse_cmd(1,3,2,2);#1;if(!response_valid||response_status!=1)errors=errors+1;@(negedge clk);data_valid=1;data_last=1;@(negedge clk);data_valid=0;data_last=0;#1;if(!response_valid||response_status!=2)errors=errors+1;
  pulse_cmd(1,2,1,1);#1;cmd_defer=1;@(negedge clk);cmd_defer=0;#1;if(!response_valid||response_status!=3)errors=errors+1;@(negedge clk);data_valid=1;data_last=1;@(negedge clk);data_valid=0;data_last=0;#1;if(!response_valid||response_status!=2)errors=errors+1;
  pulse_cmd(1,1,1,1);#1;cmd_abort=1;@(negedge clk);cmd_abort=0;#1;if(!response_valid||response_status!=5)errors=errors+1;
  pulse_cmd(1,0,1,1);#1;if(!response_valid||response_status!=0) errors=errors+1;
  if(errors==0) $display("TB_615A_PROCESS_PASS"); else $display("TB_615A_PROCESS_FAIL errors=%0d",errors);$finish;
 end
endmodule
