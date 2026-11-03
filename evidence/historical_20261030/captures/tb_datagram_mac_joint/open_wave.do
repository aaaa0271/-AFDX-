set afdx_replay_dir [file dirname [file normalize [info script]]]
dataset open [file join $afdx_replay_dir {signals.wlf}] afdx
dataset current afdx
view wave
catch {view structure}
catch {view transcript}
catch {delete wave *}
add wave -noupdate -divider {A_B_links}
add wave -noupdate -radix unsigned {afdx:/tb_datagram_mac_joint/exercise/data_a_tx_en}
add wave -noupdate -radix hexadecimal {afdx:/tb_datagram_mac_joint/exercise/data_a_txd}
add wave -noupdate -radix unsigned {afdx:/tb_datagram_mac_joint/exercise/data_b_tx_en}
add wave -noupdate -radix hexadecimal {afdx:/tb_datagram_mac_joint/exercise/data_b_txd}
add wave -noupdate -radix unsigned {afdx:/tb_datagram_mac_joint/exercise/network_a_valid}
add wave -noupdate -radix unsigned {afdx:/tb_datagram_mac_joint/exercise/network_b_valid}
add wave -noupdate -divider {Application_delivery}
add wave -noupdate -radix unsigned {afdx:/tb_datagram_mac_joint/exercise/payload_valid}
add wave -noupdate -radix unsigned {afdx:/tb_datagram_mac_joint/exercise/payload_sof}
add wave -noupdate -radix unsigned {afdx:/tb_datagram_mac_joint/exercise/payload_eof}
add wave -noupdate -radix hexadecimal {afdx:/tb_datagram_mac_joint/exercise/payload_data}
add wave -noupdate -radix unsigned {afdx:/tb_datagram_mac_joint/exercise/business_frames}
add wave -noupdate -radix unsigned {afdx:/tb_datagram_mac_joint/exercise/business_bytes}
add wave -noupdate -divider {Basic_services}
add wave -noupdate -radix unsigned {afdx:/tb_datagram_mac_joint/exercise/response_count}
add wave -noupdate -radix unsigned {afdx:/tb_datagram_mac_joint/exercise/snmp_snapshots}
add wave -noupdate -radix unsigned {afdx:/tb_datagram_mac_joint/exercise/load_complete}
add wave -noupdate -radix unsigned {afdx:/tb_datagram_mac_joint/exercise/rtc_locked}
add wave -noupdate -radix unsigned {afdx:/tb_datagram_mac_joint/exercise/image_valid}
add wave -noupdate -radix unsigned {afdx:/tb_datagram_mac_joint/exercise/package_generation}
add wave -noupdate -divider {Checks}
add wave -noupdate -radix unsigned {afdx:/tb_datagram_mac_joint/errors}
add wave -noupdate -radix unsigned {afdx:/tb_datagram_mac_joint/finished}
configure wave -timelineunits us
configure wave -namecolwidth 230
configure wave -signalnamewidth 1
update
wave zoom range 0ns 27022240ns
set afdx_fd [open [file join $afdx_replay_dir {result.log}] r]
echo [read $afdx_fd]
close $afdx_fd
set afdx_fd [open [file join $afdx_replay_dir {verify_shared.log}] r]
echo [read $afdx_fd]
close $afdx_fd
