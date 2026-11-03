set afdx_replay_dir [file dirname [file normalize [info script]]]
dataset open [file join $afdx_replay_dir {tcn.wlf}] afdx
dataset current afdx
view wave
catch {view structure}
catch {view transcript}
catch {delete wave *}
add wave -noupdate -divider {Input}
add wave -noupdate -radix unsigned {afdx:/tb_tcn_plugin/clk}
add wave -noupdate -radix unsigned {afdx:/tb_tcn_plugin/job_id}
add wave -noupdate -radix unsigned {afdx:/tb_tcn_plugin/job_valid}
add wave -noupdate -radix unsigned {afdx:/tb_tcn_plugin/job_ready}
add wave -noupdate -radix unsigned {afdx:/tb_tcn_plugin/feature_valid}
add wave -noupdate -radix unsigned {afdx:/tb_tcn_plugin/feature_ready}
add wave -noupdate -radix unsigned {afdx:/tb_tcn_plugin/feature_last}
add wave -noupdate -divider {Result}
add wave -noupdate -radix unsigned {afdx:/tb_tcn_plugin/result_valid}
add wave -noupdate -radix unsigned {afdx:/tb_tcn_plugin/result_ready}
add wave -noupdate -radix unsigned {afdx:/tb_tcn_plugin/result_compute_cycles}
add wave -noupdate -radix unsigned {afdx:/tb_tcn_plugin/result_status}
add wave -noupdate -radix unsigned {afdx:/tb_tcn_plugin/result_logits}
add wave -noupdate -divider {Verification}
add wave -noupdate -radix unsigned {afdx:/tb_tcn_plugin/vector_index}
add wave -noupdate -radix unsigned {afdx:/tb_tcn_plugin/protocol_cases}
configure wave -timelineunits us
configure wave -namecolwidth 230
configure wave -signalnamewidth 1
update
wave cursor add -time {40840.0 ns} -name {Last_feature_accepted}
wave cursor add -time {1163640.0 ns} -name {Result_valid}
wave zoom range 32840.0ns 1171640.0ns
echo {FIRST VECTOR: last feature accepted at 40840.0 ns; result valid at 1163640.0 ns.}
echo {DELTA: 14035 cycles x 80 ns = 1122.8 us.}
set afdx_fd [open [file join $afdx_replay_dir {result.log}] r]
echo [read $afdx_fd]
close $afdx_fd
