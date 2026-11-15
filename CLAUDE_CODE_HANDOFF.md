# Handoff: Zybo Z7 edge detector and HDMI bring-up

Prepared 15 November 2026 from this chat and the workspace. This is a handoff,
not a claim that the HDMI output works. The latest physical board state is
unknown: the last hardware interaction in this chat was on 13 November.

## Request and scope

The original task was to inspect `problem statement.png`, the RTL, and software
model; test the core extensively; and write notes for later FPGA work. The user
initially excluded the research-paper implementation and external interfaces.
They then asked for HDMI interfacing, Vivado IP, timing-aware simulation,
synthesis, implementation, and hardware testing. They explicitly confirmed
**Zybo Z7-10, `xc7z010clg400-1`**, and selected a **built-in image/test
pattern** as the first video source. A monitor was connected to HDMI TX and the
board was connected over USB/JTAG during the last session.

The assignment calls for a 640x480@60 streaming, one-pixel-per-clock,
Canny-style pipeline: grayscale, 3x3 or 5x5 Gaussian, Sobel L1 magnitude and
quantized direction, nonmaximum suppression, double threshold, BRAM line
buffers, APB thresholds/statistics, and at least five pixel-exact image tests.
It also calls for later CPU/DMA/video integration, Boolean minimization, formal
CTL proofs, and a research-paper comparison. The research paper remains out of
scope for this work; do not silently claim those deferred items are complete.

## Most important current facts

1. **The core RTL was extensively tested and corrected; the HDMI board demo is
   unfinished.** The RTL/model audit and evidence are in
   `docs/CORE_RTL_REVIEW.md` and `doc/evidence/core_audit/`. These are snapshots
   of the earlier core revision: HDMI integration subsequently added
   `smooth_valid`/`smooth_gray` ports to `rtl/top.sv`, so source hashes in the
   earlier manifest should not be presented as hashes of the present tree.
2. **No monitor image has been confirmed.** The user first reported no signal,
   then disclosed that they accidentally turned off the board after JTAG
   programming. After powering it back on, the previous bitstream was loaded
   again. Their subsequent observation was: only **LD10 (DONE)** and **LD11
   (PGOOD)** were illuminated; none of the four user LEDs was lit; the monitor
   showed nothing. This points to an unlocked pixel-clock generator (LED0 should
   reflect its `locked` signal), but it does not establish the root cause.
3. **A newer PHY-reset experiment was built after that report but was never
   programmed or tested on hardware in this chat.** The last programming log is
   `build/hdmi_program_console.txt`, 13 Nov 20:50:27, and the current
   `build/hdmi/zybo_edge_hdmi.bit` was generated at 20:53:52. Therefore the
   current bitstream is **not** the one the user last observed. The board may
   have since been powered off; do not assume its current contents.
4. **Post-route SDF timing simulation is unresolved and has failed.** Do not
   report the functional simulation or static-timing pass as a pass for the
   delay-annotated TMDS simulation. Logs in `build/hdmi_sim_max/simulate.txt`
   and `build/hdmi_sim_min/simulate.txt` belong to an earlier reset-ECO version
   before the PHY output was added; they contain unknown decoded RGB symbols
   and, at fast/min corner, serializer reset hold violations. There is no passing
   max/min `summary.json` verified for the current PHY-reset bitstream.
5. **Some generated HDMI documentation is stale.** In particular,
   `docs/HDMI_BRINGUP.md` and `docs/HDMI_RESULTS.md` mention an extra 1,024-clock
   startup delay that is no longer present, and resource/slack numbers and
   implicit timing-test claims refer to earlier builds. They also predate the
   explicit `eth_rst_b` output. Reconcile these documents with the final source,
   reports, simulation and hardware observation before delivering.
6. The worktree contains extensive modified **and untracked** user/project
   files. Do not reset/clean it or overwrite unrelated files. `build/` is
   ignored and contains critical intermediate checkpoints, generated IP,
   reports and the bitstreams; preserve it until the handoff work is complete.

## Core review and changes

The active baseline oracle is `model/golden.py`, with these fixed-point choices:

- 8-bit grayscale; 3x3 Gaussian `(weighted_sum + 8) >> 4`.
- Sobel `abs(Gx)+abs(Gy)` in 11 bits; direction boundaries use 13/32.
- NMS keeps a positive center when it is `>=` the earlier raster neighbor and
  `>` the later neighbor.
- Class 0 = none, 1 = weak, 2 = strong. The baseline is double threshold with
  K=0: the binary view uses strong edges only. Zero magnitude stays class 0 even
  when both thresholds are zero.
- Gaussian, Sobel and NMS each shrink the valid region, so the class stream is
  the original image interior with a three-pixel zero border on reconstruction.

The root-level `p7 golden.py` is a retained **legacy** implementation with
incompatible border, direction and hysteresis semantics. `golden/p7_golden.py`
now forwards to `model/golden.py`. The Python model exposes additional 5x5,
input-truncation and hysteresis options that are **not** supported by the
reviewed baseline top.

Changes made during audit include explicit Vivado-compatible input net types;
synchronous read-first, alternating BRAM row banks; correct first-pixel SOF
addressing; nonzero prerequisite for thresholding; histogram clear that does
not drop a class sample; set-dominant APB event/clear handling; missing-SOF
checking; explicit Gaussian/Sobel widths; consistent grayscale conversion and
RGB vector export; and a correctly failing image-report CLI. See
`doc/change_notes/002-core-audit-corrections.md`.

Evidence gathered before the HDMI work:

- 20 Python tests and 11 existing unit benches passed.
- 642 Verilator frame presentations at six sizes, including 69 VGA-size runs;
  25,862,274 output classes and matching intermediate Gaussian, Sobel and NMS
  samples compared with zero mismatches. Traffic included continuous input,
  random gaps and 160-clock horizontal/45-line vertical blanking.
- 504 additional small-frame Icarus presentations passed. Direction comparator
  domain: 4,169,764 magnitude/sign combinations. Additional arithmetic, NMS,
  histogram saturation/clear, reset/restart, APB and CRC stress passed.
- Six deliberate mutants were rejected by the scoreboard.
- Two 640x480 frames passed Vivado **synthesized functional-netlist**
  simulation: 601,032 classes plus coordinates, markers and histogram bins.
- The provided JPEG matched all 307,200 reconstructed pixels; default
  thresholds 80/200 yielded 4,804 edges and CRC `39abe3c7`. Custom thresholds
  30/90 also matched (8,007 strong edges; CRC `50afd115`).
- Core-only registered-shell OOC implementation at 39.722 ns had setup/hold
  +20.567/+0.014 ns. Bare-OOC boundary paths had hold violations with assumed
  I/O delays; neither experiment is full-board I/O sign-off.

These are finite tests, not formal proof of arbitrary input or of the entire
FPGA system. `hyst_stage.sv` is an isolated extension, not a proven cascadeable
K-stage implementation. The core has no backpressure. RV32, an integrated
strong-edge counter readable over APB, DMA/frame store, and CTL proofs remain
separate work.

## HDMI design currently in the source tree

- `rtl/video/zybo_hdmi_top.sv`: board top, 125 MHz K17 input, Clocking Wizard,
  128-stage asynchronous-assert/synchronous-release lock qualifier, falling-edge
  synchronous core reset and falling-edge/asynchronous-assert transmitter
  reset. Current source **also drives `eth_rst_b=1`** on E17 so the Ethernet PHY
  is not held in reset. This matters because the PHY provides the K17 125 MHz
  reference. The latest direct-PHY ECO output has not been board-tested.
- `rtl/video/edge_video.sv`: 640x480 active, 800x525 raster; a built-in gray
  checker/rectangle pattern; source switches synchronized and sampled at
  source SOF. Four views (original, smooth, strong edges, class colors) and four
  low/high threshold presets. It exports per-frame edge count, frame pulse and
  a sticky alignment error internally, though these are not an integrated
  CPU/APB implementation.
- `rtl/video/video_delay.sv`: reset-free SRL-friendly delays with a falling-edge
  sample before each SRL input. The fixed stream/raster relationship is
  essential: output display timing/original data is delayed 2,414 pixel clocks
  from acceptance to publication; the Gaussian stream gets its own matching
  delay. The warmup counter masks uninitialized SRLs. This is not a generic
  AXI4-Stream video adapter, and there is no backpressure or full-frame store.
- `rtl/vga_timing.sv` is reused as an internal raster timing generator; this is
  HDMI/DVI output, not the old Pmod VGA board top.
- `fpga/zybo_hdmi.xdc` assigns the reference clock, switches/buttons/LEDs, HDMI
  TX differential pins, and the **new E17 PHY-reset output**. The clock wizard
  supplies the primary 8 ns clock; duplicate primary-clock constraints earlier
  produced critical warnings and false CDC findings.
- `third_party/rgb2dvi/` is Digilent's BSD-licensed transmitter, vendored from
  `vivado-library` commit `0362ce72d39eebc400fdabacff706ee7fa8ad564`.
  `scripts/build_hdmi.tcl` generates this IP and AMD Clocking Wizard. The IP
  requires R,B,G packing, so the top explicitly reorders its RGB input.
- Clock Wizard requested 25.175 / 125.875 MHz and Vivado generated roughly
  **25.178571 / 125.892857 MHz**, exact 5:1 from one MMCM, ~59.949 Hz raster.
  This fixed-mode DVI-compatible signal carries no audio and does not read EDID,
  use HPD for mode negotiation, or implement HDMI input.

Controls intended for the demo: SW1:0 `00` original, `01` Gaussian, `10` strong
edges, `11` classes (weak amber / strong white); SW3:2 choose 80/200, 20/40,
160/400, 300/700. BTN0 resets clocking/video. LED0 is MMCM lock, LED1 active
video, LED2 frame heartbeat, LED3 sticky alignment fault. `docs/assets/hdmi_views.png`
illustrates software-expected views; it is not a hardware screenshot.

## HDMI tests and implementation status

`scripts/video_regression.py` ran 14 test configurations, three frames each:
64x48 and 640x480, four views and all four threshold presets. It compared
6,515,712 displayed RGB pixels to the Python reference, plus coordinates,
blanking, HSYNC/VSYNC, borders, alignment and edge counts. This passed for
`edge_video.sv`/`video_delay.sv` before the latest board-top-only PHY reset
addition. See `build/video_results.txt` and `build/video_regression/summary.json`.
The small Icarus core regression and unit benches were also rerun after the
smooth output ports were added, in `build/core_after_video.txt` and
`build/unit_after_video.txt`.

The hardware-independent full-board-top **routed functional netlist** test
passed for an earlier bitstream. `tb/video/tb_hdmi_timing.sv` decodes TMDS output
symbols; the passing run checked 2,000 active and at least 200 control symbols
and clock/alignment LED status. Log: `build/hdmi_sim_functional/simulate.txt`,
summary `build/hdmi_sim_functional/summary.json` timestamp 20:43 on 13 Nov.
That summary predates the 20:53 PHY-reset bitstream and must not be treated as
validation of the new bitstream.

Vivado 2024.2 is at `/tools/Xilinx/Vivado/2024.2/bin/vivado`. The latest E17
PHY ECO regenerated the main checkpoint, reports, timing/functional netlists,
slow/fast SDF and bitstream under `build/hdmi/`; the ECO log is
`build/hdmi_phy_console.txt` and it reports successful bitgen and no DRC errors.
Current `build/hdmi/timing.rpt` reports **+10.517 ns setup, +0.049 ns hold**,
zero failing endpoints, 0.100 ns clock uncertainty, and no unconstrained
internal endpoints. Four TMDS output ports lack an external receiver I/O timing
budget; document/analyze that limitation rather than claim HDMI electrical
compliance. The generated `build/hdmi/project/hdmi.xpr` is useful for GUI
inspection but source files have been modified since its original synthesis;
open `build/hdmi/route.dcp` for the latest ECO checkpoint or run a clean full
`build_hdmi.tcl` from the current source and verify its reports.

Other earlier candidate results under `build/hdmi_reset_margin/` are a separate
**experimental serializer-reset-min-delay ECO** and do not necessarily
include the later E17 PHY reset addition. Its bitstream SHA256 is
`d66118aa281c4f2e710a7ecfd5eafcd8bd2f4d4c811e44973471c7d0a52d0da5`.
Do not confuse it with the current main bitstream, SHA256
`c1ff1a9bf412297991752aafb8f9538a0d60a1f3cdf160e9c127a1bbf5ff7f2a`.
Neither was confirmed on the monitor. The ECO scripts are one-off modifications
of a specific checkpoint, not generic idempotent build scripts:

- `scripts/hdmi_reset_eco.tcl` replaced the earlier counter-derived root reset
  with a falling-edge reset register. The current source implements the simpler
  reset directly; future full builds should start from source rather than
  blindly replay the ECO.
- `scripts/hdmi_phy_eco.tcl` added a constant-high E17 output to that routed
  checkpoint. The current RTL/XDC include the same intended output.
- `scripts/hdmi_reset_margin.tcl` built an experimental alternative with a
  1.5 ns min-delay constraint on the vendor reset synchronizer to OSERDESE2 RST
  pins, in a separate output directory. Review this constraint carefully before
  use: earlier attempts using **Q pins** as `-from` caused path-segmentation
  critical warnings. The later script uses cells as startpoints, but it has not
  been checked by the full timing simulation/hardware flow.

The physical reset concern is grounded in Digilent's board manual: PHY
`PHYRSTB` low disables CLK125 to K17. The previous bitstream relied on the
unused-pin pullup, and the user reported no user LEDs; explicitly driving E17
high is an attempted fix, **not yet a proven diagnosis**. Check BTN0 polarity,
actual reset pin/PHY clock, active HDMI TX vs RX connector, monitor input/mode,
and clock generation; never infer a working display from JTAG DONE alone.

## SDF timing problem — preserve and investigate

`scripts/hdmi_timing_sim.py` exports/uses slow SDF/MAX for setup and fast
SDF/MIN for hold, with XSim transport and pulse options and timing checks on.
It scores only a `PASS routed TMDS timing` plus zero operational timing
warnings, with separate accounting for Xilinx `glbl` GSR initialization in the
first 100 ns. It can optionally substitute ideal 5:1 MMCM output clocks via
`--ideal-clocks` for diagnosis; this bypasses MMCM output modeling and **must
not** be represented as equivalent to native MMCM timing simulation.

On the pre-PHY-reset routed netlist, the last native tests did not pass:

- Max/slow: at about 107.45 us the TMDS decoder saw unknown RGB bits
  (`xx 18 xx`) instead of the expected grayscale palette.
- Min/fast: OSERDESE2 reset deassertion violated CLKDIV hold checks, and there
  were FDRE timing warnings in the core line buffer; decoded RGB was unknown.
- Earlier startup-counter variants also deadlocked with `rst`/`tx_rst` unknown
  in annotated simulation. A debug run showed MMCM lock high and clocks
  oscillating while reset/startup state was X. The design was simplified to a
  128-stage qualified lock and a direct falling-edge reset register, but the
  transmitter SDF failures above remained. Do not assume they are only simulator
  artifacts: the observed timing warnings and unknown data need diagnosis.

Useful logs: `build/hdmi_sim_max/{elaborate.txt,simulate.txt}`,
`build/hdmi_sim_min/{elaborate.txt,simulate.txt}`,
`build/hdmi/serdes_reset_before.rpt`, and `build/serdes_reset_console.txt`.
The old report showed a vendor `LockLostReset/.../oSyncStages_reg[1]/C` to
`DataSerializer/SerializerSlave/RST` min path with +0.234 ns STA slack, while
XSim's OSERDESE2 CLKDIV/RST check warned at reset release. That discrepancy
has not been resolved. Check SDF annotation, primitive reset-domain
requirements, common-clock/pessimism details, timing exceptions, the model and
actual routing. Retain both successful and failing results. Do not suppress
notifiers, widen the startup-warning window to hide runtime violations, or
claim the pin test passed if symbols or clocks are X.

## Suggested next actions

1. Ask the user whether the board is presently powered, USB/JTAG attached, and
   a monitor is connected to **HDMI TX**. Two days have elapsed since the last
   exchange. JTAG programming is volatile; power cycling removes the design.
   A previous read-only JTAG query saw `arm_dap_0` and `xc7z010_1` via a
   Digilent cable. The user had already authorized board programming/testing.
2. Before changing the board again, inspect current reports and make a named
   copy of the 20:53 PHY-reset bitstream/checkpoint and hash. Re-run at least
   functional simulation against **that exact PHY-reset netlist** and verify the
   E17 output is held high. The old functional summary predates this bitstream.
   `scripts/program_hdmi.tcl` normally checks that passing functional, max and
   min summaries are newer than the bitfile. `P7_HW_DEBUG=1` relaxes this to
   a fresh functional summary for an explicitly disclosed hardware-debug run;
   it does not turn failed SDF tests into passes.
3. With the user ready, program the current verified-for-debug bitstream and
   ask for LED0–LED3 and monitor observations with all switches OFF. The
   20:50 JTAG load reported `End of startup status: HIGH`, but loaded the older
   pre-E17 bitstream. If LED0 remains off, directly diagnose K17 input clock,
   E17 PHY reset, BTN0 and board power; if LED0 is on but no display, inspect
   HDMI clock/data activity, IP reset, connector, and sink mode/HPD/EDID.
   Distinguish actual observations from hypotheses.
4. Continue SDF debugging and a complete source rebuild until both native
   timing corners and the actual monitor test pass, or report precise remaining
   failures honestly. Do not assume the separate reset-margin experiment and
   the newer PHY-reset experiment were combined.
5. Re-run full-frame view regression, core checks, static timing, DRC and CDC
   against the final sources/netlist, and preserve an evidence manifest with
   **hashes of the actual programmed bitstream and tested sources**. Then fix
   stale `docs/HDMI_RESULTS.md`, `docs/HDMI_BRINGUP.md`, and status notes.

Reproduction from the repository root (Python dependencies can be installed
with `requirements-verification.txt`):

```bash
build/venv/bin/python -m pytest model/tests -q
make sim
build/venv/bin/python scripts/core_regression.py --quick --simulator iverilog
build/venv/bin/python scripts/video_regression.py
/tools/Xilinx/Vivado/2024.2/bin/vivado -mode batch -source scripts/build_hdmi.tcl -log build/hdmi_build.log -journal build/hdmi_build.jou
build/venv/bin/python scripts/hdmi_timing_sim.py --corner functional
build/venv/bin/python scripts/hdmi_timing_sim.py --corner max
build/venv/bin/python scripts/hdmi_timing_sim.py --corner min
```

Note `scripts/build_hdmi.tcl` rebuilds/overwrites the main `build/hdmi` outputs;
archive the existing latest ECO artifacts before rerunning. Verilator builds
are staged under `/tmp` because the project path contains spaces. Vivado has
also required `[list ...]` for paths with spaces. `make bit` is an older
core-only placeholder; the HDMI script produces the board bitstream.
