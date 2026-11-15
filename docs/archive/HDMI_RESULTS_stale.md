> **STALE - superseded 2026-11-15.** Written for the Zybo Z7 pinout before the board was identified as the original Zybo, and before the stored-image path, RV32 SoC and Espresso/CSE changes. Kept for history only. Current: docs/FINAL_REPORT.md, docs/DEMO_GUIDE.md.

# Zybo Z7-10 HDMI verification results

Target: `xc7z010clg400-1`; Vivado/XSim 2024.2. Source, clocks and constraints are
reproducible with `scripts/build_hdmi.tcl`. The hardware instructions are in
[HDMI_BRINGUP.md](HDMI_BRINGUP.md).

## Final implementation

- 3,216 LUTs, including SRL delay storage; 954 flip-flops, no latches.
- Six RAMB18 primitives (three BRAM tiles), zero DSPs.
- Pixel clock approximately 25.178571 MHz; serializer clock approximately
  125.892857 MHz, exact 5:1 ratio. Raster refresh approximately 59.949 Hz.
- Routed setup slack **+14.151 ns**, hold slack **+0.049 ns**; no failing
  setup/hold endpoints. Clock uncertainty is 0.100 ns.
- CDC: four safe switch crossings, no unsafe crossings.
- Bitstream generation succeeded with no DRC errors or critical warnings.

These are the resource numbers for the built-in-pattern demonstration. The
unconnected histogram readback logic is optimized away; they do not represent
an implementation with the entire APB/CPU subsystem retained.

The source clock comes from the board's Ethernet PHY. Its reset must remain
high; the build keeps unused pins pulled up, including E17/PHYRSTB. See the
[board manual, clocking section](https://digilent.com/reference/_media/reference/programmable-logic/zybo-z7/zybo-z7_rm.pdf).

## Simulation coverage

The video regression checks **42 complete frame presentations** across 64x48
and 640x480, comparing **6,515,712 RGB pixels** against the Python reference.
It checks all four display views and all four threshold presets, borders,
HSYNC/VSYNC, valid raster positions, alignment faults and strong-edge counts.
The previous core's small Icarus regression and unit suite also pass after
adding the two Gaussian view ports; the arithmetic/classification behavior is
unchanged.

Expected strong-edge counts on the 640x480 built-in pattern:

| Threshold preset | Low / high | Strong edges | Weak pixels |
| --- | --- | ---: | ---: |
| 00 | 80 / 200 | 12,888 | 484 |
| 01 | 20 / 40 | 13,372 | 0 |
| 10 | 160 / 400 | 12,528 | 844 |
| 11 | 300 / 700 | 34 | 12,850 |

The routed-netlist tests decode actual serialized TMDS symbols at the output
pins. Each test requires 2,000 active symbols and at least 200 blanking symbols,
checks all three color lanes against the pattern's grayscale palette, and
requires clock-lock and alignment status to be known and correct. This is a
startup/short-stream pin test, complemented by the complete-frame RGB tests;
it is not a complete HDMI protocol or electrical compliance test.

Timing simulations use slow-corner SDF/MAX for setup and fast-corner SDF/MIN
for hold, with timing checks enabled and XSim transport/interconnect pulse
options. Those settings follow
[AMD UG900 for Vivado 2024.2](https://docs.amd.com/r/2024.2-English/ug900-vivado-logic-simulation/Running-Timing-Simulation-Using-Third-Party-Tools).
Xilinx `glbl` holds configuration GSR active for the first 100 ns. The scorer
reports initialization timing warnings in that interval separately; any timing
violation after that interval fails the test. No global disabling of timing
checks or notifier checks is used.

The SDF tests identified issues absent in zero-delay simulation. The final
wrapper releases transmitter reset on a falling pixel edge, qualifies lock for 128 pixel clocks and then waits another 1,024 pixel
clocks before starting, and samples SRL inputs on falling edges.
This preserves the rising-edge pixel sequence while giving those inputs a
half-cycle timing margin.

## Acknowledged report limits

The DRC/methodology reports retain noncritical warnings: optional BRAM output
registers are not absorbed, automatically derived clocks are referenced by
uncertainty constraints, and vendor pin-filter queries are inefficient. DRC
also reports standalone Zynq PS7 absence and LUT pair packing warnings; bitgen
accepts the design. Full reports are preserved in the HDMI evidence directory.

There are no unconstrained internal endpoints. The four differential TMDS
output paths have no external receiver output-delay budget; asynchronous
switch inputs and LED status outputs have documented exceptions. Static timing
passes refer to the constrained FPGA paths. The source-synchronous serialized
interface is also exercised with SDF at its pins. Monitor/cable signal integrity,
EDID/HPD negotiation, audio and external video acquisition are outside this
fixed-mode DVI-compatible demonstration.

Final simulation summaries and hardware-programming/display observations are
preserved with the evidence; the bitstream remains in `build/hdmi`.
