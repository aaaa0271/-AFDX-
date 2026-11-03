set afdx_replay_dir [file dirname [file normalize [info script]]]
dataset open [file join $afdx_replay_dir {signals.wlf}] afdx
dataset current afdx
view wave
catch {view structure}
catch {view transcript}
catch {delete wave *}
add wave -noupdate -divider {Request}
add wave -noupdate -radix unsigned {afdx:/tb_mimic_quorum/clk}
add wave -noupdate -radix unsigned {afdx:/tb_mimic_quorum/rst}
add wave -noupdate -radix unsigned {afdx:/tb_mimic_quorum/request_id}
add wave -noupdate -radix unsigned {afdx:/tb_mimic_quorum/start}
add wave -noupdate -radix unsigned {afdx:/tb_mimic_quorum/response_valid}
add wave -noupdate -radix unsigned {afdx:/tb_mimic_quorum/response_allow}
add wave -noupdate -divider {Baseline_priority}
add wave -noupdate -radix unsigned {afdx:/tb_mimic_quorum/baseline_valid}
add wave -noupdate -radix unsigned {afdx:/tb_mimic_quorum/baseline_allow}
add wave -noupdate -radix unsigned {afdx:/tb_mimic_quorum/quorum_valid}
add wave -noupdate -radix unsigned {afdx:/tb_mimic_quorum/allow}
add wave -noupdate -divider {Result}
add wave -noupdate -radix unsigned {afdx:/tb_mimic_quorum/done}
add wave -noupdate -radix unsigned {afdx:/tb_mimic_quorum/result_reason}
add wave -noupdate -radix unsigned {afdx:/tb_mimic_quorum/passed}
add wave -noupdate -radix unsigned {afdx:/tb_mimic_quorum/failures}
configure wave -timelineunits us
configure wave -namecolwidth 230
configure wave -signalnamewidth 1
update
wave zoom range 0ns 817ns
set afdx_fd [open [file join $afdx_replay_dir {result.log}] r]
echo [read $afdx_fd]
close $afdx_fd
