# Program the live-video build (Zybo Z7-10 only): HDMI RX J10 800x600 -> 320x240 frame store -> edge pipeline -> HDMI TX 640x480.
set root [file normalize [file join [file dirname [info script]] ..]]
set bitfile [file join $root build hdmi_z7_live zybo_edge_hdmi.bit]
open_hw_manager
connect_hw_server
open_hw_target
set devices [get_hw_devices -filter {PART =~ xc7z010*}]
if {[llength $devices] != 1} {error "Expected exactly one xc7z010 target"}
set device [lindex $devices 0]
current_hw_device $device
set_property PROGRAM.FILE $bitfile $device
program_hw_devices $device
refresh_hw_device $device
puts "P7_CONFIG_STATUS=[get_property REGISTER.CONFIG_STATUS $device]"
close_hw_manager
