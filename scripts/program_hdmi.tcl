# Explicit programming entry point; never invoked by the build or test targets.
set root [file normalize [file join [file dirname [info script]] ..]]
# The board must be named: the original Zybo and the Zybo Z7-10 share the xc7z010 part, so the JTAG chain cannot tell them apart,
# and a bitstream for the wrong board drives the wrong pins.
if {![info exists ::env(P7_BOARD)] || ($::env(P7_BOARD) ne "zybo" && $::env(P7_BOARD) ne "zybo_z7")} {
    error "Set P7_BOARD=zybo (original Zybo, J8 'HDMI I/O') or P7_BOARD=zybo_z7 (Zybo Z7-10) before programming"
}
set board $::env(P7_BOARD)
set bdir [expr {$board eq "zybo" ? "hdmi" : "hdmi_z7"}]
set sdsuffix [expr {$board eq "zybo" ? "" : "_hdmi_z7"}]
if {$board eq "zybo_z7"} {puts "NOTE: the Zybo Z7 build has not been verified on hardware"}
set bitfile [file join $root build $bdir zybo_edge_hdmi.bit]
if {![file exists $bitfile]} {error "Build and verify the HDMI design first"}
set required {functional max min}
if {[info exists ::env(P7_HW_DEBUG)]} {
    puts "Hardware debug run: timing SDF remains unresolved; requiring functional simulation only"
    set required {functional}
}
foreach corner $required {
    set summary [file join $root build hdmi_sim_${corner}${sdsuffix} summary.json]
    if {![file exists $summary] || [file mtime $summary] < [file mtime $bitfile]} {
        error "Run the $corner transmitter simulation for this bitstream first"
    }
    set f [open $summary r]
    set result [read $f]
    close $f
    if {![regexp {"pass": true} $result] || ![regexp {"operational_timing_warnings": 0} $result]} {
        error "$corner transmitter verification failed"
    }
}
open_hw_manager
connect_hw_server
open_hw_target
set devices [get_hw_devices -filter {PART =~ xc7z010*}]
if {[llength $devices] != 1} {error "Expected exactly one xc7z010 target; inspect JTAG chain"}
set device [lindex $devices 0]
current_hw_device $device
set_property PROGRAM.FILE $bitfile $device
program_hw_devices $device
refresh_hw_device $device
puts "P7_CONFIG_STATUS=[get_property REGISTER.CONFIG_STATUS $device]"
puts "Programmed $device with $bitfile"
close_hw_manager
