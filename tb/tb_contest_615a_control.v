`timescale 1ns/1ps
module tb_contest_615a_control;
reg clk=0;always #5 clk=~clk;reg rst=1,init=0,lur=0,td=0,terr=0,vd=0,vok=0;
reg [1023:0] request=0;reg [15:0] len=0;
wire iv,accepted,rejected,fetch,vr,sv,active,complete,failed;wire [79:0] ib;wire [5:0] nl;wire [255:0] name;wire [15:0] vl,code;wire [31:0] vc;wire [7:0] sl;wire [1023:0] sb;
integer errors=0,cases=0,i;
afdx_615a_upload_control #(.STATUS_PERIOD(20),.VALIDATION_TIMEOUT(32)) dut(.clk(clk),.rst(rst),.initialize(init),.init_valid(iv),.init_ready(1'b1),.init_bytes(ib),
.lur_valid(lur),.lur_length(len),.lur_bytes(request),.lur_accept(accepted),.lur_reject(rejected),.fetch_start(fetch),.filename_length(nl),.filename(name),
.transfer_done(td),.transfer_error(terr),.transferred_length(16'd700),.transferred_crc(32'h12345678),.validate_request(vr),.validate_length(vl),.validate_crc(vc),
.validation_done(vd),.validation_ok(vok),.status_valid(sv),.status_ready(1'b1),.status_length(sl),.status_bytes(sb),.active(active),.complete(complete),.failed(failed),.status_code(code));
task fail;input [511:0] reason;begin errors=errors+1;$display("FAIL 615A %0s",reason);end endtask
task tick;begin @(negedge clk);end endtask
task initialize;begin init=1;tick;init=0;if(!iv||ib[31:0]!=32'h0a000000||ib[47:32]!=16'h3441||ib[63:48]!=16'h0100)fail("LUI encoding");tick;end endtask
task make_lur;begin
 // Independent A4 LUR: 4-byte length, A4, one header, NUL-terminated APP.LUH and PN-1.
 request=0;len=23;request[3*8+:8]=23;request[4*8+:8]="A";request[5*8+:8]="4";request[7*8+:8]=1;
 request[8*8+:8]=8;request[9*8+:64]=64'h0048554c2e505041;
 request[17*8+:8]=5;request[18*8+:40]=40'h00312d4e50;
end endtask
task submit;input good;begin lur=1;tick;lur=0;if(accepted!==good||rejected===good)fail("LUR validation");end endtask
task await_status;input [15:0] status;integer t;begin
 t=0;while((!sv||{sb[55:48],sb[63:56]}!=status)&&t<100)begin tick;t=t+1;end
 if(t==100)fail("missing final LUS");
 if({sb[7:0],sb[15:8],sb[23:16],sb[31:24]}!=sl||sb[39:32]!="A"||sb[47:40]!="4")fail("LUS envelope");
 if(sb[20*8+:8]!=1||sb[21*8+:8]!=8||sb[22*8+:64]!=64'h0048554c2e505041)fail("LUS header file");
 if(status==3&&{sb[16*8+:8],sb[17*8+:8],sb[18*8+:8]}!=24'h313030)fail("LUS progress");tick;
end endtask
initial begin
 repeat(4)tick;rst=0;
 make_lur;submit(0);initialize;request[3*8+:8]=22;submit(0);make_lur;submit(1);
 if(!fetch||nl!=7||name[55:0]!=56'h48554c2e505041)fail("load-header RRQ intent");
 repeat(4)tick;td=1;tick;td=0;if(!vr||vl!=700||vc!=32'h12345678)fail("application validation contract");
 if(complete)fail("must not complete without application validation");vd=1;vok=1;tick;vd=0;await_status(3);if(!complete||failed)fail("completion");
 initialize;make_lur;submit(1);terr=1;tick;terr=0;await_status(16'h1003);if(!failed||complete)fail("transport failure");
 initialize;make_lur;submit(1);td=1;tick;td=0;repeat(34)tick;await_status(16'h1003);if(!failed)fail("validation timeout");
 initialize;make_lur;request[7*8+:8]=2;submit(0);make_lur;submit(1);
 td=1;tick;td=0;vd=1;vok=0;tick;vd=0;await_status(16'h1003);if(!failed||complete)fail("negative application validation");
 $display("615A_CONTROL_ERRORS=%0d",errors);
 if(errors==0)$display("TB_CONTEST_615A_CONTROL_PASS");else $display("TB_CONTEST_615A_CONTROL_FAIL");$finish;
end
initial begin #100000;$display("615A_CONTROL_TIMEOUT");$finish;end
endmodule
