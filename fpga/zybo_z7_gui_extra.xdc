## Extra settings the scripted build applies in Tcl; add this file too when building from the Vivado GUI.
set_clock_uncertainty 0.100 [all_clocks]
set_property BITSTREAM.CONFIG.UNUSEDPIN Pullup [current_design]
