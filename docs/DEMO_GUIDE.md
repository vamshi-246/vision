# Live demo guide: photo -> FPGA -> edge detection (RV32-controlled) -> monitor

Board used and tested: **original Digilent Zybo** (single HDMI I/O port J8). All commands run from the project root.
Bitstream: `build/hdmi/zybo_edge_hdmi.bit` (record of the exact tested file: `build/archive_final_zybo/`).
Known-good fallback if anything is rebuilt by accident: `build/archive_final_zybo/zybo_edge_hdmi.bit`.

## 0. Before the audience arrives
1. Power switch SW4 on. Micro-USB cable in **PROG/UART** (J11) to the laptop. HDMI cable from **J8 (HDMI I/O)** to the monitor; select that input.
2. `lsusb | grep 0403` should list an FT2232.
3. Program the FPGA (the design is lost at every power-off; **name the board explicitly**):
   ```
   P7_BOARD=zybo P7_HW_DEBUG=1 /tools/Xilinx/Vivado/2024.2/bin/vivado -mode batch -source scripts/program_hdmi.tcl
   ```
   After about 20 s: LD0, LD1, LD2 lit, LD3 off, checker pattern on the monitor. (`P7_HW_DEBUG=1` is needed because the post-route SDF timing
   simulation is still open; see the final report. Functional netlist simulation, static timing and the hardware tests pass.)
4. Dry-run an upload (section 1) once.
5. Firmware is already built (`fw/build/fw.bin`); rebuild only if you edit `fw/src/main.c`: `make -C fw`.

## 1. Sending a photo (the live step)
```
build/venv/bin/python scripts/fpga_image.py send ~/photos/photo.jpg
```
Any threshold 0..2047 can be sent (`threshold LO HI`). About 11 s (about 8 s is Vivado starting). The tool: converts the photo (EXIF rotation, 4:3 crop, 320x240, the model's grayscale formula),
uploads it into the FPGA frame buffer over JTAG, **reads every byte back**, loads and starts the **RV32 firmware**, waits for the CPU to publish,
and compares the CPU's numbers with the Python model. The screen switches to your photo by itself.

Expected last lines:
```
Image read-back: PASS - all 76800 bytes identical; firmware read-back: PASS
CPU (PicoRV32): published N frames ... mailbox record stable; thresholds in effect 80/200 ...
model @ 80/200: strong edges E -> CPU value MATCH; 64-bin histogram read by the CPU -> MATCH
RESULT: OK
```
Options: `--fit pad` keeps the whole photo with gray bars; HEIC needs `pip install pillow-heif` (or export as JPEG);
`convert photo.jpg` previews the expected result without hardware (PNGs in `build/upload/<name>/`).

## 2. What to show (live, on the board)
| Control | Effect |
|---|---|
| BTN1 | pattern <-> your photo |
| SW1:0 = 00 / 01 / 10 / 11 | original / Gaussian-smoothed / strong edges / classes (weak amber, strong white) |
| SW3:2 = 00 / 01 / 10 / 11 | thresholds low/high 80/200, 20/40, 160/400, 300/700. **The RV32 firmware reads the switches and writes the thresholds** into the APB registers. |
| BTN0 | reset clocks/video (picture blanks and returns; the stored photo survives and the CPU re-applies its settings within one frame) |
| LD0 / LD1 / LD2 / LD3 | PLL locked / active video / frame heartbeat / alignment fault (should stay off) |

Laptop-side extras while the demo runs:
```
build/venv/bin/python scripts/fpga_image.py status          # live CPU readings (edge count, thresholds, 64-bin histogram) vs the model
build/venv/bin/python scripts/fpga_image.py threshold 30 90 # the laptop overrides the CPU's thresholds: more edges appear on the monitor
build/venv/bin/python scripts/fpga_image.py threshold auto  # back to the switches
```
Good talking sequence: original -> smoothed -> strong edges -> classes; sweep SW3:2; send a second photo; run `threshold 30 90`;
run `status` and point at "MATCH" (hardware and model agree on edge count and all 64 histogram bins).

## 3. Say honestly
- Not a camera stream: each photo is re-sent on request (about 11 s); processing then runs continuously at 60 frames/s.
- The photo is stored at 320x240 grayscale and shown 2x enlarged (640x480): 640x480x8 bit does not fit the chip's block RAM.
  The JTAG-AXI + BRAM frame store replaces a DDR/DMA path (not built; see report).
- The PicoRV32 CPU reads the pipeline's statistics through the APB register bank and sets the thresholds; if the CPU is not running, the
  switch presets drive the thresholds in hardware (same values).
- The photo is lost when the FPGA is reprogrammed or powered off.

## 4. Troubleshooting
| Symptom | Fix |
|---|---|
| "No JTAG-AXI core found" | FPGA not programmed (power-cycled): redo 0.3 |
| Vivado cannot connect | replug USB; `pkill -f hw_server`; close other Vivado sessions |
| Picture stays the pattern after upload | press BTN1; read the tool output for FAIL lines |
| Monitor blank | BTN0; check LD0 and the cable in J8 |
| `no firmware magic` / `cpu_trap 1` | run `send` again (reloads the firmware) |
| LD3 lit | alignment fault: BTN0; if it persists, tell the team |
| Using a **Zybo Z7** | build with `P7_BOARD=zybo_z7` and program with `P7_BOARD=zybo_z7`. This variant is build-and-simulation verified only: no Z7 board was available. |

## 5. Live webcam (Zybo Z7-10 only, `live-video` build)
Laptop webcam -> laptop HDMI out (USB-C to HDMI cable) -> board **HDMI RX (J10)** -> grayscale, 320x240 -> frame buffer -> the same edge
pipeline and 640x480 HDMI TX (J11) to the monitor. Hardware-verified 2026-11-20 on the Zybo Z7-10.

Build and program (the bitstream is `build/hdmi_z7_live/zybo_edge_hdmi.bit`):
```
make live              # P7_BOARD=zybo_z7 P7_LIVE=1 build (about 6 min)
make live-sim          # rx_timing + rx_downscale testbench: expects "TB_RX_LIVE PASS"
/tools/Xilinx/Vivado/2024.2/bin/vivado -mode batch -source scripts/program_live.tcl
```
On the laptop:
1. Plug the cable into J10 firmly (a loose plug was the cause of one failed session). The laptop sees a new display (`DP-1`) whose EDID offers
   only 800x600@60. If it shows another size or a scaled mode: `xrandr --output DP-1 --mode 800x600 --scale 1x1`
   (after reprogramming the board, unplug/replug the J10 cable once so the laptop re-reads the EDID).
2. Start the viewer, which draws the webcam full-screen on that display: `python3 scripts/live_camera.py` (option `--output` if the display is
   not `DP-1`). **Leave its window open**: it is the video source. It lives on the FPGA display, not on the laptop screen.

Board controls (same as the still demo, plus):
| Control | Effect |
|---|---|
| LD3 | live HDMI-in source active (in this build LD3 is not the alignment-fault LED) |
| BTN2 | live source off/on (off: checker pattern or the last JTAG-uploaded photo, BTN1 as before) |
| SW1:0, SW3:2, BTN0, BTN1 | unchanged |
`fpga_image.py send/status/threshold` still work; the live writes pause only while a JTAG access is in progress.

Why 800x600 in and 640x480 out: Digilent's `dvi2rgb` receiver supports 800x600 and up only (640x480 failed channel alignment on the board),
and the monitor did not accept an 800x600 signal from the board (a TX-only 800x600 colour-bar test stayed black while 640x480 works). The
frame buffer decouples the two: RX runs on the laptop's 40 MHz clock, the pipeline and TX on the board's 25.175 MHz clock; a 64-word async
FIFO crosses between them. Decimation is 2.5:1 nearest-neighbour (rows/columns n with n mod 5 in {0,2}). There is a single frame buffer, so a
slowly moving tear line is possible (laptop 60.32 Hz vs output 59.94 Hz).
