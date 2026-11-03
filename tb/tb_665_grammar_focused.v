`timescale 1ns/1ps
module tb_665_grammar_focused;
parameter integer PATH_MODE=0;
reg clk=0;always #5 clk=~clk;
reg rst=1,start=0;reg [15:0] header_length=0,udd_read_address=0;
reg [5:0] hardware_length=4;reg [255:0] hardware_id=256'h30574854;
wire [15:0] read_address,udd_address,udd_length,format_version,part_flags,load_type_id;
wire [7:0] udd_read_data,error_code;wire done,error;
wire [2:0] file_count,data_file_count,support_file_count;
wire [3:0] support_mask;wire [1023:0] names;wire [23:0] name_lengths;
wire [63:0] file_lengths,file_crcs;wire [31:0] load_crc_state,expected_load_crc;
reg [7:0] memory[0:65535];integer base=0,errors=0,total=0,t,k;
 afdx_665_header #(.MAX_FILES(4),.ALLOW_RELATIVE_PATHS(PATH_MODE)) dut(
 .clk(clk),.rst(rst),.start(start),.header_length(header_length),.read_address(read_address),.read_data(memory[base+read_address]),
 .hardware_length(hardware_length),.hardware_id(hardware_id),.done(done),.error(error),.error_code(error_code),
 .file_count(file_count),.names(names),.name_lengths(name_lengths),.file_lengths(file_lengths),.file_crcs(file_crcs),
 .load_crc_state(load_crc_state),.expected_load_crc(expected_load_crc),.data_file_count(data_file_count),
 .support_file_count(support_file_count),.support_mask(support_mask),.udd_address(udd_address),.udd_length(udd_length),
 .format_version(format_version),.part_flags(part_flags),.load_type_id(load_type_id),.udd_read_address(udd_read_address),.udd_read_data(udd_read_data));
task run_case;
 input integer id,offset,size,expected_flat,expected_path,nd,ns,udlen;
 input [1023:0] want_names;input [23:0] want_nlens;input [63:0] want_lens,want_crcs;
 input [31:0] want_seed,want_crc;input [15:0] want_type;
 integer expected;begin
 expected=PATH_MODE?expected_path:expected_flat;
 @(negedge clk);base=offset;header_length=size;hardware_length=4;hardware_id=256'h30574854;start=1;
 @(negedge clk);start=0;
 // Caller mutation after acceptance must not alter THW matching.
 hardware_length=1;hardware_id=256'hff;
 t=0;while(!done&&t<20000)begin @(negedge clk);t=t+1;end
 if(!done||error!==(expected!=0)||error_code!==expected)begin
  errors=errors+1;$display("FAIL case=%0d error=%h expected=%h",id,error_code,expected);end
 if(expected==0)begin
  if(file_count!==nd+ns||data_file_count!==nd||support_file_count!==ns||udd_length!==udlen||
     names!==want_names||name_lengths!==want_nlens||file_lengths!==want_lens||file_crcs!==want_crcs||
     support_mask!==(((1<<ns)-1)<<nd)||load_crc_state!==want_seed||expected_load_crc!==want_crc||
     load_type_id!==want_type||format_version!=={memory[offset+4],memory[offset+5]})begin
   errors=errors+1;$display("FAIL metadata case=%0d count=%0d/%0d/%0d lens=%h names=%h seed=%h",id,file_count,data_file_count,support_file_count,file_lengths,names,load_crc_state);
  end
  for(k=0;k<udlen;k=k+1)begin udd_read_address=k;#1;if(udd_read_data!==memory[offset+udd_address+k])errors=errors+1;end
  udd_read_address=udlen;#1;if(udd_read_data!==0)errors=errors+1;
 end else if(file_count!==0||names!==0||file_lengths!==0||file_crcs!==0||support_mask!==0||
     data_file_count!==0||support_file_count!==0||udd_length!==0||load_crc_state!==0||expected_load_crc!==0)begin
  errors=errors+1;$display("FAIL stale result case=%0d",id);end
 total=total+1;$display("GRAMMAR_CASE id=%0d code=%0d cycles=%0d",id,error_code,t);
 @(negedge clk);if(done)begin errors=errors+1;$display("FAIL sticky done");end
 end
endtask
initial begin
 $readmemh("grammar.hex",memory);
 repeat(4)@(negedge clk);rst=0;
 `include "grammar.vh"
 if(errors==0)$display("TB_665_GRAMMAR_FOCUSED_PASS cases=%0d paths=%0d",total,PATH_MODE);
 else $fatal(1,"TB_665_GRAMMAR_FOCUSED_FAIL errors=%0d",errors);
 $finish;
end
initial begin #20000000;$fatal(1,"grammar watchdog");end
endmodule
