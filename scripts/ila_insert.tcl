# Sourced by build_hdmi.tcl after synthesis when P7_ILA=1: inserts one ILA on the pixel clock.
# Probes = the nets marked (* mark_debug *) in rtl/video/edge_video.sv under `ifdef P7_ILA, plus the Sobel stage outputs of the
# core (found by name, so rtl/top.sv stays untouched). One ILA probe per signal/bus, named after the RTL signal.

# group marked nets into buses: base name -> list of {index net}
proc p7_group {nets} {
 set g [dict create]
 foreach n $nets {
  if {[regexp {^(.*)\[(\d+)\]$} $n -> base idx]} {dict lappend g $base [list $idx $n]} else {dict lappend g $n [list 0 $n]}
 }
 return $g
}
set marked [get_nets -hier -filter {MARK_DEBUG == 1}]
set extra {}
foreach s {sobel_valid sobel_mag sobel_dir} {
 set f [get_nets -hier -quiet -filter "NAME =~ */core/${s} || NAME =~ */core/${s}\[*\]"]
 if {[llength $f] == 0} {puts "WARNING: ILA: core net $s not found after synthesis (skipped)"} else {lappend extra {*}$f}
}
set groups [p7_group [concat $marked $extra]]
if {[dict size $groups] < 8} {error "ILA: only [dict size $groups] debug signals found; expected the marked nets of edge_video"}

# ILA clock = the clock of the register that drives the running edge count (pixel clock domain)
set re [lindex [dict get $groups [lindex [lsearch -inline -all [dict keys $groups] *running_edges] 0]] 0 1]
set ff [get_cells -of [get_pins -leaf -of [get_nets $re] -filter {DIRECTION == OUT}]]
set clk [get_nets -of [get_pins -of $ff -filter {REF_PIN_NAME == C}]]
puts "ILA clock net: $clk"

create_debug_core u_ila_pixel ila
set_property C_DATA_DEPTH 4096 [get_debug_cores u_ila_pixel]
set_property C_EN_STRG_QUAL true [get_debug_cores u_ila_pixel]
set_property C_ADV_TRIGGER false [get_debug_cores u_ila_pixel]
set_property C_INPUT_PIPE_STAGES 0 [get_debug_cores u_ila_pixel]
set_property C_TRIGIN_EN false [get_debug_cores u_ila_pixel]
set_property C_TRIGOUT_EN false [get_debug_cores u_ila_pixel]
set_property ALL_PROBE_SAME_MU true [get_debug_cores u_ila_pixel]
set_property ALL_PROBE_SAME_MU_CNT 2 [get_debug_cores u_ila_pixel]
set_property port_width 1 [get_debug_ports u_ila_pixel/clk]
connect_debug_port u_ila_pixel/clk $clk

# fixed probe order (as it appears in the waveform): raster in -> Sobel -> classified out -> thresholds -> count
set order {sof sde eol gray sobel_valid sobel_mag sobel_dir cv cs ce cx cy cls lo hi running_edges}
set keys [dict keys $groups]
set sorted {}
foreach o $order {foreach k $keys {if {[regexp "(^|/)${o}\$" $k] && [lsearch -exact $sorted $k] < 0} {lappend sorted $k}}}
foreach k $keys {if {[lsearch -exact $sorted $k] < 0} {lappend sorted $k}}
set first 1
set report {}
foreach k $sorted {
 set bits [lsort -integer -index 0 [dict get $groups $k]]
 set nets {}
 foreach b $bits {lappend nets [lindex $b 1]}
 if {$first} {set p u_ila_pixel/probe0; set first 0} else {set p [create_debug_port u_ila_pixel probe]}
 set_property port_width [llength $nets] [get_debug_ports $p]
 connect_debug_port $p [get_nets $nets]
 lappend report "[file tail $p] [llength $nets] $k"
}
puts "ILA probes:\n  [join $report "\n  "]"
set fh [open [file join $out ila_probes.txt] w]; puts $fh [join $report "\n"]; close $fh
