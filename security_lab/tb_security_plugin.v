`timescale 1ns/1ps
module tb_security_plugin;
reg clk=0;always #40 clk=~clk;reg rst=1;reg [31:0] input_data=0;reg [3:0] input_valid=0,input_error=0;wire [15:0] core_data;wire [1:0] core_valid,core_error;
reg cw=0,cr=0,core_safe=1,event_ready=1;reg [15:0] ca=0;reg [31:0] cd=0;wire ready,error,pending,commit;wire [31:0] rd,epoch;wire [1:0] mode;wire ev,alarm,idle;wire [159:0] event_record;wire [31:0] wa,wb,qo,eo,ab,hf,ta;wire [3:0] tf;
reg [255:0] target_id=256'h4d4953;reg locked=0,reanchor=0;reg [63:0] utc=64'h0000000100000000,mono=0,frac=0;
reg [12287:0] frames[0:255];integer fd,wirefd,eventfd,n,op,a0,a1,a2,a3,a4,a5,a6,i,j,t,case_id=0,errors=0,events=0,wire_count=0,cycle=0;
reg [159:0] last_event;reg [1:0] previous=0;reg [7:0] capture[0:3071];integer counts[0:1];integer before_event,before_wire;
afdx_security_plugin #(.TIME_SAMPLE_CYCLES(32)) dut(.clk(clk),.rst(rst),.a_rx(input_data[7:0]),.b_rx(input_data[15:8]),.a_tx(input_data[23:16]),.b_tx(input_data[31:24]),.a_rx_valid(input_valid[0]),.b_rx_valid(input_valid[1]),.a_tx_valid(input_valid[2]),.b_tx_valid(input_valid[3]),.a_rx_error(input_error[0]),.b_rx_error(input_error[1]),.a_tx_error(input_error[2]),.b_tx_error(input_error[3]),.core_a_rx(core_data[7:0]),.core_b_rx(core_data[15:8]),.core_a_valid(core_valid[0]),.core_b_valid(core_valid[1]),.core_a_error(core_error[0]),.core_b_error(core_error[1]),.core_safe(core_safe),.target_id(target_id),.rtc_locked(locked),.utc_ntp(utc),.monotonic_ticks(mono),.time_reanchor(reanchor),.cfg_write(cw),.cfg_read(cr),.cfg_address(ca),.cfg_wdata(cd),.cfg_ready(ready),.cfg_error(error),.cfg_pending(pending),.cfg_commit_pulse(commit),.cfg_rdata(rd),.mode(mode),.epoch(epoch),.event_valid(ev),.event_ready(event_ready),.event_record(event_record),.alarm(alarm),.time_flags(tf),.time_alarms(ta),.would_allow(wa),.would_block(wb),.queue_overflows(qo),.event_overflows(eo),.ab_conflicts(ab),.hash_failures(hf),.idle(idle));
always @(posedge clk)begin
 if(rst)begin cycle=0;mono<=0;utc<=64'h0000000100000000;frac<=0;previous=0;counts[0]=0;counts[1]=0;end
 else begin
  cycle=cycle+1;mono<=mono+1'b1;
  if(frac+7467296>=12500000)begin frac<=frac+7467296-12500000;utc<=utc+344;end else begin frac<=frac+7467296;utc<=utc+343;end
  if(ev&&event_ready)begin events=events+1;last_event=event_record;$fwrite(eventfd,"%0d %0d %040x\n",case_id,cycle,event_record);end
  for(j=0;j<2;j=j+1)begin
   if(mode!=2&&(core_valid[j]!==input_valid[j]||core_error[j]!==input_error[j]||(core_valid[j]&&core_data[j*8+:8]!==input_data[j*8+:8])))begin errors=errors+1;$display("FAIL transparent path");end
   if(core_valid[j])begin capture[j*1536+counts[j]]=core_data[j*8+:8];counts[j]=counts[j]+1;end
   else if(previous[j])begin wire_count=wire_count+1;$fwrite(wirefd,"%0d %0d %0d ",case_id,j,cycle);for(t=0;t<counts[j];t=t+1)$fwrite(wirefd,"%02x",capture[j*1536+t]);$fwrite(wirefd,"\n");counts[j]=0;end
  end
  previous=core_valid;
 end
end
task fail;input [511:0] why;begin errors=errors+1;$display("FAIL case=%0d %0s",case_id,why);end endtask
task tick;begin @(negedge clk);end endtask
task send_frame;input wait_event;begin
 before_event=events;before_wire=wire_count;
 for(i=0;i<a1;i=i+1)begin input_data[a0*8+:8]=frames[a2][i*8+:8];input_valid[a0]=1;tick;end
 input_valid[a0]=0;
 if(wait_event)begin
  n=0;while((events==before_event||!idle)&&n<100000)begin tick;n=n+1;end
  repeat(3)tick;
  if(events!=before_event+1||n>=100000)fail("missing or extra event");
  if(last_event[63:48]!==a3[15:0]||last_event[41]!==a4[0]||last_event[43:42]!==a0[1:0])begin $display("EVENT_DEBUG got=%040x flags=%h expected=%h",last_event,last_event[63:48],a3);fail("verdict mismatch");end
  if(a0<2&&wire_count-before_wire!=((a5==2&&!a4)?0:1))begin $display("WIRE_DEBUG before=%0d after=%0d mode=%0d allow=%0d",before_wire,wire_count,a5,a4);fail("whole-frame output count");end
  if(events==before_event+1&&last_event[63:48]===a3[15:0]&&last_event[41]===a4[0])$display("SCENARIO_PASS case=%0d flags=%04x allow=%0d mode=%0d",case_id,a3,a4,a5);
 end else repeat(12)tick;
end endtask
initial begin
 $readmemh("frames.hex",frames);fd=$fopen("commands.hex","r");wirefd=$fopen("forwarded_wire.txt","w");eventfd=$fopen("security_events.txt","w");repeat(4)tick;rst=0;
 while(!$feof(fd))begin
  n=$fscanf(fd,"%h %h %h %h %h %h %h %h\n",op,a0,a1,a2,a3,a4,a5,a6);
  if(n==8)begin case_id=a6;
   case(op)
    0:begin rst=1;input_valid=0;cw=0;locked=0;reanchor=0;core_safe=1;event_ready=1;target_id=256'h4d4953;repeat(4)tick;rst=0;repeat(3)tick;end
    1,11:begin tick;cw=1;ca=a0;cd=a1;tick;cw=0;if(error!==(op==11))fail("configuration response");tick;end
    2:send_frame(1);
    3:send_frame(0);
    4:repeat(a0)tick;
    5:begin ca=a0;cr=1;#1;if(rd!==a1)begin $display("READ_DEBUG addr=%h got=%h expected=%h",ca,rd,a1);fail("register assertion");end tick;cr=0;end
    6:begin core_safe=a0[0];tick;end
    7:begin event_ready=a0[0];tick;end
    8:begin tick;locked=a0[0];utc={a1,a2};mono={a3,a4};reanchor=a5[0];tick;reanchor=0;end
    10:begin target_id={224'd0,a0};tick;end
    12:begin ca=a0;cr=1;#1;if(rd<a1)fail("register lower bound");else $display("REGISTER_MIN_PASS addr=%04x actual=%0d min=%0d",ca,rd,a1);tick;cr=0;end
    9:begin tick;input_error=a0[3:0];tick;end
    default:fail("unknown command");
   endcase
  end
 end
 repeat(100)tick;$fclose(wirefd);$fclose(eventfd);
 $display("SEC_PLUGIN_FINAL errors=%0d frames=%0d events=%0d",errors,wire_count,events);
 if(errors==0)$display("SEC_PLUGIN_PASS");else $display("SEC_PLUGIN_FAIL");$finish;
end
initial begin #1000000000;$display("SEC_PLUGIN_TIMEOUT");$finish;end
endmodule
