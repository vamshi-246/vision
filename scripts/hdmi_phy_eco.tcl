set root [file normalize [file join [file dirname [info script]] ..]]
set out [file join $root build hdmi]
set_param general.maxThreads 1
open_checkpoint [file join $out route.dcp]
create_port -direction OUT eth_rst_b
create_cell -reference OBUF phy_reset_obuf
create_cell -reference VCC phy_reset_vcc
create_net phy_reset_high
connect_net -net phy_reset_high -objects [list [get_pins phy_reset_vcc/P] [get_pins phy_reset_obuf/I]]
create_net eth_rst_b
connect_net -net eth_rst_b -objects [list [get_pins phy_reset_obuf/O] [get_ports eth_rst_b]]
set_property -dict {PACKAGE_PIN E17 IOSTANDARD LVCMOS33} [get_ports eth_rst_b]
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
