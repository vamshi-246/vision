# Add an explicit reset-release margin at the vendor serializer reset inputs.
set root [file normalize [file join [file dirname [info script]] ..]]
set base [file join $root build hdmi]
set out [file join $root build hdmi_reset_margin]
file mkdir $out
set_param general.maxThreads 1
open_checkpoint [file join $base route.dcp]
set sources [get_cells -hier -filter {NAME =~ *LockLostReset* && REF_NAME == FDPE}]
set sinks [get_pins -of_objects [get_cells -hier -filter {REF_NAME == OSERDESE2}] -filter {REF_PIN_NAME == RST}]
if {![llength $sources] || [llength $sinks]!=8} {error "Serializer reset endpoints were not found"}
set_min_delay 1.500 -from $sources -to $sinks
phys_opt_design -hold_fix
route_design
report_timing_summary -report_unconstrained -file [file join $out timing.rpt]
report_utilization -file [file join $out utilization.rpt]
report_drc -file [file join $out drc.rpt]
report_cdc -file [file join $out cdc.rpt]
report_methodology -file [file join $out methodology.rpt]
report_timing -from $sources -to $sinks -delay_type min -max_paths 8 -file [file join $out serdes_reset_margin.rpt]
write_checkpoint -force [file join $out route.dcp]
write_verilog -force -mode funcsim [file join $out routed_funcsim.v]
write_verilog -force -mode timesim -sdf_anno false [file join $out routed_timesim.v]
write_sdf -force -process_corner slow [file join $out routed_slow.sdf]
write_sdf -force -process_corner fast [file join $out routed_fast.sdf]
foreach dt {max min} {if {[get_property SLACK [get_timing_paths -delay_type $dt -max_paths 1]]<0} {error "$dt timing failed"}}
set_property BITSTREAM.CONFIG.UNUSEDPIN Pullup [current_design]
write_bitstream -force [file join $out zybo_edge_hdmi.bit]
