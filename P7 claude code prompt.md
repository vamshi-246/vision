# MASTER PROMPT — P7: Real-Time Edge-Detection Video Pipeline (VL401)

You are implementing a complete FPGA course project end-to-end, in **Verilog (Verilog-2001; SystemVerilog only inside formal/testbench files if a tool needs it)**. Work autonomously through the milestones below, commit after each milestone, and keep `STATUS.md` current (done / in progress / blocked / open questions). **Never fabricate results**: every number in a table must come from a real tool report or simulation log that you saved under `docs/logs/`. If a tool is missing, say so, produce the scripts anyway, and mark the result "NOT RUN".

---

## 0. Project definition (from the course spec)

**Aim:** detect edges in video at full pixel rate with a streaming Canny-style pipeline, shown on a display.

**Spec**
- 640×480 @ 60 Hz, **one pixel per clock**. Frames come from memory via DMA (camera optional → out of scope).
- Pipeline: grayscale → Gaussian (3×3 or 5×5) → Sobel magnitude `|Gx|+|Gy|` and quantised direction → non-maximum suppression → double threshold (+ hysteresis).
- BRAM line buffers.

**Develop**
1. Golden model (Python/NumPy) → **already written: `p7_golden.py`** (bit-exact; frame model + stream model; passes its self-tests). It is the single source of truth.
2. Sobel window + magnitude from **hand HLS**: CSE between Gx/Gy, tree-height reduction, pipelined schedule with initiation interval 1.
3. Line-buffer / frame-sync controller and VGA timing generator.
4. Direction quantiser + NMS select as the **ESPRESSO/BDD logic-optimisation block**.
5. APB threshold registers; edge-count/histogram readable by RV32.

**Research:** find a paper on memory-efficient line-buffer architectures, approximate arithmetic for image filters, or adaptive-threshold Canny on FPGA; implement it; compare BRAM/LUT use and output quality (PSNR or F-score vs golden).

**Project deliverables**
- Pixel-exact match with the golden model on ≥5 test images.
- Resource table and achieved pixel clock; latency in lines.
- Quality-vs-resource comparison, baseline vs paper design.
- CTL proofs on frame/line synchronisation; no-deadlock property.
- Demo: live display switching between original / smoothed / edges; thresholds set on switches.

---

## 1. Target platform (confirmed by the user)

- Vivado part **`xc7z010clg400-1`** (Zybo-family Zynq-7010). 125 MHz board clock. ~17.6k LUT, 35.2k FF, 60 BRAM36 (2.1 Mb), 80 DSP48. Design everything to fit with margin (≤60% of any resource).
- The RV32 SoC lives entirely in the PL. The Zynq PS is **not used** (no PS7 block, unless a gate in §2 forces it).
- **Single clock domain** by default: MMCM from 125 MHz → ≈25.175 MHz pixel clock, used for CPU, bus, pipeline, VGA. (No CDC = simpler verification and formal proofs. Report Fmax separately, see M7.)

### Hardware facts you must handle (do not assume, ask — see §2)
- **Board revision:** the original *Zybo* has a VGA port (5-6-5 resistor DAC) and the *Zybo Z7-10* has **no VGA, HDMI only**. Both use `xc7z010clg400-1`. Video output module must match the real board.
- **UART:** on both boards the USB-UART bridge goes to the **PS**, not the PL. A PL UART needs an external 3.3 V USB-serial adapter on a Pmod header (e.g., Digilent Pmod USBUART).
- Only 4 switches, 4 buttons, 4 LEDs; **no 7-segment display** (not needed for P7).

---

## 2. FIRST ACTION: ask me these questions (one batched message), then continue with the stated default if I do not answer

Before writing RTL, inspect the environment and repo, then ask me **only what you cannot determine yourself**:

1. **Board revision**: original Zybo (VGA) or Zybo Z7-10 (HDMI only)? Default: VGA if original Zybo; if Z7-10, implement the HDMI/DVI TX path (§M5b). Ask me to place Digilent's master XDC for my board in `vivado/` (or confirm you may download it); use its exact pin names.
2. **UART adapter**: which Pmod header and pins is it on (JA–JE, which pins)? Default: JB pins 1–4 wired as a Pmod USBUART.
3. **VL326 RV32I SoC**: search the repo first (`find . -iname '*vl326*' -o -iname '*rv32*'`). If not found, ask me whether I have the RTL (course portal / TA). **Default if I don't have it: vendor PicoRV32 (YosysHQ/picorv32, ISC licence)** with its native memory interface behind a small address decoder, and keep the bus interface clean enough that the VL326 core can replace it later.
4. **Tools present on this machine**: detect and report (do not ask): `vivado` (version), `iverilog`, `verilator`, `yosys`, `sby` + solvers, `NuSMV`, `espresso`, `riscv32-*/riscv64-*-gcc`, python packages (`numpy`, `pillow`, `matplotlib`, `pyeda`/`dd`). Tell me exactly what is missing and what that blocks. If Vivado is absent, still write all Tcl/XDC and run everything else; I will run Vivado.
5. Any real test photos I want used (default: the 5 synthetic images in `p7_golden.py` plus ≥3 public-domain photos if network is available).

---

## 3. Fixed architecture decisions (change only with a written justification in `docs/decisions.md`)

**Video format.** Standard 640×480@60: total 800×525; H: 640 active/16 fp/96 sync/48 bp; V: 480/10/2/33; sync polarity negative. Pixel clock ≈25.175 MHz.

**Frame store.** 640×480×8 does not fit in BRAM. Store **320×240×8 gray** (76,800 B ≈ 17 BRAM36, 32-bit words) in a dual-port BRAM. The DMA reader outputs it **2×2 nearest-neighbour upscaled** to 640×480 at one pixel/clock (each memory pixel repeated twice horizontally, each memory line read twice). The pipeline therefore sees a true 640×480, 1 px/clk stream.
→ **Golden consequence:** extend `p7_golden.py` with `upscale2x_nearest()`; the golden reference input for RTL comparison is `edge_frame(upscale2x(gray320))`. Keep all existing self-tests passing.
(RGB input path: golden has `rgb2gray`; RTL gray converter is a small module with the same `(77R+150G+29B+128)>>8`, unit-tested, but frames are stored already gray; the RGB→gray unit is exercised by its own testbench and available if a camera is added later.)

**Frame loading.** RV32 firmware receives an image over UART (protocol: bytes `'I','M','G'`, then 2 B width, 2 B height, little-endian, then raw gray bytes) and writes it into the frame BRAM through the bus. One default image is preloaded via `$readmemh` so the demo works with no PC.

**DMA.** A small bus-visible DMA engine (APB regs: `ENABLE`, `START`, `BUSY`, `FRAME_DONE`) streams the frame BRAM into the pipeline, paced by the VGA scan generator (no back-pressure: real-time stream). It must never underrun.

**Pipeline contract (baseline).**
- Stream bus: `pix_data[7:0], pix_valid, pix_sof, pix_eol` (+ `pix_sof` at first active pixel of a frame).
- Line buffers are **BRAM/LUTRAM RAMs addressed by the column counter** (not shift registers). Horizontal/vertical blanking is used to flush last-column/last-row windows (replicate borders in hardware via muxes). Border behaviour **must match the golden**: replicate padding for Gaussian/Sobel; NMS and hysteresis neighbours outside the frame count as 0; NMS output on the 1-pixel frame border forced to non-edge.
- Gaussian parameter `GAUSS_SIZE ∈ {3,5}` via `generate`; hysteresis enable as parameter (+ runtime bypass register).
- Fixed widths (match golden): gray 8 b; smoothed 8 b; Gx,Gy signed 11 b (magnitude of each ≤1020); `mag` 11 b unsigned; `dir` 2 b; NMS value 11 b; class 2 b.
- Direction quantiser: no atan; compare `|Gy|·256` against `|Gx|·106` and `|Gx|·618` (shift-add), tie rules exactly as in `quant_dir()`.
- NMS tie-break exactly as golden: keep iff `m > a && m >= b` with the neighbour pairs in the golden `NB` table.
- Latency is **measured** (cycles and lines, in the VGA total-timing domain) and reported; the output must be pixel-exact on the active area, not cycle-identical to the golden stream model.

**Latency alignment & views.** The display scan must show the processed image registered to the original. Choose and document one strategy: advance the source scan generator ahead of the VGA timing by the pipeline latency (in clocks, including blanking), and use a **second read port of the frame BRAM** for the "original" view (zero latency) and a BRAM/LUTRAM delay line for the "smoothed" view. Count alignment-RAM resources **separately** from the core pipeline in the resource table.

**Views / UI (4 switches, 4 buttons).** `SW[1:0]`: 00 original, 01 smoothed, 10 edges, 11 raw magnitude (or strong/weak colour map). Thresholds: `SW[3:2]` selects among 4 preset `{lo,hi}` pairs; `BTN0/1` = `lo` −/+, `BTN2/3` = `hi` −/+ (debounced, written into the APB regs by hardware or by firmware polling — pick one, document it). Edges displayed white on black (weak = grey, strong = white is a nice option). LEDs: frame heartbeat, hysteresis on, view mode.

**Register map (APB, 32-bit, word-aligned; document in `docs/regmap.md`).**
`0x00 CTRL` (enable, dma_start, hyst_en, view[1:0]) · `0x04 LO` · `0x08 HI` · `0x0C STATUS` (frame_done, vsync_seen, dma_busy) · `0x10 EDGE_COUNT` (latched at frame end) · `0x14–0x50 HIST[0..15]` (16-bin histogram of `mag>>7`, latched at frame end) · `0x54 FRAME_CNT` · `0x58 CRC_EDGE` · `0x5C CRC_SMOOTH` · `0x60 LATENCY_CLKS` (measured).
**Per-frame CRC32** units (zlib-compatible CRC-32/IEEE: reflected poly 0xEDB88320, init/xorout 0xFFFFFFFF) over the active-area pixels in row-major order, one byte per pixel (`edge` byte = `0x00`/`0xFF`). Add `frame_crc()` to the golden using `zlib.crc32`. This is how pixel-exactness is proven **on the board** without a capture buffer.

**SoC.** CPU (VL326 or PicoRV32) + instruction/data RAM (≥16 KB) + bus decoder + UART + timer + APB bridge + frame-BRAM window. Toolchain: `-march=rv32i -mabi=ilp32`. Memory map documented in `docs/memmap.md`.

---

## 4. Repository layout

```
golden/   p7_golden.py, tests/, make_vectors.py          # source of truth
hls/      sobel_cdfg.md, schedule scripts (Python), schedule tables
logic/    truth tables, espresso runs, BDD ordering study, equivalence scripts
rtl/      *.v  (one module per file; parameters, no magic numbers)
tb/       unit + integration testbenches, vector loaders
formal/   *.sby, *.nusmv, bug-injection variants, counterexample traces
fw/       C firmware, linker script, Makefile
vivado/   build.tcl, constraints (xdc), reports/
scripts/  run_all.sh  (sim → formal → synth), compare scripts
docs/     decisions.md, regmap.md, memmap.md, bringup.md, report.md, logs/
vectors/  generated .mem + CRC lists (committed)
```
`scripts/run_all.sh` must run everything reproducibly and exit non-zero on any failure.

---

## 5. Milestones (each has a gate; do not move on until the gate passes or is explicitly blocked and logged)

### M0 — Recon & questions
Environment report, §2 questions, repo skeleton, copy `p7_golden.py` into `golden/`, run its `selftest`.
**Gate:** selftest passes; STATUS.md lists tools and open questions.

### M1 — Golden extensions
Add `upscale2x_nearest`, `frame_crc`, a vector generator that writes, for each of ≥5 images (synthetic + real), the 320×240 gray `.mem`, and expected 640×480 `gray/smooth/mag/dir/nms/cls/edge` `.mem` + per-frame CRCs (both Gaussian sizes, hysteresis on/off, default thresholds + two other threshold pairs). Add parameterised "variant" hooks in the golden for the paper technique (§M9) so the approximate/reduced-memory variant has its own bit-exact reference.
**Gate:** `pytest`/selftest green; vectors committed; vector manifest with checksums.

### M2 — Hand HLS: Sobel window + magnitude (course requirement)
In `hls/sobel_cdfg.md` + scripts, show **by hand** (not with an HLS tool):
1. CDFG of Gx, Gy, `|Gx|+|Gy|` on the 3×3 window (list every op node).
2. **CSE between Gx and Gy** (e.g., shared differences/sums of window pixels); op counts before/after.
3. **Tree-height reduction** of the adder trees; critical-path depth before/after.
4. A **pipelined schedule with initiation interval 1**: table of ops per control step, register insertion points, resource binding (adders/subtractors/abs units), latency in cycles.
5. A Python script that executes the *scheduled* DFG on random windows and checks equality with `sobel_scalar()` (also the exhaustive-corner cases).
Then write `rtl/sobel_unit.v` strictly following the schedule (document any deviation).
**Gate:** schedule-vs-golden script passes 1e6 random windows; RTL unit test bit-exact vs golden on ≥1e5 random windows including extremes (all 0, all 255, alternating).

### M3 — Logic-optimisation / BDD block (course requirement)
Block A: **direction quantiser** (inputs: comparator outputs `ay·256 ≤ ax·106`, `ay·256 ≥ ax·618`, signs of Gx, Gy → 2-bit `dir`). Block B: **NMS select** (inputs: `dir`, `m>a`, `m>=b` flags from the muxed neighbours → `keep`; plus the neighbour-select decode of `dir`).
- Write truth tables, minimise with **ESPRESSO** (if the binary is missing, implement Quine–McCluskey in Python and say so), generate Verilog, and compare to a naive behavioural/case implementation: LUTs (Yosys or Vivado), logic depth.
- Build **BDDs** for each output with ≥3 variable orderings; table of node counts per ordering.
- Prove equivalence minimised-vs-reference exhaustively (inputs are few) and via Yosys `equiv` or an `sby` miter.
**Gate:** equivalence proven; tables saved; the minimised block is the one used in the pipeline.

### M4 — Core streaming pipeline (no video I/O yet)
Modules: `gray_conv`, `linebuf` (parameterised depth/width, BRAM or LUTRAM inferred by attribute), `win3x3`/`win5x5` (replicate borders), `gauss3`/`gauss5` (shift-add, with rounding term), `sobel_unit` (M2), `dir_quant` + `nms_select` (M3), `nms_thresh`, `hysteresis`, `pipeline_top`.
Testbenches stream the generated vectors (with realistic 800×525 blanking gaps) and compare **every stage output** with the golden `.mem` files; the top-level compares `edge`.
**Gate:** per-stage and top-level pixel-exact on all vector sets, Gaussian 3 and 5, hysteresis on/off, three threshold pairs. Verilator preferred for full frames (iverilog allowed for unit tests). Log mismatch counts (must be 0).

### M5 — Video timing, frame-sync controller, frame store, DMA, views
`vga_timing` (800×525 counters, sync, active flag, frame/line start strobes), `frame_sync_ctrl` (explicit FSM: IDLE → ACTIVE → HBLANK → VBLANK; line/pixel counters; `sof/eol/eof` generation; start/stop with software enable), `frame_bram` (dual-port), `dma_reader` (2×2 upscale, paced by the advanced scan), latency-alignment RAMs, `view_mux`, output register stage (5-6-5 VGA DAC pins), `crc32_byte` ×2 and `stats_unit` (edge count, histogram, latched at frame end).
**5b (only if board = Zybo Z7-10):** DVI/HDMI TX in Verilog: TMDS 8b/10b encoder ×3, 10:1 serialisation with `OSERDESE2` (5× clock via MMCM ≈125.9 MHz DDR), differential `OBUFDS`. Provide a loopback/unit test for the TMDS encoder against a Python reference.
**Gate:** full-frame simulation of the whole video path: active-area pixels equal golden; **CRC registers equal golden CRCs for ≥5 images**; no DMA underrun; measured latency printed and matches the structural latency from the design notes.

### M6 — SoC + firmware
Integrate CPU, RAM, bus, UART, timer, APB regs. Firmware (`fw/`): UART image loader, register init, per-frame print of `FRAME_CNT`, `EDGE_COUNT`, histogram, CRCs, a self-check mode that compares CRCs against a table compiled in from `vectors/` and prints `PASS`/`FAIL` per image, and threshold polling (if chosen).
**Gate:** RTL simulation of CPU running the firmware end-to-end (UART bit-banged in the testbench) prints PASS for ≥5 images.

### M7 — Vivado build, constraints, reports
`vivado/build.tcl` non-interactive: create project for `xc7z010clg400-1`, read RTL, XDC (pins from the real board file; `create_clock` for 125 MHz and generated pixel clock), MMCM, synth, impl, bitstream, write reports (`utilization`, `timing_summary`, `power`, `clock_utilization`) to `vivado/reports/`.
- **Fmax study:** run out-of-context (or tightened-constraint) implementations of the pipeline at several target clocks (e.g., 25/50/75/100/125 MHz) and report the highest met → "achieved pixel clock" column; the board itself runs at 25.175 MHz.
- Resource table per block (LUT/FF/BRAM/DSP) using hierarchical utilisation.
**Gate:** timing met at 25.175 MHz; utilisation ≤60%; bitstream generated (or "NOT RUN: Vivado absent" + scripts ready).

### M8 — Formal verification (course requirement)
**NuSMV (CTL)** on abstracted controllers (counters abstracted to small bounds): `frame_sync_ctrl` and the DMA/CPU start-stop handshake. Prove at least:
- `AG (state = ACTIVE -> AF (state = VBLANK))` — every frame ends; `AG AF eof` — frames recur while enabled;
- `AG (eol -> line_cnt_next = line_cnt+1 ∨ wrap)` — line/frame counters consistent; `AG (pix_valid -> col < W ∧ row < H)`;
- **No-deadlock:** `AG EF (state = IDLE)` under enable-low, `AG (dma_start ∧ enabled -> AF frame_done)`; DMA never reads an invalid address.
**SymbiYosys** on the RTL: line-buffer write/read pointer invariants (never read an unwritten entry, never overrun), `sof`/`eol` ordering, counters stay in range, stats latch only at `eof`.
**Bug injection:** deliberately break the frame-sync controller (e.g., skip the vblank state when a start pulse arrives mid-frame); show NuSMV/SBY finds a counterexample; replay the trace in simulation (save VCD + notes).
**Gate:** all proofs pass on the correct design; every injected bug is caught; traces saved.

### M9 — Research part
1. **Literature search** (use web search if available; otherwise ask me for papers). Pick **one real, verifiable** paper. Preferred direction (best fit for this board and spec): **memory-efficient line-buffer architecture** — e.g., width-packing narrow line buffers into shared BRAM/LUTRAM, removing per-stage buffer duplication, and storing the NMS-stage magnitude at reduced precision. If a better-fitting paper is found (approximate arithmetic or adaptive-threshold Canny), you may choose it with a written rationale. **Do not invent citations**: record title, authors, venue, year, DOI/URL, and which technique you reproduce and what you changed.
2. Implement it as a **parameterised variant** (`PAPER_VARIANT`), with its own bit-exact golden variant (from M1 hooks).
3. Baseline vs paper: BRAM/LUT/FF, Fmax, **F-score and PSNR vs the baseline golden edge map** across all test images (and vs a float OpenCV Canny if OpenCV is available, as an extra column), plus latency.
**Gate:** variant passes its own pixel-exact test; comparison table + quality-vs-resource plot generated by script.

### M10 — Report, plots, bring-up guide
`docs/report.md` with: architecture diagram (Mermaid/SVG), HLS section, logic/BDD tables, resource table + achieved clock + latency in lines, baseline-vs-paper comparison and plot, formal results (properties, tools, runtimes, counterexample story), limitations. `docs/bringup.md`: exact steps for me to program the board, wire the UART Pmod, run the firmware loader (`scripts/send_image.py` pyserial), and what the LEDs/VGA should show; expected CRC values per test image.
**Gate:** `scripts/run_all.sh` green from a clean checkout.

---

## 6. Engineering rules

- One module per file; `localparam`/parameters for all sizes; no latches; synchronous resets only (or no reset where safe); explicit widths; `default_nettype none`.
- Every RTL module gets a self-checking testbench with a pass/fail line and non-zero exit on failure.
- RAM inference: use coding styles Vivado infers as BRAM/LUTRAM; confirm in the utilisation report; if a buffer lands in the wrong resource, fix it or document why.
- Never edit golden outputs to match the RTL. If RTL and golden disagree, decide which is wrong, fix it, and record why in `docs/decisions.md`. A golden change requires re-generating all vectors and re-running everything.
- Keep unrelated work out; no features beyond this spec (no camera, no PS/DDR path) unless I ask.
- If blocked on a hardware fact only I can supply (pins, adapter, board revision), ask once, batched, continue with the documented default meanwhile.
- At the end, print a final summary: milestone status, gates passed, anything NOT RUN and why, and the list of things I must do on the physical board.

Begin with M0 now.
