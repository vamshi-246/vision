## P7 constraints for the ORIGINAL Digilent Zybo (single HDMI I/O port J8), xc7z010clg400-1.
## Pins from Digilent Zybo-Master.xdc (clock L16, BTN0 R18, BTN2 V16, HDMI_OUT_EN F17). Earlier Zybo Z7 pins were wrong for this board.

set_property -dict { PACKAGE_PIN L16 IOSTANDARD LVCMOS33 } [get_ports { clk }]

set_property -dict { PACKAGE_PIN G15 IOSTANDARD LVCMOS33 } [get_ports { sw[0] }]
set_property -dict { PACKAGE_PIN P15 IOSTANDARD LVCMOS33 } [get_ports { sw[1] }]
set_property -dict { PACKAGE_PIN W13 IOSTANDARD LVCMOS33 } [get_ports { sw[2] }]
set_property -dict { PACKAGE_PIN T16 IOSTANDARD LVCMOS33 } [get_ports { sw[3] }]

set_property -dict { PACKAGE_PIN R18 IOSTANDARD LVCMOS33 } [get_ports { btn[0] }]
set_property -dict { PACKAGE_PIN P16 IOSTANDARD LVCMOS33 } [get_ports { btn[1] }]
set_property -dict { PACKAGE_PIN V16 IOSTANDARD LVCMOS33 } [get_ports { btn[2] }]
set_property -dict { PACKAGE_PIN Y16 IOSTANDARD LVCMOS33 } [get_ports { btn[3] }]

set_property -dict { PACKAGE_PIN M14 IOSTANDARD LVCMOS33 } [get_ports { led[0] }]
set_property -dict { PACKAGE_PIN M15 IOSTANDARD LVCMOS33 } [get_ports { led[1] }]
set_property -dict { PACKAGE_PIN G14 IOSTANDARD LVCMOS33 } [get_ports { led[2] }]
set_property -dict { PACKAGE_PIN D18 IOSTANDARD LVCMOS33 } [get_ports { led[3] }]

set_property -dict {PACKAGE_PIN H16 IOSTANDARD TMDS_33} [get_ports {hdmi_tx_clk_p}]
set_property -dict {PACKAGE_PIN H17 IOSTANDARD TMDS_33} [get_ports {hdmi_tx_clk_n}]
set_property -dict {PACKAGE_PIN D19 IOSTANDARD TMDS_33} [get_ports {hdmi_tx_p[0]}]
set_property -dict {PACKAGE_PIN D20 IOSTANDARD TMDS_33} [get_ports {hdmi_tx_n[0]}]
set_property -dict {PACKAGE_PIN C20 IOSTANDARD TMDS_33} [get_ports {hdmi_tx_p[1]}]
set_property -dict {PACKAGE_PIN B20 IOSTANDARD TMDS_33} [get_ports {hdmi_tx_n[1]}]
set_property -dict {PACKAGE_PIN B19 IOSTANDARD TMDS_33} [get_ports {hdmi_tx_p[2]}]
set_property -dict {PACKAGE_PIN A20 IOSTANDARD TMDS_33} [get_ports {hdmi_tx_n[2]}]
# User inputs are asynchronous. Only their synchronizer entry is excluded.
set_false_path -from [get_ports {sw[*]}] -to [get_pins -hier -filter {NAME =~ */sw_meta_reg*/D}]
set_false_path -from [get_ports {btn[*]}]

# LEDs have no synchronous receiver timing requirement.
set_false_path -to [get_ports {led[*]}]

# Clocking Wizard supplies the sole 8 ns primary clock and its input jitter.

# The Ethernet PHY supplies CLK125. Actively release its reset.
set_property -dict {PACKAGE_PIN E17 IOSTANDARD LVCMOS33} [get_ports eth_rst_b]
set_property -dict {PACKAGE_PIN F17 IOSTANDARD LVCMOS33} [get_ports hdmi_out_en]
