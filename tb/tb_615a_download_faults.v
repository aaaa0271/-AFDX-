`timescale 1ns/1ps
// Deliberately hostile independent peer. No internal DUT state is driven.
module tb_615a_download_faults;
reg clk=0;always #5 clk=~clk;reg rst=1,rv=0,upload_busy=0,pkg_valid=1;
reg [31:0] rip=32'h0a000001;reg [15:0] rsp=32000,rdp=69;reg [10:0] rl=0;reg [4127:0] rb=0;
wire tv,active,idle,complete,failed;wire [31:0] tip;wire [15:0] sp,dp,addr;wire [1:0] file_index;
wire [10:0] tl;wire [4127:0] tb;reg [15:0] file_size=1;
integer errors=0,scenario=0,t,k,control_errors=0,init_packets=0,file_wrqs=0,file_packets=0,terminal_status=0,zero_blocks=0;
integer prior_errors,prior_files;reg pending=0;reg [4127:0] reply;reg [10:0] reply_len;reg [15:0] reply_sp,reply_dp;
reg [4095:0] request_file;integer request_size;
afdx_615a_download #(.TIMEOUT_CYCLES(80),.CLK_HZ(80)) dut(
 .clk(clk),.rst(rst),.loader_ip(32'h0a000001),.upload_busy(upload_busy),.package_valid(pkg_valid),.file_count(3'd1),
 .read_file(file_index),.read_address(addr),.read_name({216'd0,40'h50554c2e41}),.read_length(file_size),.read_data(addr[7:0]^8'h5a),
 .rx_valid(rv),.rx_ip(rip),.rx_sport(rsp),.rx_dport(rdp),.rx_length(rl),.rx_bytes(rb),
 .tx_valid(tv),.tx_ready(1'b1),.tx_ip(tip),.tx_sport(sp),.tx_dport(dp),.tx_length(tl),.tx_bytes(tb),
 .active(active),.idle(idle),.complete(complete),.failed(failed));
task fail;input [511:0] why;begin errors=errors+1;$display("DOWNLOAD_FAULT scenario=%0d %0s",scenario,why);end endtask
always @(posedge clk)if(!rst&&tv)begin
 reply=0;reply_len=4;reply_sp=dp;reply_dp=sp;
 if(sp==44000)begin
  if(tb[15:8]==3)begin
   init_packets=init_packets+1;reply[15:8]=4;reply[31:24]=1;
   // Drop the first initialization ACK in scenario 7.
   if(scenario!=7||init_packets>1)pending=1;
  end else if(tb[15:8]==4&&tb[31:24]==0)begin
   reply[15:8]=3;reply[31:24]=1;reply[4*8+:4096]=request_file;reply_len=request_size+4;pending=1;
  end else if(tb[15:8]==5)control_errors=control_errors+1;
 end else if(sp==44001)begin
  reply_sp=30004;reply[15:8]=4;
  if(tb[15:8]==2)begin
   reply[31:24]=0;
   if(tb[2*8+:40]==40'h50554c2e41)begin file_wrqs=file_wrqs+1;if(scenario!=5)pending=1;end
   else pending=1;
  end else if(tb[15:8]==3)begin
   reply[23:16]=tb[23:16];reply[31:24]=tb[31:24];pending=1;
   if(tl>=10&&tb[8*8+:16]==16'h3441)begin
    if({tb[10*8+:8],tb[11*8+:8]}>=16'h1000||{tb[10*8+:8],tb[11*8+:8]}==3)
     terminal_status={tb[10*8+:8],tb[11*8+:8]};
   end else begin
    file_packets=file_packets+1;if(tl==4)zero_blocks=zero_blocks+1;
    if(scenario==4)begin reply=0;reply[15:8]=5;reply[31:24]=0;reply[4*8+:48]=48'h003730303041;reply_len=10;end
   end
  end
 end
end
always @(negedge clk)begin
 rv=0;
 if(!rst&&pending)begin rv=1;rip=32'h0a000001;rsp=reply_sp;rdp=reply_dp;rb=reply;rl=reply_len;pending=0;end
end
task request;input [15:0] op;input [79:0] name;begin
 @(posedge clk);#1;reply=0;reply[15:8]=op;reply[2*8+:80]=name;reply[13*8+:48]=48'h00746574636f;
 reply_sp=32000;reply_dp=69;reply_len=19;pending=1;
end endtask
task reset_test;begin
 rst=1;pending=0;repeat(4)@(negedge clk);rst=0;
 terminal_status=0;control_errors=0;init_packets=0;file_wrqs=0;file_packets=0;zero_blocks=0;file_size=1;upload_busy=0;pkg_valid=1;
 request_file=0;request_file[3*8+:8]=16;request_file[4*8+:8]="A";request_file[5*8+:8]="4";request_file[7*8+:8]=1;
 request_file[8*8+:8]=6;request_file[9*8+:48]=48'h0050554c2e41;request_size=16;
end endtask
task initialize;begin
 request(1,80'h444e4c2e544547524154);
 t=0;while(dut.state!=5&&t<1000)begin @(negedge clk);t=t+1;end
 if(t==1000)fail("initialization did not reach selection");
end endtask
task finish_test;input expect_success;begin
 t=0;while(active&&t<3000)begin @(negedge clk);t=t+1;end
 if(active||!idle)fail("resource not released");
 if(expect_success)begin if(!complete||failed||terminal_status!=3)fail("successful session result");end
 else begin if(complete||!failed||terminal_status<16'h1000)fail("failed session incorrectly completed");end
end endtask
initial begin
 scenario=0;reset_test;pkg_valid=0;request(1,80'h444e4c2e544547524154);repeat(30)@(negedge clk);
 if(control_errors!=1||active)fail("uncommitted bank exposed");
 scenario=1;reset_test;upload_busy=1;request(1,80'h444e4c2e544547524154);repeat(30)@(negedge clk);
 if(control_errors!=1||active)fail("concurrent upload not rejected");
 // Unknown filename, changed envelope/version, duplicate selection.
 for(scenario=2;scenario<=9;scenario=scenario+1)begin
  if(scenario==2||scenario==3||scenario==8||scenario==9)begin
  reset_test;initialize;
  if(scenario==2)request_file[9*8+:8]="X";
  else if(scenario==3)request_file[5*8+:8]="9";
  else if(scenario==8)begin
   request_file[7*8+:8]=2;request_file[3*8+:8]=23;request_size=23;
   request_file[15*8+:8]=6;request_file[16*8+:48]=48'h0050554c2e41;
  end else begin request_file[15*8+:8]=1;request_file[16*8+:8]=8'h55;request_file[3*8+:8]=17;request_size=17;end
  request(2,80'h524e4c2e544547524154);finish_test(0);
  if(control_errors!=1||file_wrqs!=0)fail("malformed selection initiated file write");
  end
 end
 scenario=4;reset_test;initialize;request(2,80'h524e4c2e544547524154);finish_test(0);
 if(file_wrqs!=1||file_packets!=1)fail("remote abort coverage");
 scenario=5;reset_test;initialize;request(2,80'h524e4c2e544547524154);finish_test(0);
 if(file_wrqs!=4||file_packets!=0)fail("bounded file retry budget");
 scenario=6;reset_test;initialize;finish_test(0);
 if(file_wrqs!=0)fail("selection timeout wrote a file");
 scenario=7;reset_test;file_size=0;initialize;request(2,80'h524e4c2e544547524154);finish_test(1);
 if(init_packets!=2||zero_blocks!=1)fail("initialization retry or zero-byte file");
 $display("DOWNLOAD_FAULT_SCENARIOS=10 ERRORS=%0d",errors);
 if(errors==0)$display("TB_615A_DOWNLOAD_FAULTS_PASS");else $display("TB_615A_DOWNLOAD_FAULTS_FAIL");$finish;
end
initial begin #3000000;$display("DOWNLOAD_FAULT_TIMEOUT");$finish;end
endmodule
