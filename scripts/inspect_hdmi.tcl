set root [file normalize [file join [file dirname [info script]] ..]]
set out [file join $root build hdmi]
open_checkpoint [file join $out route.dcp]
report_clocks -file [file join $out clocks.rpt]
set f [open [file join $out checks.txt] w]
set pc [get_clocks clk_out1_video_clocks*]
set sc [get_clocks clk_out2_video_clocks*]
puts $f "pixel_period_ns=[get_property PERIOD $pc]"
puts $f "serial_period_ns=[get_property PERIOD $sc]"
set ratio [expr {[get_property PERIOD $pc]/[get_property PERIOD $sc]}]
puts $f "clock_period_ratio=$ratio"
if {abs($ratio-5)>0.01} {error "incorrect serializer ratio"}
foreach dt {max min} {
 set slack [get_property SLACK [get_timing_paths -delay_type $dt -max_paths 1]]
 puts $f "$dt slack_ns=$slack"
 if {$slack<0} {error "timing violation"}
}
puts $f "latches=[llength [get_cells -quiet -hier -filter {REF_NAME =~ LDCE || REF_NAME =~ LDPE}]]"
puts $f "serializer_masters=[llength [get_cells -quiet -hier -filter {REF_NAME == OSERDESE2 && SERDES_MODE == MASTER}]]"
close $f
puts "PASS HDMI clock ratio and routed setup/hold"
