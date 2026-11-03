`timescale 1ns/1ps
// Entire production top, redundant physical MAC loopback, no protocol stubs.
module tb_integration_subvl_mac;
reg clk=0;always #40 clk=~clk;
reg rst=1,tx_enable=0,cwrite=0,cseal=0,cwe=0,pwe=0;
reg [1:0] ci=0;reg [3:0] pi=0;reg [63:0] pe=0;reg [671:0] cfg=0;
reg wr=0,sof=0,eof=0,use_sap=0;reg [1:0] wvl=0,wsub=0,rvl=0,rsub=0;
reg [2:0] wpart=0,rpart=0;reg [15:0] wsap=0,wlen=0;reg [7:0] wd=0;
reg read_request=0,payload_ready=1;reg inject=0,inject_valid=0;reg [7:0] inject_data=0;
reg [575:0] startup_frame=576'h55555555555555d503000000000202000000102008004500001d002a00000111a5a40a0000010a00000227104e2000090000700000000000000000000000000000000000af5a100c;
wire cr,ce,wr_ready,wr_accept,len_error,access_error,rr;
wire [7:0] ad,bd,pd;wire ae,be,aer,ber,valid,psof,peof,fresh;wire [1:0] pvl;wire [3:0] port;wire [15:0] plen,psap;
wire [31:0] a_frames,b_frames,overflow;
integer errors=0,delivered=0,byte_index=0,expect_port=0,expect_len=0,expect_seed=0,expect_fresh=1;
integer i,j,t,wirelog,alen=0,blen=0;reg preva=0,prevb=0;
reg [7:0] amem[0:1535],bmem[0:1535];reg held=0;reg [7:0] held_data;reg held_sof,held_eof;reg [15:0] held_len;reg [3:0] held_port;
AFDX_competition_top #(.EXTENDED_PORTS(1),.EXPLICIT_PORT_READ(1),.FRESHNESS_CYCLES(125000)) dut(
 .clk(clk),.rst(rst),.cfg_rx_write(cwrite),.cfg_rx_seal(cseal),.cfg_rx_index(ci),.cfg_rx_entry(cfg[ci*168+:168]),.cfg_rx_ready(cr),.cfg_rx_error(ce),
 .cfg_port_write(pwe),.cfg_port_index(pi),.cfg_port_entry(pe),.tx_enable(tx_enable),.network_a_enable(1'b1),.network_b_enable(1'b1),
 .cfg_we(cwe),.cfg_vl_id(ci),.cfg_bag(32'd12500),.cfg_destination(8'd2),.cfg_lmax(16'd1518),
 .app_wr_en(wr),.app_wr_vl_id(wvl),.app_wr_subvl(wsub),.app_wr_use_sap(use_sap),.app_wr_sap(wsap),.app_wr_partition(wpart),
 .app_wr_data(wd),.app_wr_len(wlen),.app_wr_sof(sof),.app_wr_eof(eof),.app_wr_ready(wr_ready),.app_wr_accept(wr_accept),.app_len_error(len_error),.app_access_error(access_error),
 .fault_enable(1'b0),.data_a_txd(ad),.data_b_txd(bd),.data_a_tx_en(ae),.data_b_tx_en(be),.data_a_tx_er(aer),.data_b_tx_er(ber),.data_a_done(),.data_b_done(),
 .data_a_rxd(inject?inject_data:ad),.data_b_rxd(inject?inject_data:bd),.data_a_rx_dv(inject?inject_valid:ae),.data_b_rx_dv(inject?inject_valid:be),.data_a_rx_er(inject?1'b0:aer),.data_b_rx_er(inject?1'b0:ber),
 .payload_data(pd),.payload_valid(valid),.payload_sof(psof),.payload_eof(peof),.payload_network(),.payload_ready(payload_ready),
 .app_read_request(read_request),.app_read_port(rvl),.app_read_subvl(rsub),.app_read_partition(rpart),.app_read_ready(rr),
 .payload_length(plen),.payload_vl(pvl),.payload_port(port),.payload_sap(psap),.payload_fresh(fresh),
 .management_busy(),.snmp_snapshots(),.snmp_busy_drops(),.shared_rx_accepted(),.shared_rx_duplicates(),.shared_rx_dropped(),
 .shared_tx_overflows(overflow),.physical_a_frames(a_frames),.physical_b_frames(b_frames),
 .loader_ip(32'h0a000001),.time_server_ip(32'h0a000064),.hardware_length(6'd3),.hardware_id({232'd0,24'h4d4953}),.app_file(2'd0),
 .rtc_poll(1'b0),.rtc_locked(),.utc_ntp(),.monotonic_ticks(),.image_valid(),.image_length(),.image_crc(),.package_generation(),.package_file_count(),
 .image_read_address(16'd0),.image_read_data(),.loading(),.load_complete(),.load_failed());
task fail;input [511:0] why;begin errors=errors+1;$display("FAIL SUBVL %0s",why);end endtask
function integer msg_length;input integer p;begin msg_length=p<4?1800+p:p>=8&&p<12?1700+(p%4):40+p;end endfunction
task send;input integer p,n,seed;integer k,age;begin
 for(k=0;k<n;k=k+1)begin
  @(negedge clk);wvl=p%4;wsub=p/4;use_sap=p>=8&&p<12;wsap=16'h9000+p;wlen=n;wd=(seed+k*7)&255;sof=k==0;eof=k==n-1;wr=1;
  #1;age=0;while(!wr_ready&&age<100000)begin @(negedge clk);#1;age=age+1;end
  if(!wr_ready)fail("TX ready deadline");@(posedge clk);if(!wr_accept)fail("TX handshake missing");
 end
 @(negedge clk);wr=0;sof=0;eof=0;use_sap=0;
end endtask
task start_read;input integer p,n,seed,isfresh;begin
 expect_port=p;expect_len=n;expect_seed=seed;expect_fresh=isfresh;
 @(negedge clk);rvl=p%4;rsub=p/4;#1;t=0;
 while(!rr&&t<200000)begin @(negedge clk);#1;t=t+1;end
 if(!rr)fail("port read deadline");read_request=1;@(negedge clk);read_request=0;
end endtask
task finish_read;input integer target;begin
 t=0;while(delivered<target&&t<200000)begin @(negedge clk);t=t+1;end
 if(delivered!=target)fail("port data delivery deadline");repeat(3)@(negedge clk);
end endtask
task wait_messages;input integer target;begin
 t=0;while(dut.u_core.rx.messages<target&&t<300000)begin @(negedge clk);t=t+1;end
 if(dut.u_core.rx.messages!=target)fail("RX publication count");
end endtask
always @(posedge clk)if(!rst)begin
 if(held&&(!valid||pd!==held_data||psof!==held_sof||peof!==held_eof||plen!==held_len||port!==held_port))fail("read transaction changed under backpressure");
 held=valid&&!payload_ready;if(held)begin held_data=pd;held_sof=psof;held_eof=peof;held_len=plen;held_port=port;end
 if(valid&&payload_ready)begin
  if(psof)byte_index=0;
  if(pd!==((expect_seed+byte_index*7)&255)||plen!==expect_len||port!==expect_port||pvl!==(expect_port%4)||fresh!==expect_fresh)fail("application bytes/port/length/freshness");
  if(psap!==(expect_port>=8&&expect_port<12?16'h9000+expect_port:0))fail("SAP metadata");
  if(psof!==(byte_index==0)||peof!==(byte_index==expect_len-1))fail("application boundaries");
  byte_index=byte_index+1;if(peof)delivered=delivered+1;
 end
 if(ae)begin amem[alen]=ad;alen=alen+1;end
 if(preva&&!ae)begin $fwrite(wirelog,"A %0t ",$time);for(j=0;j<alen;j=j+1)$fwrite(wirelog,"%02x",amem[j]);$fwrite(wirelog,"\n");alen=0;end
 if(be)begin bmem[blen]=bd;blen=blen+1;end
 if(prevb&&!be)begin $fwrite(wirelog,"B %0t ",$time);for(j=0;j<blen;j=j+1)$fwrite(wirelog,"%02x",bmem[j]);$fwrite(wirelog,"\n");blen=0;end
 preva=ae;prevb=be;
end
reg [47:0] mac;reg [31:0] ip;reg [15:0] sp,dp,sap;reg [7:0] flags,mask;
initial begin
 wirelog=$fopen("subvl_wire.txt","w");
 for(i=0;i<4;i=i+1)begin mac=48'h030000000002+i;ip=32'h0a000002+i;sp=10000+i;dp=20000+i;cfg[i*168+:168]={16'd1518,dp,sp,ip,32'h0a000001,mac,8'h03};end
 repeat(5)@(negedge clk);rst=0;
 for(i=0;i<4;i=i+1)begin ci=i;cwrite=1;cwe=1;@(negedge clk);cwrite=0;cwe=0;@(negedge clk);end
 for(i=0;i<16;i=i+1)begin pi=i;sp=10000+i;dp=20000+i;sap=16'h9000+i;flags=i==4?8'h0b:i>=8&&i<12?8'h0d:8'h09;mask=i==4?8'h03:8'h01;pe={mask,dp,sp,sap,flags};pwe=1;@(negedge clk);pwe=0;#1;if(ce)fail("valid port configuration rejected");@(negedge clk);end
 pi=14;pe[7:0]=8'h0d;pe[23:8]=16'h9008;pwe=1;@(negedge clk);pwe=0;#1;if(!ce)fail("duplicate SAP accepted");@(negedge clk);
 pi=12;pe={8'h01,16'd20000,16'd10000,16'h9012,8'h09};pwe=1;@(negedge clk);pwe=0;#1;
 if(!ce)fail("duplicate UDP binding accepted");@(negedge clk);
 // Correctly addressed, CRC-valid traffic before seal is not application data.
 inject=1;for(i=0;i<72;i=i+1)begin @(negedge clk);inject_data=startup_frame[575-i*8-:8];inject_valid=1;end
 @(negedge clk);inject_valid=0;repeat(200)@(negedge clk);inject=0;
 if(dut.u_core.rx.messages!=0||dut.u_core.rx.accepted_frames!=0)fail("business traffic admitted before seal");
 // A coincident write/seal must neither publish nor modify any table.
 pi=4;pe={8'h01,16'd22222,16'd11111,16'hdead,8'h09};pwe=1;cseal=1;
 @(negedge clk);pwe=0;cseal=0;#1;
 if(!ce||cr||dut.port_sealed||dut.port_table[4*64+40+:16]!=20004)fail("port write/seal was not atomic");
 @(negedge clk);ci=0;cwrite=1;cwe=1;cseal=1;
 @(negedge clk);cwrite=0;cwe=0;cseal=0;#1;
 if(!ce||cr||dut.port_sealed)fail("VL/TX write/seal was not atomic");
 @(negedge clk);cseal=1;@(negedge clk);cseal=0;#1;if(!cr||!dut.port_sealed)fail("configuration seal");
 pwe=1;@(negedge clk);pwe=0;#1;if(!ce)fail("live reconfiguration accepted");@(negedge clk);
 wpart=1;use_sap=1;wsap=16'h9008;wr=1;sof=1;eof=1;wlen=1;#1;
 if(wr_ready||wr_accept||!access_error)fail("unauthorized SAP writer");@(negedge clk);wr=0;sof=0;eof=0;use_sap=0;wpart=0;
 wsap=16'hdead;use_sap=1;wr=1;sof=1;eof=1;wlen=1;#1;
 if(wr_ready||wr_accept||!access_error)fail("unknown SAP accepted");@(negedge clk);wr=0;sof=0;eof=0;use_sap=0;
 // Capacity is a declared, configurable hardware limit, never a standard limit.
 wvl=0;wsub=3;wlen=2049;wr=1;sof=1;eof=0;#1;if(wr_ready||wr_accept)fail("over-capacity sub-VL message accepted");
 @(negedge clk);#1;if(!len_error)fail("over-capacity report missing");wr=0;sof=0;
 for(i=0;i<16;i=i+1)begin if(i==4)send(4,44,99);send(i,msg_length(i),20+i);end
 send(12,21,200);
 @(negedge clk);wr=1;sof=1;eof=1;wvl=0;wsub=3;wlen=1;wd=250;#1;
 if(wr_ready||wr_accept)fail("full queuing port accepted third message");repeat(3)@(negedge clk);wr=0;sof=0;eof=0;
 tx_enable=1;wait_messages(17);
 rpart=1;rvl=0;rsub=2;read_request=1;repeat(4)begin @(negedge clk);if(rr||valid)fail("unauthorized SAP reader");end
 read_request=0;rpart=0;
 for(i=0;i<16;i=i+1)begin start_read(i,msg_length(i),20+i,1);finish_read(i+1);end
 start_read(12,21,200,1);finish_read(17);
 // Precisely coincide a queued-message enqueue with the previous dequeue.
 send(15,1,210);t=0;
 while(!(dut.u_core.tx.state==3&&dut.u_core.tx.selected==15&&dut.u_core.tx.idle_gap==1)&&t<50000)begin @(negedge clk);t=t+1;end
 if(t==50000)fail("could not reach simultaneous enqueue/dequeue boundary");
 @(negedge clk);wr=1;sof=1;eof=1;wvl=3;wsub=3;wlen=1;wd=211;
 @(posedge clk);if(!wr_accept||!dut.u_core.tx.enqueue||!dut.u_core.tx.dequeue)fail("enqueue/dequeue did not coincide");
 $display("SUBVL_SIMULTANEOUS_ENQUEUE_DEQUEUE");@(negedge clk);wr=0;sof=0;eof=0;
 wait_messages(19);start_read(15,1,210,1);finish_read(18);start_read(15,1,211,1);finish_read(19);
 payload_ready=0;rpart=1;start_read(4,44,24,1);repeat(5)@(negedge clk);
 send(4,27,55);wait_messages(20);send(4,28,66);wait_messages(21);repeat(10)@(negedge clk);
 payload_ready=1;finish_read(20);
 start_read(4,28,66,1);finish_read(21);
 repeat(130000)@(negedge clk);start_read(4,28,66,0);finish_read(22);
 if(a_frames!=29||b_frames!=29||overflow!=0||dut.u_core.rx.overflows!=0||dut.u_core.rx.reassembly_errors!=0)fail("wire frame/capacity/integrity totals");
 $fclose(wirelog);$display("SUBVL_FINAL messages=%0d deliveries=%0d A=%0d B=%0d errors=%0d",dut.u_core.rx.messages,delivered,a_frames,b_frames,errors);
 if(errors==0)$display("TB_INTEGRATION_SUBVL_MAC_PASS");else $display("TB_INTEGRATION_SUBVL_MAC_FAIL");$finish;
end
initial begin #100000000;$display("SUBVL_TIMEOUT");$finish;end
endmodule