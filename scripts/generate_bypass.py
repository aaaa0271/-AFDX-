from pathlib import Path
R=Path(__file__).resolve().parents[1]
s=(R/'reference_core/tb/model_foundation_system.v').read_text()
s=s.replace('output reg [31:0] errors=0,output reg finished=0','output reg [31:0] errors,output reg finished')
s=s.replace(');',');\ninitial begin errors=0;finished=0;end',1)
for kind in ('baseline','plugin'):
 text=s.replace('module model_foundation_system #(',f'module model_security_{kind} #(',1)
 text=text.replace('"shared_wire.txt"',f'"{kind}_shared_wire.txt"').replace('"service_wire.txt"',f'"{kind}_service_wire.txt"')
 if kind=='plugin':
  text=text.replace('AFDX_competition_top #(','AFDX_security_plugin_top #(.SECURITY_BOOT_MODE(0),',1)
  # Internal references remain test-only, routed through the unchanged core.
  text=text.replace('dut.','dut.core.')
 (R/f'tb/model_security_{kind}.v').write_text('// Semantics-preserving test copy; original source remains frozen.\n'+text)
signals=['cfg_rx_ready','cfg_rx_error','app_wr_ready','app_len_error','app_wr_accept','data_a_txd','data_b_txd','data_a_tx_en','data_b_tx_en','data_a_tx_er','data_b_tx_er','data_a_done','data_b_done','payload_data','payload_valid','payload_sof','payload_eof','payload_network','management_busy','snmp_snapshots','snmp_busy_drops','shared_rx_accepted','shared_rx_duplicates','shared_rx_dropped','shared_tx_overflows','physical_a_frames','physical_b_frames','rtc_locked','image_valid','loading','load_complete','load_failed','utc_ntp','monotonic_ticks','image_length','image_crc','package_generation','package_file_count','image_read_data']
text='''`timescale 1ns/1ps
module tb_security_bypass;
wire [31:0] base_errors,plugin_errors;wire base_finished,plugin_finished;integer errors=0,checks=0;
model_security_baseline #(.MODE(1)) baseline(.errors(base_errors),.finished(base_finished));
model_security_plugin #(.MODE(1)) wrapped(.errors(plugin_errors),.finished(plugin_finished));
always @(negedge baseline.clk)if(!baseline.rst)begin
 checks=checks+1;
'''
for sig in signals:text+=f' if(baseline.{sig}!==wrapped.{sig})begin errors=errors+1;$display("BYPASS_MISMATCH signal={sig} cycle=%0d",checks);end\n'
text+='''end
initial begin
 wait(base_finished&&plugin_finished);#1;
 if(base_errors!=0||plugin_errors!=0)begin errors=errors+1;$display("BYPASS_BASELINE_ERRORS base=%0d plugin=%0d",base_errors,plugin_errors);end
 $display("BYPASS_FINAL cycles=%0d signals=39 errors=%0d",checks,errors);
 if(errors==0)$display("SEC_BYPASS_PASS");else $display("SEC_BYPASS_FAIL");$finish;
end
initial begin #200000000;$display("BYPASS_TIMEOUT");$finish;end
endmodule
'''
(R/'tb/tb_security_bypass.v').write_text(text)
print('bypass equivalence compares',len(signals),'live signals each cycle')
