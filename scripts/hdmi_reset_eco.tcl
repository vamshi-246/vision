# Targeted reset ECO equivalent to the reset pipeline in zybo_hdmi_top.sv.
# Reuses the already verified 128-stage lock qualifier and unchanged core.
set root [file normalize [file join [file dirname [info script]] ..]]
set out [file join $root build hdmi]
set_param general.maxThreads 1
open_checkpoint [file join $out route.dcp]
set old [get_cells rst_reg]
if {[get_property REF_NAME $old] != "FDSE"} {error "Reset ECO expects the prior counter-based reset checkpoint"}
set cnet [get_nets -of_objects [get_pins rst_reg/C]]
set enet [get_nets -of_objects [get_pins rst_reg/CE]]
set dnet [get_nets -of_objects [get_pins rst_reg/S]]
set qnet [get_nets -of_objects [get_pins rst_reg/Q]]
set znet [get_nets -of_objects [get_pins heartbeat_reg/R]]
disconnect_net -net $qnet -objects [get_pins rst_reg/Q]
create_cell -reference FDRE rst_clean_reg
set_property INIT 1'b1 [get_cells rst_clean_reg]
set_property IS_C_INVERTED 1'b1 [get_cells rst_clean_reg]
foreach {pin net} [list C $cnet CE $enet D $dnet Q $qnet R $znet] {
 connect_net -net $net -objects [get_pins rst_clean_reg/$pin]
}
remove_cell $old
opt_design
place_design
phys_opt_design
route_design
report_timing_summary -report_unconstrained -file [file join $out timing.rpt]
report_utilization -file [file join $out utilization.rpt]
report_drc -file [file join $out drc.rpt]
report_cdc -file [file join $out cdc.rpt]
report_methodology -file [file join $out methodology.rpt]
write_checkpoint -force [file join $out route.dcp]
write_verilog -force -mode funcsim [file join $out routed_funcsim.v]
write_verilog -force -mode timesim -sdf_anno false [file join $out routed_timesim.v]
write_sdf -force -process_corner slow [file join $out routed_slow.sdf]
write_sdf -force -process_corner fast [file join $out routed_fast.sdf]
foreach dt {max min} {if {[get_property SLACK [get_timing_paths -delay_type $dt -max_paths 1]]<0} {error "$dt timing failed"}}
# Keep unused PL pins pulled up, including the Ethernet PHY reset (E17).
# The PHY supplies the 125 MHz PL reference clock and must not be held reset.
set_property BITSTREAM.CONFIG.UNUSEDPIN Pullup [current_design]
write_bitstream -force [file join $out zybo_edge_hdmi.bit]
