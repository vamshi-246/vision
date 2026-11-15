# Guide from the verified core to FPGA deployment

> The Zybo Z7-10 built-in-pattern HDMI implementation is now in
> [HDMI_BRINGUP.md](HDMI_BRINGUP.md). Use that guide for the board project and
> programming commands; the broader integration work below remains a roadmap.

## 1. Keep the tested baseline intact

The algorithm top is **`edge_pipeline`**, in `rtl/top.sv`. It is not a board top.
Import these six SystemVerilog files into Vivado:

```text
rtl/linebuf.sv
rtl/gauss.sv
rtl/sobel.sv
rtl/dirnms.sv
rtl/classify_hist.sv
rtl/top.sv
```

`pkg.sv` is not required by this core. Add `ctrl_sync.sv`, `apb_regs.sv` and
`crc32.sv` when wiring their corresponding functions. `vga_timing.sv` is not
required for HDMI or algorithm verification. `scripts/core_timing_wrapper.sv`
is an internal timing experiment, not a deployable video wrapper.

Use `model/golden.py` as the reference. `golden/p7_golden.py` is a compatibility
entry point to that model. The root-level `p7 golden.py` has different borders,
direction thresholds and hysteresis behavior; keep it as legacy evidence.
The supported RTL baseline is 3x3, direction 13/32, 11-bit L1 magnitude and K=0.
Do not enable the model's 5x5, truncation, alternate direction or hysteresis
options while claiming an RTL comparison.

## 2. Observe the streaming contract

| Signal/behavior | Requirement |
| --- | --- |
| Clock/reset | One pixel clock. Synchronous active-high reset; use a synchronized reset in the eventual wrapper |
| Input data | Unsigned 8-bit grayscale. For RGB use `(77*R+150*G+29*B)>>8`, without rounding |
| Acceptance | Every rising edge with `in_valid=1` accepts one pixel; no `ready` signal |
| SOF | Assert with the first accepted pixel at (0,0), exactly once per frame |
| EOL | Assert with the last accepted pixel of every active line |
| Blanking | Set `in_valid=0`; SOF/EOL are meaningful only with valid. Do not count porch/blanking pixels in IMG_W/H |
| Dimensions | Compile-time parameters, at least 7x7. Audited targets 640x480 and 320x240; frame pixels limited to 524,287 by statistics widths |
| Thresholds | 11-bit values with `0 <= low <= high <= 2047`; keep them constant while a frame is being classified |
| Output classes | `00` absent, `01` weak, `10` strong; baseline binary edge is `out_cls==2` |
| Output coordinates | Original-image coordinates; only x=3..W-4 and y=3..H-4 are emitted |
| Output SOF/EOL | First interior pixel (3,3); last interior pixel of each line. These are cropped-stream markers |
| Borders | Insert zero in the three-pixel frame margin when reconstructing a full image |
| Output rate | Consecutive interior pixels can arrive every clock. Invalid gaps occur at cropped borders and input blanking |
| Drain | Keep clock running after input stops. The tests allow 32 clocks; no valid zero-pixel flush is required |

Measured first output latency is `6*IMG_W+17` clocks with uninterrupted input:
3,857 clocks at 640 pixels/line, 1,937 at 320. With 160 clocks of horizontal
blanking it becomes `6*(IMG_W+160)+17`: 4,817 clocks for 640. Arbitrary input
gaps add elapsed clocks, so follow valid/markers rather than a fixed time delay.
This differs by three clocks from the earlier asynchronous line-buffer design.

For 640x480 there must be **300,516 valid class outputs**, not 307,200. A display
still needs a complete 640x480 raster with 6,684 border pixels set to zero.

`hist_nnz` counts **nonzero NMS survivors**, independently of the thresholds;
it is not the number of strong edges. Histogram bins are `nms_mag>>5`, 64 bins.
The snapshot includes the final pixel. `hist_valid` stays high after the first
snapshot until reset/clear; detect frame completion from the last output
coordinate/marker, not a later rising edge of hist_valid. Registers give a
coherent snapshot until the next frame completes.

Use histogram clear between frames for complete-frame statistics. A clear
during valid traffic preserves the classification sample but intentionally
discards that cycle's histogram increment and clears the current snapshot.

## 3. Reproduce the verification before importing changes

From the repository root:

```bash
python3 -m venv build/venv
build/venv/bin/pip install -r requirements-verification.txt
make golden PYTHON=build/venv/bin/python
make sim
make stress PYTHON=build/venv/bin/python
make regression PYTHON=build/venv/bin/python
build/venv/bin/python scripts/check_scoreboard_mutations.py
```

The full regression needs Icarus and Verilator in PATH. The script compiles
Verilator in a temporary directory because its GNU Make flow rejects paths
containing spaces. All evidence remains under `build/core_regression`.
For a smaller Icarus-only run:

```bash
build/venv/bin/python scripts/core_regression.py --quick --simulator iverilog
```

Vivado is installed at `/tools/Xilinx/Vivado/2024.2/bin/vivado` on this machine:

```bash
make synth VIVADO=/tools/Xilinx/Vivado/2024.2/bin/vivado
make impl VIVADO=/tools/Xilinx/Vivado/2024.2/bin/vivado
make netlist PYTHON=build/venv/bin/python VIVADO=/tools/Xilinx/Vivado/2024.2/bin/vivado
```

Run the full regression before the netlist test; it supplies the VGA reference
vectors. `make synth` writes the bare core's functional netlist/checkpoint to
`build/vivado_core`. `make impl` routes the registered timing shell and writes
`build/vivado_registered`. The netlist test uses XSim and the actual Xilinx
RAM/logic primitives and can be much slower than RTL simulation. There is no
board-specific bitstream target yet; `make bit` explicitly fails instead of
silently claiming a build.

Override `P7_PART` if the actual board differs from the repository's assumed
`xc7z010clg400-1`. Confirm the chip marking and board revision first. The checked
timing shell excludes its external pad paths; the real design must constrain
its actual clocks and interfaces and meet both setup and hold.

## 4. Bring up a static image before a live video source

1. Create a board wrapper with the correct clock source, clock wizard and
   synchronized reset. Keep the core and its first source in one clock domain.
2. Feed a known grayscale image from a ROM or a controlled memory/FIFO source.
   Use a generated checker/step image first, then one of the tested photos.
3. Implement `ctrl_sync` checking on accepted input pixels. Latch errors and
   reset/restart the stream after a malformed frame. For whole-core abort
   recovery use reset; line-buffer SOF recovery alone is not a whole-pipeline
   flush guarantee.
4. Capture classes/coordinates in simulation or an ILA. Check the first output,
   634 outputs per line, 474 lines and total 300,516 for VGA.
5. Reconstruct the border explicitly and compare the resulting image against
   the Python model. Keep this test available when adding each new interface.

The core has no backpressure. An AXI4-Stream input adapter must drive core valid
from **accepted beats (`TVALID && TREADY`)** and preserve TLAST/SOF. An output
adapter needs sufficient FIFO/buffering and a proven rate guarantee; it cannot
simply stop this pipeline when downstream TREADY drops. Handle DMA underflow
as a frame error and recover at a clean frame boundary.

## 5. Add the display path deliberately

The installed Vivado IP catalog was queried in this audit. It contains
`v_tc` (6.1/6.2), `v_axi4s_vid_out` (4.0), `v_vid_in_axi4s` (4.0/5.0),
`axi_vdma` (6.3), clock-wizard entries and several HDMI TX/RX subsystem entries.
No `*dvi*` IP was returned. Full results are preserved in the audit evidence;
rerun `scripts/ip_inventory.tcl` for the current installation.

**Catalog presence does not establish that an HDMI subsystem supports the
actual Zynq-7000 device, board pin wiring, required PHY or available license.**
Check device compatibility and licensing in the IP customization flow, then
use the board's supported HDMI/DVI output design. Keep that selection outside
the algorithm RTL. Do not select a transceiver-based HDMI configuration merely
because it appears in the catalog.

For the display wrapper, plan all of these before connecting RGB:

- Generate a complete output raster, including blanking and border zeros.
- Align the delayed class stream with that raster; cropped `out_sof/out_eol`
  are not display sync signals. Use coordinates, FIFO occupancy and a defined
  startup phase. Avoid combinationally connecting core valid to display DE.
- For original/smoothed/edge view switching, account for each path's different
  spatial crop and latency. The core currently exports only classes; add
  deliberately aligned debug/view outputs if needed.
- Add asynchronous FIFOs or a suitable frame-buffer architecture if the source,
  algorithm and display clocks differ. Verify sustained rates and startup.
- Use board-specific constraints and clock/serialization IP. Do not reuse VGA
  pin constraints for HDMI. Timing, I/O standards and board routing need their
  own validation.

## 6. Finish controls and project deliverables

Add a strong-edge counter (`out_valid && out_cls==2`), frame counter and
frame-done pulse. Include the first pixel when clearing at output SOF; publish
the completed count atomically at the last interior pixel. Connect these to
APB status ports. The current APB block does not instantiate the counters,
core, bridge or CPU. If RV32 is required by the course, that integration remains
work even if a Zynq PS control path is convenient.

Latch pending thresholds atomically at a frame boundary. APB writes currently
update the register values immediately; directly wiring them into a running
core can produce a frame with mixed thresholds. The simplest initial rule is
to write only while acquisition is stopped and the pipeline is drained.

If APB and pixel clocks differ, synchronize commands and transfer multi-bit
thresholds/snapshots using a handshake; independent bit synchronizers are not
an atomic bus transfer. Status events are set-dominant over software clears.
A level-high histogram-valid input will reassert the corresponding APB status
bit after clearing; use a per-frame event or explicit snapshot-clear protocol.

The standalone CRC block uses zlib-compatible reflected CRC32 on bytes 00/FF.
The golden CRC covers **all W*H pixels**, including zero borders. Feeding it only
the cropped core output computes a different CRC. Reinsert border pixels before
CRC, or explicitly define a separate cropped-stream CRC in both RTL/software.
Frame-start/end must accompany accepted pixel bytes at that CRC interface.

Before claiming the whole assignment complete, add the hand-HLS schedule and
sharing/tree-height analysis, Espresso/BDD minimization and equivalence
evidence, and CTL frame/line/no-deadlock proofs. These artifacts are currently
missing. A simulation PASS is not a CTL proof. The isolated `hyst_stage` is not
a validated K-stage extension: it exports a binary edge and contracts its
window, so preserving weak/strong classes and border semantics needs additional
design if that extension is later required. Research comparison remains deferred.

Finally rerun synthesis, placement, routing, DRC, CDC and setup/hold analysis on
the **complete board design**; resolve all real clock/interface warnings, then
generate a bitstream and test hardware. The checked internal timing and
six-BRAM result are a starting point for that integration.
