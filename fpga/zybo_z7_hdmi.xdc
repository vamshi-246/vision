## P7 constraints for the Digilent Zybo Z7-10 (xc7z010clg400-1, separate HDMI TX and RX connectors).
## Derived from Digilent Zybo-Z7-Master.xdc. BUILD-ONLY: this variant has not been run on a Z7 board (none was available).
## Do NOT use this file on the original Zybo (clock is L16 there); use zybo_hdmi.xdc.

set_property -dict { PACKAGE_PIN K17 IOSTANDARD LVCMOS33 } [get_ports { clk }]

set_property -dict { PACKAGE_PIN G15 IOSTANDARD LVCMOS33 } [get_ports { sw[0] }]
set_property -dict { PACKAGE_PIN P15 IOSTANDARD LVCMOS33 } [get_ports { sw[1] }]
set_property -dict { PACKAGE_PIN W13 IOSTANDARD LVCMOS33 } [get_ports { sw[2] }]
set_property -dict { PACKAGE_PIN T16 IOSTANDARD LVCMOS33 } [get_ports { sw[3] }]

set_property -dict { PACKAGE_PIN K18 IOSTANDARD LVCMOS33 } [get_ports { btn[0] }]
set_property -dict { PACKAGE_PIN P16 IOSTANDARD LVCMOS33 } [get_ports { btn[1] }]
set_property -dict { PACKAGE_PIN K19 IOSTANDARD LVCMOS33 } [get_ports { btn[2] }]
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
