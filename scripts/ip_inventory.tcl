set root [file normalize [file join [file dirname [info script]] ..]]
file mkdir [file join $root build]
create_project -in_memory -part xc7z010clg400-1
set f [open [file join $root build video_ip_inventory.txt] w]
foreach pattern {*hdmi* *dvi* *v_tc* *v_axi4s_vid_out* *v_vid_in_axi4s* *axi_vdma* *clk_wiz*} {
    puts $f "$pattern: [get_ipdefs -all -quiet $pattern]"
}
close $f
