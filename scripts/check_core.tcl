# Board-independent out-of-context synthesis and optional implementation.
# Run from the repository root; no board pin constraints or video IP required.
set root [file normalize [file join [file dirname [info script]] ..]]
set out [file join $root build vivado_core]
if {[info exists ::env(P7_REPORT_DIR)]} { set out [file normalize $::env(P7_REPORT_DIR)] }
file mkdir $out
set part xc7z010clg400-1
if {[info exists ::env(P7_PART)]} { set part $::env(P7_PART) }
set_param general.maxThreads 4
foreach src {linebuf gauss dir_decide sobel dirnms classify_hist top} {
    read_verilog -sv [list [file join $root rtl ${src}.sv]]
}
set top edge_pipeline
set registered_shell [info exists ::env(P7_REGISTERED_SHELL)]
if {$registered_shell} {
    read_verilog -sv [list [file join $root scripts core_timing_wrapper.sv]]
    set top core_timing_wrapper
}
synth_design -top $top -part $part -mode out_of_context
create_clock -name pixel_clk -period 39.722 [get_ports clk]
set_property HD.CLK_SRC BUFGCTRL_X0Y0 [get_ports clk]
set_clock_uncertainty 0.200 [get_clocks pixel_clk]
# Explicit OOC environment assumption: 10 ns upstream/downstream budget.
# Replace these with the actual wrapper's constraints at board integration.
if {$registered_shell} {
    # Only the shell's external pad-to-register paths are excluded. Every core
    # path and shell-register-to-core/core-to-shell path remains timed.
    set_false_path -from [get_ports -filter {DIRECTION == IN && NAME != clk}]
    set_false_path -to [get_ports -filter {DIRECTION == OUT}]
} else {
    set_input_delay -max 10.000 -clock pixel_clk [get_ports -filter {DIRECTION == IN && NAME != clk}]
    set_input_delay -min 0.500 -clock pixel_clk [get_ports -filter {DIRECTION == IN && NAME != clk}]
    set_output_delay -max 10.000 -clock pixel_clk [get_ports -filter {DIRECTION == OUT}]
    set_output_delay -min 0.500 -clock pixel_clk [get_ports -filter {DIRECTION == OUT}]
}
report_utilization -hierarchical -file [file join $out utilization_synth.rpt]
report_timing_summary -file [file join $out timing_synth.rpt]
report_drc -file [file join $out drc_synth.rpt]
write_checkpoint -force [file join $out core_synth.dcp]
write_verilog -force -mode funcsim [file join $out core_funcsim.v]
puts "P7_BRAM_COUNT=[llength [get_cells -hier -filter {REF_NAME =~ RAMB*}]]"
if {![info exists ::env(P7_SYNTH_ONLY)]} {
    opt_design
    place_design
    phys_opt_design
    route_design
    report_utilization -hierarchical -file [file join $out utilization_route.rpt]
    report_timing_summary -report_unconstrained -file [file join $out timing_route.rpt]
    report_timing -from [all_registers] -to [all_registers] -max_paths 10 -file [file join $out timing_registers.rpt]
    report_drc -file [file join $out drc_route.rpt]
    report_methodology -file [file join $out methodology.rpt]
    write_checkpoint -force [file join $out core_route.dcp]
    if {$registered_shell} {
        foreach delay_type {max min} {
            set worst [get_timing_paths -quiet -delay_type $delay_type -max_paths 1]
            if {[llength $worst] && [get_property SLACK $worst] < 0} {
                error "Registered core shell fails $delay_type timing; see $out/timing_route.rpt"
            }
        }
        puts "P7_REGISTERED_CORE_TIMING=PASS"
    } else {
        puts "P7_BARE_OOC_BOUNDARY_TIMING=NOT_BOARD_SIGNOFF; inspect setup and hold reports"
    }
}
