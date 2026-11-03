`timescale 1ns/1ps
module tb_contest_configuration;
reg clk=0;always #5 clk=~clk;reg rst=1,we=0,seal=0,present=1,enabled=1;reg [1:0] index=0;
reg [47:0] mac=48'h030000001234;reg [31:0] sip=32'h0a000001,dip=32'h0a000002;reg [15:0] sp=10000,dp=10001,maxlen=1518;
wire [671:0] cfg;wire sealed,ce;reg meta=0;reg [47:0] dm=0;reg [31:0] si=0,di=0;reg [15:0] us=0,ud=0;reg [10:0] plen=0;
wire result,accept,reject;wire [1:0] vidx;wire [15:0] vid;wire [10:0] lim;wire unknown,disabled,iperr,udperr,lenerr;
integer errors=0,queries=0;
afdx_rx_config_bank bank(.clk(clk),.rst(rst),.write(we),.seal(seal),.index(index),.present(present),.enabled(enabled),.dst_mac(mac),.src_ip(sip),.dst_ip(dip),.src_port(sp),.dst_port(dp),.lmax(maxlen),.config_table(cfg),.sealed(sealed),.error(ce));
afdx_vl_identifier #(.CONFIGURABLE(1)) dut(.clk(clk),.rst(rst),.cfg_table(cfg),.meta_valid(meta),.dst_mac(dm),.src_ip(si),.dst_ip(di),.udp_src_port(us),.udp_dst_port(ud),.payload_length(plen),.result_valid(result),.vl_accept(accept),.vl_reject(reject),.vl_index(vidx),.vl_id(vid),.vl_lmax(lim),.unknown_vl_error(unknown),.disabled_vl_error(disabled),.ip_whitelist_error(iperr),.udp_whitelist_error(udperr),.length_whitelist_error(lenerr));
task fail;input [511:0] x;begin errors=errors+1;$display("FAIL CONFIG %0s",x);end endtask
task write_row;input integer n;input expecterror;begin @(negedge clk);we=1;index=n;@(negedge clk);we=0;if(ce!==expecterror)fail("configuration rejection");end endtask
task check;input integer reason;begin
 @(negedge clk);meta=1;@(negedge clk);meta=0;queries=queries+1;
 if(!result||accept!==(reason==0)||reject!==(reason!=0))fail("admission");
 if(unknown!==(reason==1)||disabled!==(reason==2)||iperr!==(reason==3)||udperr!==(reason==4)||lenerr!==(reason==5))fail("rejection reason");
end endtask
initial begin
 repeat(4)@(negedge clk);rst=0;dm=mac;si=sip;di=dip;us=sp;ud=dp;plen=1471;
 check(1);write_row(0,0);check(0);if(lim!=1471)fail("frame LMAX conversion");
 write_row(1,1); // duplicate destination cannot shadow an existing VL
 maxlen=63;mac=48'h030000001235;write_row(1,1);maxlen=64;write_row(1,0);
 dm=mac;plen=17;check(0);plen=18;check(5);
 enabled=0;mac=48'h030000001236;write_row(2,0);dm=mac;check(2);
 dm=48'h030000001234;plen=1471;si=sip+1;check(3);si=sip;us=sp+1;check(4);us=sp;
 dm=48'h020000001234;check(1); // low16 match alone is insufficient
 dm=48'h030000001234;check(0);
 @(negedge clk);seal=1;@(negedge clk);seal=0;
 enabled=1;mac=48'h030000001234;maxlen=64;write_row(0,1);check(0);if(!sealed||lim!=1471)fail("sealed policy mutated");
 $display("CONFIG_QUERIES=%0d ERRORS=%0d",queries,errors);
 if(errors==0)$display("TB_CONTEST_CONFIGURATION_PASS");else $display("TB_CONTEST_CONFIGURATION_FAIL");$finish;
end
endmodule
