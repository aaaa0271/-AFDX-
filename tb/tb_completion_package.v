`timescale 1ns/1ps
module tb_completion_package;
reg clk=0;always #5 clk=~clk;reg rst=1,start=0,abort=0,rx=0;
reg [31:0] rip=32'h0a000001;reg [15:0] rsp=30000,rdp=42000;reg [10:0] rlen=0;reg [4127:0] rb=0;
wire tv,busy,done,error,valid;wire [7:0] code,ad;wire [10:0] tlen;wire [4127:0] tb;wire [31:0] tip,generation;wire [15:0] tsp,tdp,alen;wire [2:0] files,activefile;wire [255:0] aname;
reg [1:0] afile=0;reg [15:0] addr=0;
integer errors=0,mode=0,current_file=0,current_length=0,offset=0,block_number=0,k,t,rrq_count=0;
reg [7:0] header[0:125],a[0:699],b[0:1023];reg pending=0;reg [4127:0] pb;reg [10:0] pl;
afdx_665_package_loader #(.TIMEOUT_CYCLES(100)) dut(.commit_authorize(1'b0),.prepared(),.clk(clk),.rst(rst),.start(start),.abort(abort),.server_ip(32'h0a000001),.header_name_length(6'd7),.header_name({200'd0,56'h48554c2e505041}),
.hardware_length(6'd3),.hardware_id({232'd0,24'h4d4953}),.tx_valid(tv),.tx_ready(1'b1),.tx_length(tlen),.tx_bytes(tb),.tx_ip(tip),.tx_sport(tsp),.tx_dport(tdp),
.rx_valid(rx),.rx_ip(rip),.rx_sport(rsp),.rx_dport(rdp),.rx_length(rlen),.rx_bytes(rb),
.busy(busy),.done(done),.error(error),.error_code(code),.package_valid(valid),.generation(generation),.package_crc(),.loaded_file_count(files),
.app_file(afile),.app_address(addr),.app_data(ad),.app_length(alen),.app_name(aname),.active_file(activefile));
task fail;input [511:0] why;begin errors=errors+1;$display("FAIL PACKAGE mode=%0d code=%h %0s",mode,code,why);if(errors>8)$finish;end endtask
function [7:0] byte_at;input integer which,pos;begin
 case(which)0:byte_at=header[pos];1:byte_at=a[pos];default:byte_at=b[pos];endcase
 if(mode==1&&which==2&&pos==11)byte_at=byte_at^1;
 if(mode==2&&which==0&&pos==45)byte_at=byte_at^1;
 if(mode==3&&which==0&&pos==125)byte_at=byte_at^1;
end endfunction
task reply;integer n,j;begin
 n=current_length-offset;if(n>512)n=512;
 pb=0;pb[15:8]=3;pb[23:16]=block_number>>8;pb[31:24]=block_number;
 for(j=0;j<n;j=j+1)pb[(j+4)*8+:8]=byte_at(current_file,offset+j);
 pl=n+4;pending=1;
end endtask
always @(posedge clk)if(!rst&&tv)begin
 if(tb[15:8]==1)begin
  rrq_count=rrq_count+1;rdp=tsp;
  if(tb[2*8+:56]==56'h48554c2e505041)begin current_file=0;current_length=126;end
  else if(tb[2*8+:40]==40'h50554c2e41)begin current_file=1;current_length=700;end
  else if(tb[2*8+:40]==40'h50554c2e42)begin current_file=2;current_length=1024;end
  else fail("unknown requested file");
  offset=0;block_number=1;reply;
 end else if(tb[15:8]==4)begin
  if(pl==516)begin offset=offset+512;block_number=block_number+1;reply;end
 end else fail("unexpected TFTP opcode");
end
always @(negedge clk)begin rx=0;if(pending)begin rb=pb;rlen=pl;rx=1;pending=0;end end
task run;input integer m;input integer want_code;begin
 mode=m;@(negedge clk);start=1;@(negedge clk);start=0;t=0;
 while(!done&&t<15000)begin @(negedge clk);t=t+1;end
 if(!done||error!==(m!=0)||code!==want_code)fail("transaction result");
 if(generation!=1||!valid||files!=2)fail("atomic preservation/commit");
 for(k=0;k<1724;k=k+1)begin
  afile=k<700?0:1;addr=k<700?k:k-700;#1;
  if(ad!==(k<700?a[k]:b[k-700]))fail("application bank contents");
 end
 repeat(6)@(negedge clk);
end endtask
initial begin
 $readmemh("APP.LUH.hex",header);
 $readmemh("A.LUP.hex",a);
 $readmemh("B.LUP.hex",b);
 repeat(4)@(negedge clk);rst=0;run(0,0);run(1,8'h83);run(2,3);run(3,8'h84);
 $display("PACKAGE_FILES=%0d GENERATION=%0d RRQS=%0d ERRORS=%0d",files,generation,rrq_count,errors);
 if(errors==0)$display("TB_COMPLETION_PACKAGE_PASS");else $display("TB_COMPLETION_PACKAGE_FAIL");$finish;
end
initial begin #1000000;$display("PACKAGE_TIMEOUT");$finish;end
endmodule
