`timescale 1ns/1ps
module tb_security_bypass;
wire [31:0] base_errors,plugin_errors;wire base_finished,plugin_finished;integer errors=0,checks=0;
model_security_baseline #(.MODE(1)) baseline(.errors(base_errors),.finished(base_finished));
model_security_plugin #(.MODE(1)) wrapped(.errors(plugin_errors),.finished(plugin_finished));
always @(negedge baseline.clk)if(!baseline.rst)begin
 checks=checks+1;
 if(baseline.cfg_rx_ready!==wrapped.cfg_rx_ready)begin errors=errors+1;$display("BYPASS_MISMATCH signal=cfg_rx_ready cycle=%0d",checks);end
 if(baseline.cfg_rx_error!==wrapped.cfg_rx_error)begin errors=errors+1;$display("BYPASS_MISMATCH signal=cfg_rx_error cycle=%0d",checks);end
 if(baseline.app_wr_ready!==wrapped.app_wr_ready)begin errors=errors+1;$display("BYPASS_MISMATCH signal=app_wr_ready cycle=%0d",checks);end
 if(baseline.app_len_error!==wrapped.app_len_error)begin errors=errors+1;$display("BYPASS_MISMATCH signal=app_len_error cycle=%0d",checks);end
 if(baseline.app_wr_accept!==wrapped.app_wr_accept)begin errors=errors+1;$display("BYPASS_MISMATCH signal=app_wr_accept cycle=%0d",checks);end
 if(baseline.data_a_txd!==wrapped.data_a_txd)begin errors=errors+1;$display("BYPASS_MISMATCH signal=data_a_txd cycle=%0d",checks);end
 if(baseline.data_b_txd!==wrapped.data_b_txd)begin errors=errors+1;$display("BYPASS_MISMATCH signal=data_b_txd cycle=%0d",checks);end
 if(baseline.data_a_tx_en!==wrapped.data_a_tx_en)begin errors=errors+1;$display("BYPASS_MISMATCH signal=data_a_tx_en cycle=%0d",checks);end
 if(baseline.data_b_tx_en!==wrapped.data_b_tx_en)begin errors=errors+1;$display("BYPASS_MISMATCH signal=data_b_tx_en cycle=%0d",checks);end
 if(baseline.data_a_tx_er!==wrapped.data_a_tx_er)begin errors=errors+1;$display("BYPASS_MISMATCH signal=data_a_tx_er cycle=%0d",checks);end
 if(baseline.data_b_tx_er!==wrapped.data_b_tx_er)begin errors=errors+1;$display("BYPASS_MISMATCH signal=data_b_tx_er cycle=%0d",checks);end
 if(baseline.data_a_done!==wrapped.data_a_done)begin errors=errors+1;$display("BYPASS_MISMATCH signal=data_a_done cycle=%0d",checks);end
 if(baseline.data_b_done!==wrapped.data_b_done)begin errors=errors+1;$display("BYPASS_MISMATCH signal=data_b_done cycle=%0d",checks);end
 if(baseline.payload_data!==wrapped.payload_data)begin errors=errors+1;$display("BYPASS_MISMATCH signal=payload_data cycle=%0d",checks);end
 if(baseline.payload_valid!==wrapped.payload_valid)begin errors=errors+1;$display("BYPASS_MISMATCH signal=payload_valid cycle=%0d",checks);end
 if(baseline.payload_sof!==wrapped.payload_sof)begin errors=errors+1;$display("BYPASS_MISMATCH signal=payload_sof cycle=%0d",checks);end
 if(baseline.payload_eof!==wrapped.payload_eof)begin errors=errors+1;$display("BYPASS_MISMATCH signal=payload_eof cycle=%0d",checks);end
 if(baseline.payload_network!==wrapped.payload_network)begin errors=errors+1;$display("BYPASS_MISMATCH signal=payload_network cycle=%0d",checks);end
 if(baseline.management_busy!==wrapped.management_busy)begin errors=errors+1;$display("BYPASS_MISMATCH signal=management_busy cycle=%0d",checks);end
 if(baseline.snmp_snapshots!==wrapped.snmp_snapshots)begin errors=errors+1;$display("BYPASS_MISMATCH signal=snmp_snapshots cycle=%0d",checks);end
 if(baseline.snmp_busy_drops!==wrapped.snmp_busy_drops)begin errors=errors+1;$display("BYPASS_MISMATCH signal=snmp_busy_drops cycle=%0d",checks);end
 if(baseline.shared_rx_accepted!==wrapped.shared_rx_accepted)begin errors=errors+1;$display("BYPASS_MISMATCH signal=shared_rx_accepted cycle=%0d",checks);end
 if(baseline.shared_rx_duplicates!==wrapped.shared_rx_duplicates)begin errors=errors+1;$display("BYPASS_MISMATCH signal=shared_rx_duplicates cycle=%0d",checks);end
 if(baseline.shared_rx_dropped!==wrapped.shared_rx_dropped)begin errors=errors+1;$display("BYPASS_MISMATCH signal=shared_rx_dropped cycle=%0d",checks);end
 if(baseline.shared_tx_overflows!==wrapped.shared_tx_overflows)begin errors=errors+1;$display("BYPASS_MISMATCH signal=shared_tx_overflows cycle=%0d",checks);end
 if(baseline.physical_a_frames!==wrapped.physical_a_frames)begin errors=errors+1;$display("BYPASS_MISMATCH signal=physical_a_frames cycle=%0d",checks);end
 if(baseline.physical_b_frames!==wrapped.physical_b_frames)begin errors=errors+1;$display("BYPASS_MISMATCH signal=physical_b_frames cycle=%0d",checks);end
 if(baseline.rtc_locked!==wrapped.rtc_locked)begin errors=errors+1;$display("BYPASS_MISMATCH signal=rtc_locked cycle=%0d",checks);end
 if(baseline.image_valid!==wrapped.image_valid)begin errors=errors+1;$display("BYPASS_MISMATCH signal=image_valid cycle=%0d",checks);end
 if(baseline.loading!==wrapped.loading)begin errors=errors+1;$display("BYPASS_MISMATCH signal=loading cycle=%0d",checks);end
 if(baseline.load_complete!==wrapped.load_complete)begin errors=errors+1;$display("BYPASS_MISMATCH signal=load_complete cycle=%0d",checks);end
 if(baseline.load_failed!==wrapped.load_failed)begin errors=errors+1;$display("BYPASS_MISMATCH signal=load_failed cycle=%0d",checks);end
 if(baseline.utc_ntp!==wrapped.utc_ntp)begin errors=errors+1;$display("BYPASS_MISMATCH signal=utc_ntp cycle=%0d",checks);end
 if(baseline.monotonic_ticks!==wrapped.monotonic_ticks)begin errors=errors+1;$display("BYPASS_MISMATCH signal=monotonic_ticks cycle=%0d",checks);end
 if(baseline.image_length!==wrapped.image_length)begin errors=errors+1;$display("BYPASS_MISMATCH signal=image_length cycle=%0d",checks);end
 if(baseline.image_crc!==wrapped.image_crc)begin errors=errors+1;$display("BYPASS_MISMATCH signal=image_crc cycle=%0d",checks);end
 if(baseline.package_generation!==wrapped.package_generation)begin errors=errors+1;$display("BYPASS_MISMATCH signal=package_generation cycle=%0d",checks);end
 if(baseline.package_file_count!==wrapped.package_file_count)begin errors=errors+1;$display("BYPASS_MISMATCH signal=package_file_count cycle=%0d",checks);end
 if(baseline.image_read_data!==wrapped.image_read_data)begin errors=errors+1;$display("BYPASS_MISMATCH signal=image_read_data cycle=%0d",checks);end
end
initial begin
 wait(base_finished&&plugin_finished);#1;
 if(base_errors!=0||plugin_errors!=0)begin errors=errors+1;$display("BYPASS_BASELINE_ERRORS base=%0d plugin=%0d",base_errors,plugin_errors);end
 $display("BYPASS_FINAL cycles=%0d signals=39 errors=%0d",checks,errors);
 if(errors==0)$display("SEC_BYPASS_PASS");else $display("SEC_BYPASS_FAIL");$finish;
end
initial begin #200000000;$display("BYPASS_TIMEOUT");$finish;end
endmodule
