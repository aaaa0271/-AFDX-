set afdx_replay_dir [file dirname [file normalize [info script]]]
# Recorded data only. This file does not drive or rerun the design.
catch {view wave}
catch {view structure}
catch {view objects}
catch {view transcript}
catch {delete wave *}
add wave -noupdate -divider {01_MAC_and_delivery}
add wave -noupdate -radix binary {afdx:/tb_defense_live/a_valid}
add wave -noupdate -radix binary {afdx:/tb_defense_live/b_valid}
add wave -noupdate -radix binary {afdx:/tb_defense_live/pv}
add wave -noupdate -radix unsigned {afdx:/tb_defense_live/payload_frames}
add wave -noupdate -divider {02_Loading_and_RTC}
add wave -noupdate -radix binary {afdx:/tb_defense_live/locked}
add wave -noupdate -radix unsigned {afdx:/tb_defense_live/package_generation}
add wave -noupdate -divider {03_Security}
add wave -noupdate -radix binary {afdx:/tb_defense_live/sec_mode}
add wave -noupdate -radix unsigned {afdx:/tb_defense_live/sec_block}
add wave -noupdate -divider {04_Mimic}
add wave -noupdate -radix unsigned {afdx:/tb_defense_live/forwarded}
add wave -noupdate -radix unsigned {afdx:/tb_defense_live/timeouts}
add wave -noupdate -divider {05_Hardware_TCN}
add wave -noupdate -radix unsigned {afdx:/tb_defense_live/ai_results}
add wave -noupdate -radix binary {afdx:/tb_defense_live/ai_block}
add wave -noupdate -divider {06_Testbench}
add wave -noupdate -radix unsigned {afdx:/tb_defense_live/errors}
catch {configure wave -namecolwidth 235}
catch {configure wave -valuecolwidth 90}
catch {configure wave -signalnamewidth 1}
catch {configure wave -timelineunits us}
update
wave zoom full
wave refresh
echo {RECORDED OVERVIEW: ModelSim + native host integration; not a board test.}
set afdx_summary_file [file join $afdx_capture_dir overview_summary.txt]
if {[file exists $afdx_summary_file]} {
    set afdx_read_fd [open $afdx_summary_file r]
    echo [read $afdx_read_fd]
    close $afdx_read_fd
} else {echo {NO VERIFIED SUMMARY IS AVAILABLE.}}
