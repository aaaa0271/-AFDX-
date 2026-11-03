set afdx_download_dir [file dirname [file normalize [info script]]]
dataset open [file join $afdx_download_dir download.wlf] afdx_download
dataset current afdx_download
view wave
catch {delete wave *}
add wave -noupdate -divider {Committed package download}
add wave -noupdate -radix unsigned afdx_download:/tb_615a_roundtrip/dut/download/state
add wave -noupdate -radix unsigned afdx_download:/tb_615a_roundtrip/dut/download/current
add wave -noupdate -radix unsigned afdx_download:/tb_615a_roundtrip/dut/download/selected_count
add wave -noupdate -radix hexadecimal afdx_download:/tb_615a_roundtrip/dut/download/status_code
add wave -noupdate -radix unsigned afdx_download:/tb_615a_roundtrip/dut/download/read_file
add wave -noupdate -radix unsigned afdx_download:/tb_615a_roundtrip/dut/download/read_address
add wave -noupdate -radix binary afdx_download:/tb_615a_roundtrip/dut/download/active
add wave -noupdate -radix binary afdx_download:/tb_615a_roundtrip/dut/download/complete
add wave -noupdate -radix binary afdx_download:/tb_615a_roundtrip/dut/download/failed
add wave -noupdate -radix unsigned afdx_download:/tb_615a_roundtrip/dl_bytes
add wave -noupdate -radix unsigned afdx_download:/tb_615a_roundtrip/dl_files
add wave -noupdate -radix unsigned afdx_download:/tb_615a_roundtrip/generation
add wave -noupdate -radix unsigned afdx_download:/tb_615a_roundtrip/errors
update
wave zoom full
