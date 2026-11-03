set afdx_replay_dir [file dirname [file normalize [info script]]]
# Open this script in an otherwise empty ModelSim GUI.
set afdx_capture_dir $afdx_replay_dir
set afdx_wlf [file join $afdx_capture_dir overview.wlf]
if {![file exists $afdx_wlf]} {error {overview.wlf is missing; capture must complete first.}}
dataset open $afdx_wlf afdx
dataset current afdx
do [file join $afdx_capture_dir focus_overview.do]
