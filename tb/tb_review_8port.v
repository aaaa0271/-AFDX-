`timescale 1ns/1ps
module tb_review_8port;
parameter integer SECURE=0;
reg clk=0;always #40 clk=~clk;
reg rst=1,start=0,replay=0;reg [7:0] replay_data=0;
wire [7:0] tx_data,peer_data;wire tx_valid,peer_valid,peer_error,ready;
wire cfg_ok,clock_locked,image_valid,complete,failed,payload_valid;wire [7:0] payload_data;
wire [15:0] image_length;wire [31:0] generation;wire [2:0] file_count;
wire [7:0] incoming=replay?replay_data:peer_data;wire incoming_valid=replay||peer_valid;
integer errors=0,frames=0,loaded_frames=0,received=0,i,n,timeout,log,count=0;
reg previous=0;reg [7:0] capture[0:1535],business[0:71];reg saved=0;
generate if(SECURE==0)begin:PLAIN
 AFDX_top #(.DEMO_INTERVAL_CYCLES(20000),.RTC_POLL_CYCLES(2000000),.SERVICE_TIMEOUT_CYCLES(300000),.TIME_SERVER_IP(32'h0a000001)) dut(
  .clk(clk),.reset(rst),.tx_data(tx_data),.rx_data(incoming),.tx_valid(tx_valid),.rx_valid(incoming_valid),.tx_ready(ready),.rx_ready(1'b1));
 assign cfg_ok=dut.cfg_rx_ready&&!dut.cfg_rx_error;assign clock_locked=dut.rtc_locked;
 assign image_valid=dut.image_valid;assign image_length=dut.image_length;assign generation=dut.package_generation;assign file_count=dut.package_file_count;
 assign complete=dut.load_complete;assign failed=dut.load_failed;assign payload_valid=dut.payload_valid;assign payload_data=dut.payload_data;
end else begin:GUARDED
 AFDX_security_8port_top #(.DEMO_INTERVAL_CYCLES(20000),.RTC_POLL_CYCLES(2000000),.SERVICE_TIMEOUT_CYCLES(300000),.TIME_SERVER_IP(32'h0a000001)) dut(
  .clk(clk),.reset(rst),.tx_data(tx_data),.rx_data(incoming),.tx_valid(tx_valid),.rx_valid(incoming_valid),.tx_ready(ready),.rx_ready(1'b1));
 assign cfg_ok=dut.cfg_ready&&!dut.cfg_error;assign clock_locked=dut.rtc_locked;
 assign image_valid=dut.image_valid;assign image_length=dut.image_length;assign generation=dut.u_end_system.package_generation;assign file_count=dut.u_end_system.package_file_count;
 assign complete=dut.u_end_system.load_complete;assign failed=dut.load_failed;assign payload_valid=dut.payload_valid;assign payload_data=dut.payload_data;
end endgenerate
wire [31:0] peer_errors,final_reports;wire lui,lur,ntp;
model_foundation_peer peer(.clk(clk),.rst(rst),.start(start),.tx_admit(1'b1),.rxd(tx_data),.dv(tx_valid),.er(1'b0),
 .txd(peer_data),.txen(peer_valid),.txer(peer_error),.errors(peer_errors),.reports(),.final_reports(final_reports),.lui_seen(lui),.lur_seen(lur),.ntp_seen(ntp));
task fail;input [511:0] why;begin errors=errors+1;$display("FAIL DEMO_8PORT %0s",why);end endtask
always @(posedge clk)if(!rst)begin
 if(payload_valid)begin
  if(payload_data!==business[50+received])fail("business loopback content");received=received+1;
 end
 if(tx_valid)begin capture[count]=tx_data;count=count+1;end
 else if(previous)begin
  frames=frames+1;
  for(n=0;n<count;n=n+1)$fwrite(log,"%02x",capture[n]);$fwrite(log,"\n");
  if(capture[8]==3&&capture[13]>=8'h40&&capture[13]<=8'h43)begin
   if(count!=72||{capture[53],capture[52],capture[51],capture[50]}!==32'h58444641)fail("demo payload or frame length");
   if(!saved)begin for(n=0;n<72;n=n+1)business[n]=capture[n];saved=1;end
   if(capture[62][1])loaded_frames=loaded_frames+1;
  end
  count=0;
 end
 previous=tx_valid;
end
initial begin
 log=$fopen("demo_wire.txt","w");repeat(8)@(negedge clk);rst=0;
 timeout=0;while(!ready&&timeout<100)begin @(negedge clk);timeout=timeout+1;end
 if(!cfg_ok)fail("startup configuration not sealed");
 start=1;@(negedge clk);start=0;
 timeout=0;while((!complete||!clock_locked||loaded_frames<4)&&timeout<1000000)begin @(negedge clk);timeout=timeout+1;end
 if(!image_valid||!complete||failed||image_length!=700||generation!=1||file_count!=2)fail("package did not commit through eight ports");
 if(!clock_locked||!ntp||!lui||!lur||final_reports!=1||peer_errors!=0||peer_error)fail("wire service evidence");
 if(!saved)fail("no business transmission");
 repeat(200)@(negedge clk);
 for(i=0;i<72;i=i+1)begin replay=1;replay_data=business[i];@(negedge clk);end
 replay=0;repeat(5000)@(negedge clk);
 if(received!=16)fail("business receive path not functional");
 $fclose(log);$display("DEMO_8PORT secure=%0d frames=%0d loaded_telemetry=%0d received=%0d",SECURE,frames,loaded_frames,received);
 if(errors==0)$display("TB_REVIEW_8PORT_PASS");$finish;
end
initial begin #100000000;fail("watchdog");$finish;end
endmodule
