set root [file normalize [file join [file dirname [info script]] ..]]
# Board selection: P7_BOARD=zybo (original Digilent Zybo, default, hardware-tested) or zybo_z7 (Zybo Z7-10, build only).
set board zybo
if {[info exists ::env(P7_BOARD)]} {set board $::env(P7_BOARD)}
if {$board ne "zybo" && $board ne "zybo_z7"} {error "P7_BOARD must be zybo or zybo_z7"}
set out [file join $root build [expr {$board eq "zybo" ? "hdmi" : "hdmi_z7"}]]
set xdc_name [expr {$board eq "zybo" ? "zybo_hdmi.xdc" : "zybo_z7_hdmi.xdc"}]
set defines [expr {$board eq "zybo" ? [list BOARD_ZYBO=1] : [list]}]
file mkdir $out
set_param general.maxThreads 1
create_project -force hdmi [file join $out project] -part xc7z010clg400-1
set_property ip_repo_paths [list [file join $root third_party]] [current_project]
update_ip_catalog
create_ip -name clk_wiz -vendor xilinx.com -library ip -module_name video_clocks
set_property -dict [list CONFIG.PRIM_IN_FREQ {125.000} CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {25.175} CONFIG.CLKOUT2_USED {true} CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {125.875} CONFIG.USE_LOCKED {true} CONFIG.USE_RESET {true} CONFIG.RESET_TYPE {ACTIVE_HIGH}] [get_ips video_clocks]
# Clocking Wizard resolves the requested pair to a common MMCM and exact 5:1 ratio.
# Vivado 2024.2 effective solution: M=35.25, D=5, O=35/7; pixel=25.178571 MHz.
create_ip -name rgb2dvi -vendor digilentinc.com -library ip -module_name hdmi_tx
set_property -dict [list CONFIG.kGenerateSerialClk {false} CONFIG.kRstActiveHigh {true}] [get_ips hdmi_tx]
# Image-upload path: JTAG-to-AXI master -> AXI BRAM controller (17-bit byte address, 32K words).
create_ip -name jtag_axi -vendor xilinx.com -library ip -module_name jtag_axi_master
create_ip -name axi_bram_ctrl -vendor xilinx.com -library ip -module_name frame_axi_ctrl
set_property -dict [list CONFIG.DATA_WIDTH {32} CONFIG.SUPPORTS_NARROW_BURST {0} CONFIG.SINGLE_PORT_BRAM {1} CONFIG.MEM_DEPTH {32768} CONFIG.READ_LATENCY {1}] [get_ips frame_axi_ctrl]
set_property XPM_LIBRARIES {XPM_MEMORY} [current_project]
generate_target all [get_ips]
# Use global synthesis so constraints and serializers remain visible.
set_property generate_synth_checkpoint false [get_files -all *.xci]
foreach src {linebuf gauss dir_decide sobel dirnms classify_hist top vga_timing apb_regs} {read_verilog -sv [list [file join $root rtl ${src}.sv]]}
foreach src {video_delay frame_store edge_video video_soc zybo_hdmi_top} {read_verilog -sv [list [file join $root rtl video ${src}.sv]]}
foreach src {soc_ram cpu_subsys} {read_verilog -sv [list [file join $root rtl soc ${src}.sv]]}
read_verilog [list [file join $root third_party picorv32 picorv32.v]]
read_xdc [list [file join $root fpga $xdc_name]]
set_property top zybo_hdmi_top [current_fileset]
update_compile_order -fileset sources_1
synth_design -top zybo_hdmi_top -part xc7z010clg400-1 -verilog_define $defines
set_clock_uncertainty 0.100 [all_clocks]
write_checkpoint -force [file join $out synth.dcp]
report_utilization -file [file join $out utilization_synth.rpt]
report_clocks -file [file join $out clocks.rpt]
set pixel_period [get_property PERIOD [get_clocks clk_out1_video_clocks*]]
set serial_period [get_property PERIOD [get_clocks clk_out2_video_clocks*]]
if {abs($pixel_period/$serial_period-5.0)>0.01} {error "Pixel/serial clocks must have a 5:1 period ratio"}
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
