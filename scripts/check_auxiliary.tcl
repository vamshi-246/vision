set root [file normalize [file join [file dirname [info script]] ..]]
set out [file join $root build vivado_auxiliary]
file mkdir $out
set_param general.maxThreads 2
foreach top {apb_regs ctrl_sync crc32 hyst_stage} {
    create_project -in_memory -part xc7z010clg400-1
    if {$top == "hyst_stage"} { read_verilog -sv [list [file join $root rtl linebuf.sv]] }
    read_verilog -sv [list [file join $root rtl ${top}.sv]]
    synth_design -top $top -part xc7z010clg400-1 -mode out_of_context
    report_utilization -file [file join $out ${top}_utilization.rpt]
    set latches [llength [get_cells -hier -filter {REF_NAME =~ LDCE || REF_NAME =~ LDPE}]]
    if {$latches} { error "$top inferred $latches latches" }
    puts "P7_AUX_SYNTH=$top PASS latches=0"
    close_project
}
