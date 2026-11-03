`timescale 1ns/1ps
module tb_665_package_support #(parameter integer VERSION=4);
localparam HEADER_LENGTH=VERSION==3?138:166;
reg clk=0;always #5 clk=~clk;reg rst=1,start=0,commit=0,abort=0,rx=0;
reg [15:0] rdp=42000;reg [10:0] rlen=0;reg [4127:0] rb=0;
wire tv,busy,done,error,valid,prepared;wire [7:0] code,ad;wire [10:0] tlen;wire [4127:0] tx;
wire [31:0] generation;wire [15:0] tsp,alen;wire [2:0] files;wire [3:0] support_mask;
reg [1:0] afile=0;reg [15:0] addr=0;
integer errors=0,mode=0,current_file=0,current_length=0,j,t,rrqs=0;
reg [7:0] header[0:165];reg pending=0;reg [4127:0] pb=0;reg [10:0] pl=0;
afdx_665_package_loader #(.TIMEOUT_CYCLES(100),.DEFER_COMMIT(1)) dut(
 .clk(clk),.rst(rst),.start(start),.abort(abort),.commit_authorize(commit),.prepared(prepared),
 .server_ip(32'h0a000001),.header_name_length(6'd7),.header_name(256'h48554c2e505041),
 .hardware_length(6'd4),.hardware_id(256'h30574854),.tx_valid(tv),.tx_ready(1'b1),.tx_length(tlen),.tx_bytes(tx),.tx_ip(),.tx_sport(tsp),.tx_dport(),
 .rx_valid(rx),.rx_ip(32'h0a000001),.rx_sport(16'd30000),.rx_dport(rdp),.rx_length(rlen),.rx_bytes(rb),
 .busy(busy),.idle(),.done(done),.error(error),.error_code(code),.package_valid(valid),.generation(generation),.package_crc(),.loaded_file_count(files),
 .app_file(afile),.app_address(addr),.app_data(ad),.app_length(alen),.app_name(),.active_file(),.loaded_support_mask(support_mask),.waiting(),.remote_abort(),.abort_status());
function [7:0] payload;input integer file_id,n;begin
 case(file_id)
  0:payload=header[n];1:payload="A"+n;
  2:case(n)0:payload="h";1:payload="e";2,3:payload="l";default:payload="o";endcase
  default:payload=0;
 endcase
 if(mode==1&&file_id==2&&n==1)payload=payload^1;
end endfunction
task fail;input [511:0] why;begin errors=errors+1;$display("FAIL SUPPORT version=%0d mode=%0d code=%h %0s",VERSION,mode,code,why);end endtask
always @(posedge clk)if(!rst&&tv&&tx[15:8]==1)begin
 rrqs=rrqs+1;rdp=tsp;
 if(tx[16+:56]==56'h48554c2e505041)begin current_file=0;current_length=HEADER_LENGTH;end
 else if(tx[16+:40]==40'h50554c2e41)begin current_file=1;current_length=3;end
 else if(tx[16+:40]==40'h5458542e53)begin current_file=2;current_length=5;end
 else if(tx[16+:72]==72'h5458542e5954504d45)begin current_file=3;current_length=0;end
 else begin fail("unexpected RRQ");current_file=0;current_length=0;end
 pb=0;pb[15:8]=3;pb[31:24]=1;
 for(j=0;j<current_length;j=j+1)pb[(4+j)*8+:8]=payload(current_file,j);
 pl=current_length+4;pending=1;
end
always @(negedge clk)begin rx=0;if(pending)begin rb=pb;rlen=pl;rx=1;pending=0;end end
task read_bank;integer f,n;begin
 for(f=0;f<3;f=f+1)begin
  afile=f;#1;if(alen!==(f==0?3:f==1?5:0))fail("published length");
  for(n=0;n<alen;n=n+1)begin addr=n;#1;
   if(f==0&&ad!==8'h41+n)fail("data bytes");
   if(f==1&&ad!==((n==0)?8'h68:(n==1)?8'h65:(n<4)?8'h6c:8'h6f))fail("support bytes");
  end
 end
 afile=3;addr=0;#1;if(alen!==0||ad!==0)fail("invalid file view");
end endtask
task run;input integer corrupt;begin
 mode=corrupt;@(negedge clk);start=1;@(negedge clk);start=0;t=0;
 while(!done&&t<5000)begin @(negedge clk);t=t+1;end
 if(!done)fail("completion deadline");
 if(!corrupt)begin
  if(error||valid||!prepared||generation!=0)fail("publish before authorization");
  repeat(5)@(negedge clk);commit=1;@(negedge clk);commit=0;@(negedge clk);
  if(!valid||generation!=1||files!=3||support_mask!=6)fail("atomic commit metadata");
 end else if(!error||code!=8'h83||generation!=1||!valid||prepared)fail("support CRC rollback");
 read_bank;repeat(5)@(negedge clk);
end endtask
initial begin
 if(VERSION==3)$readmemh("package_8003.hex",header,0,HEADER_LENGTH-1);
 else $readmemh("package_8004.hex",header,0,HEADER_LENGTH-1);
 repeat(4)@(negedge clk);rst=0;run(0);run(1);
 $display("SUPPORT_PACKAGE version=%0d RRQs=%0d errors=%0d",VERSION,rrqs,errors);
 if(errors==0)$display("TB_665_PACKAGE_SUPPORT_PASS");else $display("TB_665_PACKAGE_SUPPORT_FAIL");$finish;
end
initial begin #1000000;errors=errors+1;$display("FAIL support watchdog");$finish;end
endmodule
