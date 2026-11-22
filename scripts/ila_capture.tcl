# ILA capture on the Zybo Z7 (bitstream from `make ila`, build/hdmi_z7_ila/).  Explicit hardware step; never run by the build.
#   program:  P7_BOARD=zybo_z7 vivado -mode batch -source scripts/ila_capture.tcl -tclargs program
#   capture:  P7_BOARD=zybo_z7 vivado -mode gui   -source scripts/ila_capture.tcl -tclargs capture [ROW]
#   show:     P7_BOARD=zybo_z7 vivado -mode gui   -source scripts/ila_capture.tcl -tclargs show   (re-open the saved capture, no board)
# "capture" arms the ILA with the trigger  cv == 1 && cy == ROW && cx == 3  (first classified pixel of output row ROW,
# default 240 = middle of the frame), uploads the 4096-sample window, opens it in the waveform viewer (GUI mode) and saves
# build/hdmi_z7_ila/capture.ila + capture.csv.  "program" loads the ILA bitstream (do this before `fpga_image.py send`).
set root [file normalize [file join [file dirname [info script]] ..]]
if {![info exists ::env(P7_BOARD)] || $::env(P7_BOARD) ne "zybo_z7"} {error "Set P7_BOARD=zybo_z7 (the ILA build is for the Zybo Z7-10)"}
set dir [file join $root build hdmi_z7_ila]
set bit [file join $dir zybo_edge_hdmi.bit]
set ltx [file join $dir zybo_edge_hdmi.ltx]
foreach f [list $bit $ltx] {if {![file exists $f]} {error "Missing $f: run `make ila` first"}}
set mode [expr {[llength $argv] ? [lindex $argv 0] : "capture"}]
set row  [expr {[llength $argv] > 1 ? [lindex $argv 1] : 240}]

# "show": re-open the last saved capture in the waveform viewer (no board needed)
if {$mode eq "show"} {
 open_hw_manager
 set data [read_hw_ila_data [file join $dir capture.ila]]
 display_hw_ila_data $data
 return
}
open_hw_manager
connect_hw_server
open_hw_target
set devices [get_hw_devices -filter {PART =~ xc7z010*}]
if {[llength $devices] != 1} {error "Expected exactly one xc7z010 target; inspect JTAG chain"}
set dev [lindex $devices 0]
current_hw_device $dev
set_property PROGRAM.FILE $bit $dev
set_property PROBES.FILE $ltx $dev
set_property FULL_PROBES.FILE $ltx $dev
if {$mode eq "program"} {
 program_hw_devices $dev
 refresh_hw_device $dev
 puts "ILA bitstream programmed. Now upload a photo (python3 scripts/fpga_image.py send PHOTO), then run the capture step."
 return
}
refresh_hw_device $dev
set ila [lindex [get_hw_ilas -of $dev] 0]
if {$ila eq ""} {error "No ILA in the device: program it first (-tclargs program)"}

# probes by RTL signal name (the last path component)
proc probe {ila tail} {
 foreach p [get_hw_probes -of $ila] {if {[regexp "(^|/)${tail}\$" [get_property NAME $p]]} {return $p}}
 error "ILA probe $tail not found"
}
foreach p [get_hw_probes -of $ila] {
 set_property DISPLAY_RADIX [expr {[get_property WIDTH $p] > 1 ? "UNSIGNED" : "BINARY"}] $p
}
reset_hw_ila $ila
set_property CONTROL.TRIGGER_CONDITION AND $ila
set_property CONTROL.TRIGGER_POSITION 256 $ila
set_property CONTROL.DATA_DEPTH 4096 $ila
set_property TRIGGER_COMPARE_VALUE eq1'b1 [probe $ila cv]
set_property TRIGGER_COMPARE_VALUE [format "eq%d'u%d" [get_property WIDTH [probe $ila cy]] $row] [probe $ila cy]
set_property TRIGGER_COMPARE_VALUE [format "eq%d'u3" [get_property WIDTH [probe $ila cx]]] [probe $ila cx]
run_hw_ila $ila
wait_on_hw_ila -timeout 1 $ila
set data [upload_hw_ila_data $ila]
write_hw_ila_data -force [file join $dir capture.ila] $data
write_hw_ila_data -force -csv_file [file join $dir capture.csv] $data
puts "ILA captured (trigger: output row $row, x=3); saved $dir/capture.ila and capture.csv"
if {[catch {display_hw_ila_data $data} e]} {puts "(batch mode: no waveform window) $e"}
