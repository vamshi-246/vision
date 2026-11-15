# VGA 640x480 @ 60 Hz timing -- exact numbers used in `rtl/vga_timing.sv`

Sources (looked up on 2026-11-15; all agree on every number in the table below):
* Digilent Reference, "VGA Display Controller" tutorial -- 25.175 MHz pixel clock, H sync 96 / back porch 48 / front porch 16 /
  active 640 pixels, V sync 2 lines; states the clock tolerance as +-0.5 %
  (https://digilent.com/reference/learn/programmable-logic/tutorials/vga-display-congroller/start).
* Columbia CSEE 4840 video notes, "Detailed VGA Timing" -- HTOTAL 800 = 96 + 48 + 640 + 16, VTOTAL 525, V sync 2, V back porch 33,
  V active 480, V front porch 10 (https://www.cs.columbia.edu/~sedwards/classes/2007/4840/video.pdf).
* Basys2 VGA reference table -- 640x480@60 Hz: 25.175 MHz, H 640/16/96(low)/48, V 480/10/2(low)/33 (negative sync polarity).

| | visible | front porch | sync pulse | back porch | total | sync polarity |
|---|---|---|---|---|---|---|
| horizontal (pixels) | 640 | 16 | 96 | 48 | **800** | negative (active low) |
| vertical (lines)    | 480 | 10 |  2 | 33 | **525** | negative (active low) |

* Nominal pixel clock: **25.175 MHz** (800 x 525 x 59.94 Hz). Line rate 31.469 kHz, frame rate 59.94 Hz.
* Counter convention in `vga_timing.sv`: `hcount` runs 0..799 with the visible pixels at 0..639, then front porch 640..655,
  sync 656..751 (96 clocks), back porch 752..799. `vcount` runs 0..524: visible 0..479, front porch 480..489, sync 490..491,
  back porch 492..524. HSYNC/VSYNC are active low; DE (data enable) = hcount < 640 && vcount < 480.
  The pipeline's raster origin (0,0) is the first visible pixel, so its `sof` is simply `hcount==0 && vcount==0`.
* **Clock actually generated on the board:** the Clocking Wizard in `hdmi/` derives it from the 125 MHz system clock.
  The exact achieved frequency is whatever the wizard reports for the chosen MMCM settings; it is recorded in
  `doc/FINAL_MAIN_PIPELINE_REPORT.md` from the Vivado run (**not** verified in this sandbox: Vivado is not available here).
  rgb2dvi needs the pixel clock and a **5x** serial clock (it drives the TMDS data with 10:1 serialisation at DDR = 5x).
* Pixel clock tolerance: Digilent's tutorial gives +-0.5 % around 25.175 MHz (25.049 .. 25.301 MHz). A generated 25.2 MHz would
  be +0.10 %, inside that window. HDMI sinks lock to the TMDS clock themselves; whether a particular monitor accepts the
  achieved frequency can only be confirmed on the board.
