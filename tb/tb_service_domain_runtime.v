`timescale 1ns/1ps
module tb_service_domain_runtime #(parameter integer DOMAINS=2);
localparam integer DW=$clog2(DOMAINS+1),PEER_COUNT=(DOMAINS==1)?1:2*DOMAINS;
localparam [DOMAINS-1:0] ALL={DOMAINS{1'b1}};
reg clk=0;always #40 clk=~clk;reg rst=1,start=0,poll=0;
reg [DW-1:0] app_domain=0;reg [1:0] app_file=0;reg [15:0] app_address=0;
wire [7:0] a,b;wire ae,be,aerr,ber;
reg [7:0] incoming=0;reg incoming_valid=0;
wire [DOMAINS-1:0] loaded,locked,enabled;wire image_valid,loading,complete,failed,rtc_locked;
wire [7:0] image_data;wire [15:0] image_length;wire [31:0] image_crc,generation,overflows;wire [2:0] file_count;
wire [63:0] utc,mono;
integer errors=0,cycle=0,wire_log,byte_index,k,d,f,n,t;
reg network_enable=0,cfg_we=0,cfg_commit=0,cfg_enable=1;
reg [DW-1:0] cfg_domain=0;
reg [31:0] cfg_loader_ip=0,cfg_clock_ip=0;
wire cfg_ready,cfg_error,cfg_pending,commit_pulse;
integer commits=0;
always @(posedge clk)if(!rst&&commit_pulse)commits=commits+1;

AFDX_competition_top #(.SERVICE_DOMAINS(DOMAINS),.SERVICE_BAG_CYCLES(64),.SERVICE_TIMEOUT_CYCLES(300000),.RX_SKEW_MAX_CYCLES(200000)) dut(
 .clk(clk),.rst(rst),.cfg_port_write(1'b0),.cfg_port_index(4'd0),.cfg_port_entry(64'd0),
 .cfg_rx_write(1'b0),.cfg_rx_seal(1'b0),.cfg_rx_index(2'd0),.cfg_rx_entry(168'd0),.cfg_rx_ready(),.cfg_rx_error(),
 .tx_enable(1'b1),.network_a_enable(network_enable),.network_b_enable(network_enable),.cfg_we(1'b0),.cfg_vl_id(2'd0),.cfg_bag(32'd12500),.cfg_destination(8'd2),.cfg_lmax(16'd1518),
 .app_wr_en(1'b0),.app_wr_vl_id(2'd0),.app_wr_data(8'd0),.app_wr_len(16'd0),.app_wr_sof(1'b0),.app_wr_eof(1'b0),.app_wr_ready(),.app_len_error(),.app_wr_accept(),
 .app_wr_subvl(2'd0),.app_wr_use_sap(1'b0),.app_wr_sap(16'd0),.app_wr_partition(3'd0),.app_read_partition(3'd0),.app_read_subvl(2'd0),.app_access_error(),.payload_port(),.payload_sap(),
 .fault_enable(1'b0),.data_a_txd(a),.data_b_txd(b),.data_a_tx_en(ae),.data_b_tx_en(be),.data_a_tx_er(aerr),.data_b_tx_er(ber),.data_a_done(),.data_b_done(),
 .data_a_rxd(incoming),.data_b_rxd(incoming),.data_a_rx_dv(incoming_valid),.data_b_rx_dv(incoming_valid),.data_a_rx_er(1'b0),.data_b_rx_er(1'b0),
 .payload_data(),.payload_valid(),.payload_sof(),.payload_eof(),.payload_network(),.payload_ready(1'b1),.app_read_request(1'b0),.app_read_port(2'd0),.app_read_ready(),.payload_length(),.payload_vl(),.payload_fresh(),
 .management_busy(),.snmp_snapshots(),.snmp_busy_drops(),.shared_rx_accepted(),.shared_rx_duplicates(),.shared_rx_dropped(),.shared_tx_overflows(overflows),.physical_a_frames(),.physical_b_frames(),
 .loader_ip(32'h0a000001),.time_server_ip(32'h0a000101),.hardware_length(6'd3),.hardware_id({232'd0,24'h4d4953}),
 .service_cfg_we(cfg_we),.service_cfg_domain(cfg_domain),.service_cfg_loader_ip(cfg_loader_ip),.service_cfg_clock_ip(cfg_clock_ip),
 .service_cfg_enable(cfg_enable),.service_cfg_commit(cfg_commit),.service_cfg_ready(cfg_ready),.service_cfg_error(cfg_error),.service_cfg_pending(cfg_pending),.service_cfg_commit_pulse(commit_pulse),.service_enabled(enabled),
 .service_app_domain(app_domain),.service_loaded(loaded),.service_clock_locked(locked),.app_file(app_file),.rtc_poll(poll),.rtc_locked(rtc_locked),.utc_ntp(utc),.monotonic_ticks(mono),
 .image_valid(image_valid),.image_length(image_length),.image_crc(image_crc),.package_generation(generation),.package_file_count(file_count),.image_read_address(app_address),.image_read_data(image_data),.loading(loading),.load_complete(complete),.load_failed(failed));
wire [PEER_COUNT*8-1:0] peers_tx;wire [PEER_COUNT-1:0] peers_en,peers_err;wire [PEER_COUNT*32-1:0] peer_errors,filter_overflows,final_reports;
wire [PEER_COUNT-1:0] lui,lur,ntp;wire [PEER_COUNT-1:0] admit;

reg [7:0] net_mem[0:PEER_COUNT*1536-1];integer caplen[0:PEER_COUNT-1],frame_length[0:PEER_COUNT-1];reg [PEER_COUNT-1:0] previous=0,pending=0;
integer owner=0,rr=PEER_COUNT-1,idx=0,gap=0,choice,probe;reg sending=0;
genvar g;
generate for(g=0;g<PEER_COUNT;g=g+1)begin:PEERS
 localparam [31:0] IP=(g<DOMAINS)?32'h0a010001+g:32'h0a010101+(g-DOMAINS);
 localparam [47:0] DM=(g<DOMAINS)?(DOMAINS==1?48'h030000000012:48'h030000000020+g*2):48'h030000000021+(g-DOMAINS)*2;
 localparam [47:0] REMOTE_DM=(g<DOMAINS)?(DOMAINS==1?48'h030000000010:48'h030000000010+g*2):48'h030000000011+(g-DOMAINS)*2;
 wire [7:0] host_data;wire host_valid,host_error;
 model_reference_rx_filter #(.HOST_IP(IP)) filter(.clk(clk),.rst(rst),.data(a),.valid(ae),.error(aerr),.host_data(host_data),.host_valid(host_valid),.host_error(host_error),.overflows(filter_overflows[g*32+:32]));
 model_foundation_peer #(.LOCAL_MAC(DM),.PEER_MAC(REMOTE_DM),.LOCAL_IP(IP)) peer(
 .clk(clk),.rst(rst),.start(start&&(g<DOMAINS)),.tx_admit(admit[g]),.rxd(host_data),.dv(host_valid),.er(host_error),
 .txd(peers_tx[g*8+:8]),.txen(peers_en[g]),.txer(peers_err[g]),.errors(peer_errors[g*32+:32]),.reports(),.final_reports(final_reports[g*32+:32]),.lui_seen(lui[g]),.lur_seen(lur[g]),.ntp_seen(ntp[g]));
 assign admit[g]=!pending[g]&&caplen[g]==0&&!(sending&&owner==g);
end endgenerate
task fail;input [511:0] msg;begin errors=errors+1;$display("FAIL MULTI %0s",msg);end endtask
// Reference network serializer: each peer retains an entire frame until sent.
always @(negedge clk)begin
 if(rst)begin incoming_valid=0;pending=0;previous=0;sending=0;gap=0;rr=PEER_COUNT-1;for(k=0;k<PEER_COUNT;k=k+1)begin caplen[k]=0;frame_length[k]=0;end end
 else begin
  cycle=cycle+1;incoming_valid=0;
  for(k=0;k<PEER_COUNT;k=k+1)begin
   if(peers_en[k])begin
    if(caplen[k]>=1536)fail("reference buffer overflow");else begin net_mem[k*1536+caplen[k]]=peers_tx[k*8+:8];caplen[k]=caplen[k]+1;end
    if(peers_err[k])fail("peer MAC error");
   end else if(previous[k])begin pending[k]=1;frame_length[k]=caplen[k];end
  end
  previous=peers_en;
  if(sending)begin incoming=net_mem[owner*1536+idx];incoming_valid=1;idx=idx+1;
   if(idx==frame_length[owner])begin sending=0;pending[owner]=0;caplen[owner]=0;rr=owner;gap=24;end
  end else if(gap!=0)gap=gap-1;
  else begin choice=-1;for(k=1;k<=PEER_COUNT;k=k+1)begin probe=(rr+k)%PEER_COUNT;if(choice<0&&pending[probe])choice=probe;end
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
task write_config;
 input integer domain;input en;
 begin
  @(negedge clk);cfg_domain=domain;cfg_loader_ip=32'h0a010001+domain;cfg_clock_ip=(DOMAINS==1)?32'h0a010001:32'h0a010101+domain;cfg_enable=en;cfg_we=1;
  #1;if(!cfg_ready)fail("configuration not ready");
  @(negedge clk);cfg_we=0;#1;if(cfg_error)fail("valid configuration rejected");
 end
endtask
task request_commit;
 begin @(negedge clk);cfg_commit=1;@(negedge clk);cfg_commit=0;end
endtask
task await_commit;
 begin
  t=0;while(!commit_pulse&&t<500000)begin @(negedge clk);t=t+1;end
  if(!commit_pulse)fail("commit timeout");
  @(negedge clk);if(commit_pulse||cfg_pending)fail("commit must be one pulse and release pending");
 end
endtask
task invalid_selection;
 begin
  #1;if({image_valid,image_length,image_crc,generation,file_count,image_data,utc,mono}!==0)
   fail("invalid/disabled selector did not zero all outputs");
 end
endtask
initial begin
 wire_log=$fopen("service_domain_runtime_wire.txt","w");
 repeat(8)@(negedge clk);rst=0;repeat(20)@(negedge clk);
 if($bits(dut.service_app_domain)!=DW||$bits(dut.service_loaded)!=DOMAINS||$bits(dut.SERVICE_LOADER_IPS)!=32*DOMAINS)
  fail("top parameter width");
 if(enabled!==ALL||loaded!==0||locked!==0||complete||rtc_locked)fail("reset masks");
 for(d=0;d<DOMAINS;d=d+1)begin
  if(dut.MULTI_SERVICES.plane.active_loader_ips[d*32+:32]!==32'h0a000001+d)fail("default IP lane");
  write_config(d,1);
 end
 // Shadow writes cannot change any active endpoint or mask.
 for(d=0;d<DOMAINS;d=d+1)
  if(dut.MULTI_SERVICES.plane.active_loader_ips[d*32+:32]!==32'h0a000001+d)fail("shadow write leaked");
 // Outstanding real NTP requests and blocked egress must defer the commit.
 poll=1;@(negedge clk);poll=0;repeat(2000)@(negedge clk);
 request_commit;
 repeat(100)begin @(negedge clk);if(commit_pulse||!cfg_pending)fail("busy commit applied early");end
 cfg_we=1;@(negedge clk);cfg_we=0;#1;if(!cfg_error)fail("write accepted while pending");
 network_enable=1;
 await_commit;
 for(d=0;d<DOMAINS;d=d+1)begin
  if(dut.MULTI_SERVICES.plane.active_loader_ips[d*32+:32]!==32'h0a010001+d||
     dut.MULTI_SERVICES.plane.active_clock_ips[d*32+:32]!==((DOMAINS==1)?32'h0a010001:32'h0a010101+d))fail("atomic endpoint commit");
 end
 // All traffic below uses runtime-configured addresses through the real top.
 start=1;poll=1;@(negedge clk);start=0;poll=0;
 t=0;while((loaded!==ALL||locked!==ALL)&&t<1800000)begin @(negedge clk);t=t+1;end
 if(loaded!==ALL||locked!==ALL||!rtc_locked||!complete||failed)begin $display("RUNTIME_STATE loaded=%b locked=%b rtc=%b complete=%b failed=%b loading=%b enabled=%b",loaded,locked,rtc_locked,complete,failed,loading,enabled);fail("all loaders/clocks did not complete");end
 if(peer_errors!==0||filter_overflows!==0||overflows!==0||dut.MULTI_SERVICES.merge_overflows!==0)fail("peer/queue error");
 if(lui[DOMAINS-1:0]!==ALL||lur[DOMAINS-1:0]!==ALL)fail("per-domain upload evidence");
 for(d=0;d<DOMAINS;d=d+1)begin
  if(final_reports[d*32+:32]!=1)fail("per-domain final report");
  app_domain=d;
  for(f=0;f<2;f=f+1)begin
   app_file=f;#1;if(!image_valid||generation!=1||file_count!=2||image_length!=(f==0?700:1024))fail("selected bank metadata");
   for(n=0;n<(f==0?700:1024);n=n+1)begin app_address=n;#1;
    if(f==0&&image_data!==PEERS[0].peer.file_a[n])fail("application A bytes");
    if(f==1&&image_data!==PEERS[0].peer.file_b[n])fail("application B bytes");
   end
  end
 end
 // Include all unused selector codes (not just one sentinel), X, and Z.
 for(d=DOMAINS;d<(1<<DW);d=d+1)begin app_domain=d;invalid_selection;end
 app_domain={DW{1'bx}};invalid_selection;
 if(DOMAINS!=1)begin app_domain={DW{1'bz}};invalid_selection;end
 // The ninth domain must disable independently of domain zero.
 write_config(DOMAINS-1,0);request_commit;await_commit;
 if(enabled!==(ALL>>1)||loaded!==(ALL>>1)||locked!==(ALL>>1))fail("disabled-domain masks");
 if(complete!==(DOMAINS>1)||rtc_locked!==(DOMAINS>1))fail("enabled-domain aggregate");
 app_domain=DOMAINS-1;invalid_selection;
 // Re-enable clears old package/clock state and must withhold aggregate ready.
 write_config(DOMAINS-1,1);request_commit;await_commit;
 if(enabled!==ALL||loaded[DOMAINS-1]||locked[DOMAINS-1]||complete||rtc_locked)fail("re-enable stale readiness");
 for(d=0;d<DOMAINS;d=d+1)write_config(d,0);
 request_commit;await_commit;
 if(enabled!==0||loaded!==0||locked!==0||complete||rtc_locked||loading||failed)fail("empty active set");
 // Invalid index and simultaneous write+commit cannot alter either bank.
 @(negedge clk);cfg_domain=DOMAINS;cfg_we=1;#1;if(cfg_ready)fail("invalid index ready");
 @(negedge clk);cfg_we=0;#1;if(!cfg_error)fail("invalid write accepted");
 @(negedge clk);cfg_domain={DW{1'bx}};cfg_we=1;
 @(negedge clk);cfg_we=0;#1;if(!cfg_error)fail("unknown write accepted");
 @(negedge clk);cfg_domain=0;cfg_we=1;cfg_commit=1;
 @(negedge clk);cfg_we=0;cfg_commit=0;#1;if(!cfg_error||cfg_pending||commit_pulse)fail("write/commit collision");
 repeat(100)@(negedge clk);$fclose(wire_log);
 if(commits!=4)fail("commit count");
 $display("DOMAIN_RUNTIME domains=%0d width=%0d commits=%0d frames_a=%0d frames_b=%0d errors=%0d",DOMAINS,DW,commits,frames_a,frames_b,errors);
 if(errors==0)$display("TB_SERVICE_DOMAIN_RUNTIME_PASS");else $display("TB_SERVICE_DOMAIN_RUNTIME_FAIL");$finish;
end
initial begin #240000000;fail("watchdog");$finish;end
endmodule





