`timescale 1ns/1ps
module tb_665_header_compat;
reg clk=0;always #5 clk=~clk;reg rst=1,start=0;reg [15:0] length=0;
wire [15:0] address;wire done,error;wire [7:0] code;wire [2:0] count;
wire [1023:0] names;wire [23:0] name_lengths;wire [63:0] lengths,crcs;
reg [7:0] memory[0:4095];integer base=0,errors=0,total=0,t;
afdx_665_header dut(.clk(clk),.rst(rst),.start(start),.header_length(length),.read_address(address),.read_data(memory[base+address]),
 .hardware_length(6'd3),.hardware_id({232'd0,24'h4d4953}),.done(done),.error(error),.error_code(code),.file_count(count),
 .names(names),.name_lengths(name_lengths),.file_lengths(lengths),.file_crcs(crcs),.load_crc_state(),.expected_load_crc());
task run_case;input integer id,offset,size,expected;
 begin
  @(negedge clk);base=offset;length=size;start=1;@(negedge clk);start=0;t=0;
  while(!done&&t<10000)begin @(negedge clk);t=t+1;end
  if(!done||error!==(expected!=0)||code!==expected)begin errors=errors+1;$display("FAIL 665 id=%0d error=%h expected=%h",id,code,expected);end
  if(expected==0)begin
   if(count!==2||lengths[15:0]!==700||lengths[31:16]!==1024||crcs[15:0]!==10138||crcs[31:16]!==15455)errors=errors+1;
   if(names[39:0]!==40'h50554c2e41||names[256+:40]!==40'h50554c2e42)errors=errors+1;
  end else if(count!==0)errors=errors+1;
  total=total+1;$display("COMPAT665_CASE id=%0d result=%0d expected=%0d",id,code,expected);
  repeat(2)@(negedge clk);
 end
endtask
initial begin
 $readmemh("compat665.hex",memory);
 repeat(4)@(negedge clk);rst=0;
 `include "compat665.vh"
 if(errors==0)$display("TB_665_HEADER_COMPAT_PASS");else $display("TB_665_HEADER_COMPAT_FAIL");$finish;
end
initial begin #2000000;errors=errors+1;$display("FAIL 665 watchdog");$finish;end
endmodule
