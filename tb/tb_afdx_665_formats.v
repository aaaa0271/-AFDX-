`timescale 1ns/1ps
module tb_afdx_665_formats;
 reg clk=0,rst=1,start=0;reg [3:0] edition=5,header_count=2,target_count=2,part_count=2,support_count=1,udd_count=1;reg [15:0] format_id=16'h8002;reg header_crc_ok=1,file_crc_ok=1,load_crc_ok=1,reserved_zero=1,names_ok=1,duplicate_free=1;wire done,accepted,busy;wire [7:0] error_code;integer errors=0;
 always #5 clk=~clk; afdx_665_format_engine dut(.*);
 task run_case;input [3:0] ed;input [15:0] fmt;input [3:0] sup,udd;input [7:0] expected;begin edition=ed;format_id=fmt;support_count=sup;udd_count=udd;@(negedge clk);start=1;@(negedge clk);start=0;#1;if((expected==0&&(!accepted||error_code!=0))||(expected!=0&&(accepted||error_code!=expected)))errors=errors+1;end endtask
 initial begin
 repeat(3)@(negedge clk);rst=0;
 run_case(2,16'h8003,1,1,0);
 run_case(3,16'h8004,8,8,0);run_case(4,16'h8004,1,1,0);run_case(5,16'h8004,1,1,0);
 run_case(4,16'h8003,1,0,5);run_case(2,16'h8004,0,0,5);
 run_case(5,16'h8002,0,0,2);run_case(1,16'h8002,0,0,1);
 header_crc_ok=0;run_case(5,16'h8004,0,0,16);header_crc_ok=1;
 run_case(5,16'h8006,0,0,2);run_case(5,16'h9004,0,0,2);
 if(errors==0)$display("TB_665_FORMATS_PASS");else $display("TB_665_FORMATS_FAIL errors=%0d",errors);$finish;end
endmodule
