`timescale 1ns/1ps
module tb_security_core_multi;
reg clk=0;always #40 clk=~clk;reg rst=1,start=0,poll=0;
reg [1:0] app_domain=0,app_file=0;reg [15:0] app_address=0;
wire [7:0] a,b;wire ae,be,aerr,ber;
reg [7:0] incoming=0;reg incoming_valid=0;
wire [1:0] loaded,locked;wire image_valid,loading,complete,failed,rtc_locked;
wire [7:0] image_data;wire [15:0] image_length;wire [31:0] image_crc,generation,overflows;wire [2:0] file_count;
wire [63:0] utc,mono;
integer errors=0,cycle=0,wire_log,byte_index,k,d,f,n,t;
// Explicit declarations before instantiation (ModelSim rejects an implicit
// net created by a port connection that is later redeclared as reg/wire).
reg sec_write=0;reg [15:0] sec_address=0;reg [31:0] sec_data=0;
wire sec_ready,sec_error,sec_commit,sec_ev;wire [1:0] sec_mode;wire [159:0] sec_record;wire [31:0] sec_overflows,sec_hash_fails;
integer sec_config,sec_n,sec_a,sec_v,sec_fd,security_violations=0;
AFDX_security_plugin_top #(.SERVICE_DOMAINS(2),.SERVICE_BAG_CYCLES(12500),.SERVICE_TIMEOUT_CYCLES(300000),.RX_SKEW_MAX_CYCLES(200000)) dut(
 .sec_cfg_write(sec_write),.sec_cfg_read(1'b0),.sec_cfg_address(sec_address),.sec_cfg_wdata(sec_data),.sec_cfg_ready(sec_ready),.sec_cfg_error(sec_error),.sec_cfg_commit_pulse(sec_commit),.sec_mode(sec_mode),.sec_event_valid(sec_ev),.sec_event_ready(1'b1),.sec_event_record(sec_record),.sec_queue_overflows(sec_overflows),.sec_hash_failures(sec_hash_fails),.clk(clk),.rst(rst),.cfg_port_write(1'b0),.cfg_port_index(4'd0),.cfg_port_entry(64'd0),
 .cfg_rx_write(1'b0),.cfg_rx_seal(1'b0),.cfg_rx_index(2'd0),.cfg_rx_entry(168'd0),.cfg_rx_ready(),.cfg_rx_error(),
 .tx_enable(1'b1),.network_a_enable(1'b1),.network_b_enable(1'b1),.cfg_we(1'b0),.cfg_vl_id(2'd0),.cfg_bag(32'd12500),.cfg_destination(8'd2),.cfg_lmax(16'd1518),
 .app_wr_en(1'b0),.app_wr_vl_id(2'd0),.app_wr_data(8'd0),.app_wr_len(16'd0),.app_wr_sof(1'b0),.app_wr_eof(1'b0),.app_wr_ready(),.app_len_error(),.app_wr_accept(),
 .app_wr_subvl(2'd0),.app_wr_use_sap(1'b0),.app_wr_sap(16'd0),.app_wr_partition(3'd0),.app_read_partition(3'd0),.app_read_subvl(2'd0),.app_access_error(),.payload_port(),.payload_sap(),
 .fault_enable(1'b0),.data_a_txd(a),.data_b_txd(b),.data_a_tx_en(ae),.data_b_tx_en(be),.data_a_tx_er(aerr),.data_b_tx_er(ber),.data_a_done(),.data_b_done(),
 .data_a_rxd(incoming),.data_b_rxd(incoming),.data_a_rx_dv(incoming_valid),.data_b_rx_dv(incoming_valid),.data_a_rx_er(1'b0),.data_b_rx_er(1'b0),
 .payload_data(),.payload_valid(),.payload_sof(),.payload_eof(),.payload_network(),.payload_ready(1'b1),.app_read_request(1'b0),.app_read_port(2'd0),.app_read_ready(),.payload_length(),.payload_vl(),.payload_fresh(),
 .management_busy(),.snmp_snapshots(),.snmp_busy_drops(),.shared_rx_accepted(),.shared_rx_duplicates(),.shared_rx_dropped(),.shared_tx_overflows(overflows),.physical_a_frames(),.physical_b_frames(),
 .loader_ip(32'h0a000001),.time_server_ip(32'h0a000101),.hardware_length(6'd3),.hardware_id({232'd0,24'h4d4953}),
 .service_app_domain(app_domain),.service_loaded(loaded),.service_clock_locked(locked),.app_file(app_file),.rtc_poll(poll),.rtc_locked(rtc_locked),.utc_ntp(utc),.monotonic_ticks(mono),
 .image_valid(image_valid),.image_length(image_length),.image_crc(image_crc),.package_generation(generation),.package_file_count(file_count),.image_read_address(app_address),.image_read_data(image_data),.loading(loading),.load_complete(complete),.load_failed(failed));

always @(posedge clk)if(!rst&&sec_ev)begin
 $fwrite(sec_fd,"%0t %040x\n",$time,sec_record);
 if(sec_record[63:48]!=0)begin security_violations=security_violations+1;$display("SEC_CORE_VIOLATION record=%040x",sec_record);end
end
task configure_security;begin
 sec_fd=$fopen("core_security_events.txt","w");sec_config=$fopen("core_config.hex","r");
 while(!$feof(sec_config))begin
  sec_n=$fscanf(sec_config,"%h %h\n",sec_a,sec_v);
  if(sec_n==2)begin wait(sec_ready);@(negedge clk);sec_address=sec_a;sec_data=sec_v;sec_write=1;@(negedge clk);sec_write=0;if(sec_error)fail("security configuration");end
 end
 $fclose(sec_config);repeat(20)@(negedge clk);
 if(sec_mode!=2)fail("security enforcement not active");
end endtask

wire [31:0] peers_tx;wire [3:0] peers_en,peers_err;wire [127:0] peer_errors,filter_overflows,final_reports;
wire [3:0] lui,lur,ntp;wire [3:0] admit;
reg clock1_enabled=0;
reg [7:0] net_mem[0:6143];integer caplen[0:3],frame_length[0:3];reg [3:0] previous=0,pending=0;
integer owner=0,rr=3,idx=0,gap=0,choice,probe;reg sending=0;
genvar g;
generate for(g=0;g<4;g=g+1)begin:PEERS
 localparam [31:0] IP=(g<2)?32'h0a000001+g:32'h0a000101+(g-2);
 localparam [47:0] DM=(g<2)?48'h030000000020+g*2:48'h030000000021+(g-2)*2;
 localparam [47:0] REMOTE_DM=(g<2)?48'h030000000010+g*2:48'h030000000011+(g-2)*2;
 wire [7:0] host_data;wire host_valid,host_error;
 model_reference_rx_filter #(.HOST_IP(IP)) filter(.clk(clk),.rst(rst),.data(a),.valid(ae),.error(aerr),.host_data(host_data),.host_valid(host_valid),.host_error(host_error),.overflows(filter_overflows[g*32+:32]));
 model_foundation_peer #(.LOCAL_MAC(DM),.PEER_MAC(REMOTE_DM),.LOCAL_IP(IP)) peer(
 .clk(clk),.rst(rst),.start(start&&(g<2)),.tx_admit(admit[g]),.rxd(host_data),.dv(host_valid),.er(host_error),
 .txd(peers_tx[g*8+:8]),.txen(peers_en[g]),.txer(peers_err[g]),.errors(peer_errors[g*32+:32]),.reports(),.final_reports(final_reports[g*32+:32]),.lui_seen(lui[g]),.lur_seen(lur[g]),.ntp_seen(ntp[g]));
 assign admit[g]=!pending[g]&&caplen[g]==0&&!(sending&&owner==g)&&(g!=3||clock1_enabled);
end endgenerate
task fail;input [511:0] msg;begin errors=errors+1;$display("FAIL MULTI %0s",msg);end endtask
// Independently associate physical input SOF with the two clocks. Security
// replay and all downstream queues must preserve that arrival, not redate it.
reg raw_previous=0;integer raw_index=0,timestamp_checks=0;
reg [31:0] raw_source=0;reg [15:0] raw_port=0;
reg [63:0] raw_first0,raw_first1,clock_arrival[0:1];
always @(posedge clk)begin
 if(rst)begin raw_previous=0;raw_index=0;timestamp_checks=0;clock_arrival[0]=0;clock_arrival[1]=0;end
 else begin
  if(incoming_valid)begin
   if(!raw_previous)begin
    raw_index=0;
    raw_first0=dut.core.MULTI_SERVICES.plane.LANES[0].ACTIVE.client.utc_ntp;
    raw_first1=dut.core.MULTI_SERVICES.plane.LANES[1].ACTIVE.client.utc_ntp;
   end
   if(raw_index>=34&&raw_index<=37)raw_source={raw_source[23:0],incoming};
   if(raw_index==44||raw_index==45)raw_port={raw_port[7:0],incoming};
   if(raw_index==46&&raw_port==40001)begin
    if(raw_source==32'h0a000101)clock_arrival[0]=raw_first0;
    if(raw_source==32'h0a000102)clock_arrival[1]=raw_first1;
   end
   raw_index=raw_index+1;
  end
  raw_previous=incoming_valid;
 end
end
genvar ts;
generate for(ts=0;ts<2;ts=ts+1)begin:TIMESTAMP_CHECK
 wire [63:0] actual=dut.core.MULTI_SERVICES.plane.LANES[ts].ACTIVE.received_timestamp;
 wire [63:0] delta=actual>clock_arrival[ts]?actual-clock_arrival[ts]:clock_arrival[ts]-actual;
 always @(posedge clk)if(!rst&&dut.core.MULTI_SERVICES.plane.LANES[ts].ACTIVE.rx_valid&&
                         dut.core.MULTI_SERVICES.plane.LANES[ts].ACTIVE.rdp==40001)begin
  timestamp_checks=timestamp_checks+1;
  if((delta<=1)!==1'b1)fail("security queue changed physical NTP arrival timestamp");
 end
end endgenerate
// Reference network serializer: each peer retains an entire frame until sent.
always @(negedge clk)begin
 if(rst)begin incoming_valid=0;pending=0;previous=0;sending=0;gap=0;rr=3;for(k=0;k<4;k=k+1)begin caplen[k]=0;frame_length[k]=0;end end
 else begin
  cycle=cycle+1;incoming_valid=0;
  for(k=0;k<4;k=k+1)begin
   if(peers_en[k])begin
    if(caplen[k]>=1536)fail("reference buffer overflow");else begin net_mem[k*1536+caplen[k]]=peers_tx[k*8+:8];caplen[k]=caplen[k]+1;end
    if(peers_err[k])fail("peer MAC error");
   end else if(previous[k])begin pending[k]=1;frame_length[k]=caplen[k];end
  end
  previous=peers_en;
  if(sending)begin incoming=net_mem[owner*1536+idx];incoming_valid=1;idx=idx+1;
   if(idx==frame_length[owner])begin sending=0;pending[owner]=0;caplen[owner]=0;rr=owner;gap=24;end
  end else if(gap!=0)gap=gap-1;
  else begin choice=-1;for(k=1;k<=4;k=k+1)begin probe=(rr+k)%4;if(choice<0&&pending[probe])choice=probe;end
   if(choice>=0)begin owner=choice;sending=1;idx=0;end
  end
 end
end
reg last_a=0,last_b=0;reg [7:0] abuf[0:1535],bbuf[0:1535];integer ac=0,bc=0,ai,frames_a=0,frames_b=0;
always @(posedge clk)if(!rst)begin
 if(ae)begin abuf[ac]=a;ac=ac+1;if(aerr)fail("A error");end
 else if(last_a)begin $fwrite(wire_log,"A %0t ",$time);for(ai=0;ai<ac;ai=ai+1)$fwrite(wire_log,"%02x",abuf[ai]);$fwrite(wire_log,"\n");ac=0;frames_a=frames_a+1;end
 if(be)begin bbuf[bc]=b;bc=bc+1;if(ber)fail("B error");end
 else if(last_b)begin $fwrite(wire_log,"B %0t ",$time);for(ai=0;ai<bc;ai=ai+1)$fwrite(wire_log,"%02x",bbuf[ai]);$fwrite(wire_log,"\n");bc=0;frames_b=frames_b+1;end
 last_a=ae;last_b=be;
end
initial begin
 wire_log=$fopen("multi_services_wire.txt","w");
 repeat(8)@(negedge clk);rst=0;configure_security;repeat(20)@(negedge clk);start=1;poll=1;@(negedge clk);start=0;poll=0;
 repeat(340000)@(negedge clk);
 if(locked[0]!==1||locked[1]!==0)fail("independent clock timeout/isolation");
 clock1_enabled=1;repeat(20000)@(negedge clk);poll=1;@(negedge clk);poll=0;
 t=0;while((loaded!=3||locked!=3)&&t<1200000)begin @(negedge clk);t=t+1;end
 if(loaded!==3||locked!==3||!rtc_locked||!complete||failed)fail("two loaders/two clocks did not complete");
 if(peer_errors!==0||filter_overflows!==0||overflows!==0||dut.core.MULTI_SERVICES.merge_overflows!==0)fail("peer/queue error");
 if(lui[1:0]!==3||lur[1:0]!==3||final_reports[31:0]!=1||final_reports[63:32]!=1)fail("615A final report evidence");
 for(d=0;d<2;d=d+1)begin
  app_domain=d;
  for(f=0;f<2;f=f+1)begin
   app_file=f;#1;if(!image_valid||generation!=1||file_count!=2||image_length!=(f==0?700:1024))fail("selected bank metadata");
   for(n=0;n<(f==0?700:1024);n=n+1)begin app_address=n;#1;
    if(f==0&&image_data!==PEERS[0].peer.file_a[n])fail("application A bytes");
    if(f==1&&image_data!==PEERS[0].peer.file_b[n])fail("application B bytes");
   end
  end
 end
 app_domain=3;#1;if(image_valid||image_length!=0||image_data!=0)fail("invalid bank selector");
 repeat(100)@(negedge clk);$fclose(wire_log);
 if(sec_overflows!=0||sec_hash_fails!=0||security_violations!=0)fail("security plugin rejects normal baseline flow");
 if(timestamp_checks<3)fail("missing security timestamp checks");
 $display("SECURITY_PHYSICAL_TIMESTAMP_CHECKS=%0d",timestamp_checks);
 $fclose(sec_fd);$display("SEC_CORE_FINAL violations=%0d queue_overflows=%0d hash_failures=%0d",security_violations,sec_overflows,sec_hash_fails);
 $display("MULTI_FINAL loaded=%b clocks=%b frames_a=%0d frames_b=%0d errors=%0d",loaded,locked,frames_a,frames_b,errors);
 if(errors==0)$display("SEC_CORE_MULTI_PASS");else $display("SEC_CORE_MULTI_FAIL");$finish;
end
initial begin #180000000;fail("watchdog");$finish;end
endmodule
