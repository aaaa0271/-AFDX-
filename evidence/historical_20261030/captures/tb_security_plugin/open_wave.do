set afdx_replay_dir [file dirname [file normalize [info script]]]
dataset open [file join $afdx_replay_dir {signals.wlf}] afdx
dataset current afdx
view wave
catch {view structure}
catch {view transcript}
catch {delete wave *}
add wave -noupdate -divider {Case_and_input}
add wave -noupdate -radix unsigned {afdx:/tb_security_plugin/clk}
add wave -noupdate -radix unsigned {afdx:/tb_security_plugin/rst}
add wave -noupdate -radix unsigned {afdx:/tb_security_plugin/case_id}
add wave -noupdate -radix unsigned {afdx:/tb_security_plugin/mode}
add wave -noupdate -radix unsigned {afdx:/tb_security_plugin/input_valid}
add wave -noupdate -radix hexadecimal {afdx:/tb_security_plugin/input_data}
add wave -noupdate -divider {Release_to_core}
add wave -noupdate -radix unsigned {afdx:/tb_security_plugin/core_valid}
add wave -noupdate -radix hexadecimal {afdx:/tb_security_plugin/core_data}
add wave -noupdate -radix unsigned {afdx:/tb_security_plugin/wire_count}
add wave -noupdate -divider {Security_evidence}
add wave -noupdate -radix unsigned {afdx:/tb_security_plugin/ev}
add wave -noupdate -radix hexadecimal {afdx:/tb_security_plugin/event_record}
add wave -noupdate -radix hexadecimal {afdx:/tb_security_plugin/last_event}
add wave -noupdate -radix unsigned {afdx:/tb_security_plugin/events}
add wave -noupdate -radix unsigned {afdx:/tb_security_plugin/wa}
add wave -noupdate -radix unsigned {afdx:/tb_security_plugin/wb}
add wave -noupdate -radix unsigned {afdx:/tb_security_plugin/errors}
configure wave -timelineunits us
configure wave -namecolwidth 230
configure wave -signalnamewidth 1
update
wave zoom range 0ns 31961440ns
set afdx_fd [open [file join $afdx_replay_dir {result.log}] r]
echo [read $afdx_fd]
close $afdx_fd
set afdx_fd [open [file join $afdx_replay_dir {verify_plugin_wire.log}] r]
echo [read $afdx_fd]
close $afdx_fd
