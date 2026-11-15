# Inspect the registered timing shell after make impl, without rebuilding it.
set root [file normalize [file join [file dirname [info script]] ..]]
set out [file join $root build vivado_registered]
open_checkpoint [file join $out core_route.dcp]
set f [open [file join $out timing_gate.txt] w]
set failures 0
foreach delay_type {max min} {
    set worst [get_timing_paths -delay_type $delay_type -max_paths 1]
    set slack [get_property SLACK $worst]
    puts $f "$delay_type slack_ns=$slack"
    if {$slack < 0} { incr failures }
}
set latches [llength [get_cells -hier -filter {REF_NAME =~ LDCE || REF_NAME =~ LDPE}]]
puts $f "latches=$latches"
puts $f "bram_primitives=[llength [get_cells -hier -filter {REF_NAME =~ RAMB*}]]"
puts $f "dsp_primitives=[llength [get_cells -hier -filter {REF_NAME =~ DSP*}]]"
puts $f "clock_period_ns=[get_property PERIOD [get_clocks pixel_clk]]"
close $f
if {$failures || $latches} { error "Registered core timing/latch gate failed" }
puts "PASS registered core setup/hold timing; no latches"
