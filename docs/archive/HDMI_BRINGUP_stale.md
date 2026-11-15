> **STALE - superseded 2026-11-15.** Written for the Zybo Z7 pinout before the board was identified as the original Zybo, and before the stored-image path, RV32 SoC and Espresso/CSE changes. Kept for history only. Current: docs/FINAL_REPORT.md, docs/DEMO_GUIDE.md.

# Zybo Z7-10 HDMI video demonstration

Target: **xc7z010clg400-1**, 125 MHz input clock on K17, HDMI **TX** connector.
This design uses Digilent `rgb2dvi` and AMD Clocking Wizard. It sends DVI-compatible
RGB video over HDMI, with no audio. The input is the built-in grayscale pattern
chosen for the first hardware demonstration.

## Build and verification

Run from the repository root with Vivado 2024.2 installed:

```bash
/tools/Xilinx/Vivado/2024.2/bin/vivado -mode batch -source scripts/build_hdmi.tcl -log build/hdmi_build.log -journal build/hdmi_build.jou
build/venv/bin/python scripts/video_regression.py
build/venv/bin/python scripts/hdmi_timing_sim.py --corner functional
build/venv/bin/python scripts/hdmi_timing_sim.py --corner max
build/venv/bin/python scripts/hdmi_timing_sim.py --corner min
```

The project is created at `build/hdmi/project/hdmi.xpr`. You can open it in the
GUI after the Tcl build. To inspect the already implemented design, open
`build/hdmi/route.dcp` through File > Checkpoint > Open. The board top is `zybo_hdmi_top`; use
`fpga/zybo_hdmi.xdc`, not the Pmod VGA constraints. Build outputs include reports,
a routed checkpoint, functional/timing netlists, SDF, and a bitstream if the
setup/hold gate passes. Full build results are summarized in HDMI_RESULTS.md.

## Hardware controls

Connect a monitor to HDMI TX, power the board, load the generated bitstream via
Vivado Hardware Manager/JTAG, and press/release BTN0 if necessary.

| Control | Function |
| --- | --- |
| SW1:SW0 = 00 | Original built-in grayscale pattern |
| 01 | Gaussian-smoothed view; one-pixel zero margin |
| 10 | Strong edges; three-pixel zero margin |
| 11 | Threshold classes: weak amber, strong white |
| SW3:SW2 = 00 | Low/high thresholds 80/200 |
| 01 | 20/40 |
| 10 | 160/400 |
| 11 | 300/700 |
| BTN0 | Reset the video clock generator and pipeline |
| LED0 | Clock generator locked |
| LED1 | Active output video (will look continuously lit) |
| LED2 | Frame heartbeat; too fast to see individual flashes |
| LED3 | Sticky pipeline/raster alignment fault; should remain off |

Switches pass through synchronizers and are applied at the source frame boundary.
Unconnected buttons 1–3 are reserved. The source is a rectangle plus checker
pattern generated directly from raster coordinates; no image ROM or frame
buffer is used. The IP packs RGB as R,B,G; the top explicitly reorders channels.

## Alignment and extension contract

The input raster is 640 active pixels in an 800-clock line and 480 active lines
in a 525-line frame. Original data and timing are delayed by 2,414 pixel clocks
(from acceptance edge to publication edge); Gaussian output receives the
additional delay needed to reach that same pixel. The edge core provides its
interior stream at this same phase. The reset-free delay storage maps to SRLs; each input is sampled on the falling
edge before the normal rising-edge shift to provide half-cycle input margin.
All delay inputs must come from rising-edge logic in this same clock domain. A resettable warmup counter masks all uninitialized samples.

The demo uses the core's new `smooth_valid` and `smooth_gray` debug/view ports.
Their valid region is one pixel inside the input, with no external backpressure.
Existing class output behavior is unchanged. The aligned video module also
produces a per-frame strong-edge count and frame pulse for later control/ILA use.

Do not feed a different source into this fixed-phase wrapper without preserving
its raster schedule. A camera, HDMI RX or DMA source needs its own acceptance,
blanking, clock-domain and buffering design. The display never waits for ready.

The demonstration selects a fixed video mode. It does not read EDID, use HPD to
select modes, or drive DDC/CEC. If a monitor does not lock, first check the TX
connector, LED0, BTN0 and monitor mode support. Final physical cable/monitor
operation must be checked on hardware.

Digilent IP is vendored under `third_party/rgb2dvi`, preserving upstream license
notices; provenance is in `third_party/README.md`. Its use follows the board
manual's rgb2dvi recommendation:
https://digilent.com/reference/_media/reference/programmable-logic/zybo-z7/zybo-z7_rm.pdf

Clocking Wizard requests 25.175 MHz pixel and 125.875 MHz serialization clocks.
Vivado 2024.2 selects M=35.25, D=5 and output dividers 35/7: approximately
25.178571 MHz and 125.892857 MHz, giving 59.949 Hz refresh with an exact 5:1
ratio. This is about 142 ppm above the nominal pixel rate. See `clocks.rpt`
for the actual generated clocks; the clock-ratio gate must pass after changing
any clock configuration.

Lock is qualified for 128 pixel clocks, followed by a 1,024-clock startup delay. The
transmitter reset is released on a falling pixel edge, giving its asynchronous
reset bridge half a cycle before the next rising edge. The core uses synchronous
reset. BTN0 repeats this startup sequence.

For explicit command-line programming, first connect and power the board, start
Vivado's hardware server if needed, then run:

```bash
/tools/Xilinx/Vivado/2024.2/bin/vivado -mode batch -source scripts/program_hdmi.tcl
```

This writes only the live FPGA configuration. It does not program boot flash or
install a persistent boot image. The build/test commands never program hardware.

![Expected built-in pattern views](assets/hdmi_views.png)
