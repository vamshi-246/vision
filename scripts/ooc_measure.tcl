# One out-of-context Vivado flow used for EVERY design in the resource comparison, so numbers are comparable.
#   env: P7_TOP, P7_FILES (space separated, relative to P7_ROOT), P7_OUT, P7_PERIOD (ns), P7_IMPL (1 = place+route)
set root $::env(P7_ROOT)
set top $::env(P7_TOP)
set out $::env(P7_OUT)
set period $::env(P7_PERIOD)
file mkdir $out
set_param general.maxThreads 2
foreach f $::env(P7_FILES) { read_verilog -sv [list [file join $root $f]] }
read_xdc -mode out_of_context [list [file join $out clk.xdc]]
set gen {}
if {[info exists ::env(P7_GENERICS)] && $::env(P7_GENERICS) ne ""} {set gen $::env(P7_GENERICS)}
synth_design -top $top -part xc7z010clg400-1 -mode out_of_context -flatten_hierarchy rebuilt {*}$gen
report_utilization -file [file join $out synth_utilization.rpt]
if {$::env(P7_IMPL)} {
  opt_design
  place_design
  route_design
  report_utilization -file [file join $out impl_utilization.rpt]
  report_timing_summary -delay_type min_max -max_paths 5 -file [file join $out impl_timing.rpt]
  set wns [get_property SLACK [get_timing_paths -max_paths 1 -setup]]
  set whs [get_property SLACK [get_timing_paths -max_paths 1 -hold]]
  puts "RESULT top=$top period=$period WNS=$wns WHS=$whs"
}
