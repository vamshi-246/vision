# P7 Viva Study Guide: Real-Time Edge-Detection Video Pipeline

**Group 07.** Gundoju Sai Vamshi (B23263), Shashank Tiwari (B24499).
Report: `report/VL401_G07_P07.pdf`. Demo steps: `docs/DEMO_GUIDE.md`.

Read this guide in order. Each part says **what** a block does, **why** it is built that way, and **how** it works, in plain words. Part 9 lists the questions the professor is most likely to ask, with short answers. Part 10 lists the honest limitations, with how to explain each one.

---

## 1. The project in one minute

> "We built a hardware edge detector that runs on live video. Every clock cycle one pixel goes in and one classified pixel comes out, at 640×480 and 60 frames per second. The algorithm is Canny-style: blur, gradient, thin the edges, then double threshold. It runs on a Zybo Z7-10 FPGA and shows the result on a monitor over HDMI. Switches select the original, blurred, edge or class view, and the threshold preset. A small RISC-V CPU (PicoRV32) reads statistics through APB registers and sets the thresholds. We designed the Sobel datapath with the course's HLS methods and minimised its decision logic with ESPRESSO and BDDs. We verified everything against a Python golden model, with assertions and coverage, and proved properties with NuSMV (CTL) and SymbiYosys. From a 2023 paper we added an adaptive Otsu threshold in a streaming form. Our version fits on the chip; the paper's version does not."

---

## 2. The big picture

```
 laptop photo (JTAG)  or  laptop webcam (HDMI-in)
            │
            ▼
   320×240 frame store (BRAM) ──2× upscale──► gray pixel stream, 1 pixel / clock
            │
            ▼
 ┌──────────────────────── edge_pipeline (the "core") ───────────────────────────┐
 │ line buffer → Gaussian 3×3 → line buffer → Sobel |Gx|+|Gy| + direction →       │
 │ line buffer → NMS (thin edges) → double threshold (class 0/1/2) + 64-bin histogram │
 └────────────────────────────────────────────────────────────────────────────────┘
            │                                         │ APB registers
            ▼                                         ▼
   view mux (SW1:0) + VGA timing 800×525  →  HDMI TX (rgb2dvi) → monitor
                                     PicoRV32 RISC-V reads EDGE_CNT, histogram; writes THR_HI/LO
```

* **Clock.** 25.18 MHz pixel clock from an MMCM. The 640×480@60 standard needs 25.175 MHz. One clock = one pixel. The frame is 800×525 clocks; the extra clocks are blanking.
* **Why no frame buffer in the core?** Every stage only needs a 3×3 neighbourhood, so storing 2 lines per stage is enough. This is the *line-buffer* architecture: 3 BRAM tiles for the whole core instead of megabits for a frame.
* **Latency.** About 3 lines (2,415 clocks = 3 lines + 15 clocks at the 800-clock line). Each 3×3 stage needs one line from the future: the row below the centre pixel.

---

## 3. The core, stage by stage

### 3.1 Grayscale
`gray = (77R + 150G + 29B) >> 8`. These are the standard luminance weights (0.299, 0.587, 0.114) times 256, so only shifts and adds are needed. (In the still-image build the stored photo is already gray.)

### 3.2 Line buffer (`rtl/linebuf.sv`). The heart of streaming
* **What:** it turns a stream of single pixels into a stream of 3×3 windows.
* **How:**
  * Two BRAM rows store the previous two lines. A 3×3 register array shifts left every valid clock.
  * The two rows are used alternately. When line *y* arrives, the row being overwritten holds line *y−2*, which is no longer needed, so no data ever has to be copied.
  * Each read is synchronous and *read-first*: the old value comes out while the new value is written.
* **Valid rule:** a window is valid only when its centre is at least one pixel inside the image. That is why each 3×3 stage loses one border pixel, and the final class map has a 3-pixel zero border.
* **Coordinates travel with the data.** So if the input has gaps (blanking, a stalled source), nothing goes out of alignment.

### 3.3 Gaussian blur (`rtl/gauss.sv`)
* Kernel 1-2-1 / 2-4-2 / 1-2-1, total 16, so `smooth = (sum + 8) >> 4`. The `+8` rounds to nearest instead of truncating.
* All multiplications are by powers of 2, so they are shifts (wires). There are no multipliers.
* **Why blur?** Sobel amplifies noise; blurring first removes small random edges.

### 3.4 Sobel gradient (`rtl/sobel.sv`). Designed with hand HLS
```
Gx = (p02 + 2p12 + p22) − (p00 + 2p10 + p20)      (right column − left column)
Gy = (p20 + 2p21 + p22) − (p00 + 2p01 + p02)      (bottom row − top row)
mag = |Gx| + |Gy|                                   (L1 norm, 0..2040, 11 bits)
```
* **CSE trick:** E1 = p22 − p00 and E2 = p02 − p20 appear in both gradients, so Gx = E1 + E2 + 2F and Gy = E1 − E2 + 2G, with F = p12 − p10 and G = p21 − p01. This needs 8 adders instead of 10.
* **Pipeline:** 4 register stages, II = 1 (a new window every clock).
  * Stage 0: E1, E2, F, G.
  * Stage 1: Gx, Gy.
  * Stage 2: absolute values and signs.
  * Stage 3: magnitude plus the direction comparators.
* **Why |Gx|+|Gy| and not √(Gx²+Gy²)?** A square root needs multipliers and many cycles. The L1 norm is only an add, and it is a standard approximation in hardware Canny.

### 3.5 Direction quantisation (`rtl/dir_decide.sv`, generated by ESPRESSO)
* NMS only needs to know which of 4 directions (0°, 45°, 90°, 135°) the gradient points in.
* The boundary between "horizontal" and "diagonal" is 22.5°, and tan 22.5° ≈ 0.414 ≈ 13/32.
  * `c0 = 32|Gy| ≤ 13|Gx|`: the gradient is mostly horizontal, so sector 0.
  * `c2 = 32|Gx| ≤ 13|Gy|`: the gradient is mostly vertical, so sector 2.
  * Otherwise it is diagonal: sector 1 if Gx and Gy have the same sign, sector 3 if not.
* Multiplying by 13 = `(x<<3)+(x<<2)+x`; by 32 = `x<<5`. **0 DSP blocks.**
* The 4-input decision (c0, c2, sx, sy → 2-bit dir) was minimised from 10 terms / 40 literals to 4 terms / 10 literals.

### 3.6 Non-maximum suppression (`rtl/dirnms.sv`)
* **What:** it thins thick edges to 1 pixel. A pixel survives only if it is a local maximum *across* the edge, i.e. along its gradient direction.
* **How:**
  * Pick the two neighbours along the direction: W/E for sector 0, NW/SE for 1, N/S for 2, NE/SW for 3.
  * Keep the pixel if `m > 0 && m ≥ earlier && m > later`. "Earlier" and "later" are in raster (scan) order.
* **Why ≥ on one side and > on the other?** On a flat plateau of equal values, strict `>` on both sides would delete every pixel, and `≥` on both would keep them all. The asymmetric rule keeps exactly one.

### 3.7 Double threshold + histogram (`rtl/classify_hist.sv`)
* `class = 2 (strong) if m ≥ T_hi; 1 (weak) if m ≥ T_lo; 0 otherwise` (and always 0 if m = 0).
* **Histogram:**
  * 64 bins of the non-zero NMS values; the bin is `m[10:5]`, so each bin is 32 levels wide.
  * Two banks, *ping-pong*: one counts the current frame, while the finished one is the readable snapshot. They swap at the end of each frame.
  * The CPU reads the bins over APB.
* *(We did not ship full hysteresis, i.e. "weak becomes strong if connected to strong". The class view shows weak and strong in different colours instead. An optional `hyst_stage.sv` exists.)*

---

## 4. Video, board and SoC

* **`vga_timing.sv`:**
  * Two counters: h 0..799 and v 0..524.
  * `de` (display enable) is high for h < 640 and v < 480.
  * hsync is low for h in 656..751; vsync is low for v in 490..491.
  * `sof`, `eol` and `eof` mark the frame start, line end and frame end.
* **Frame store:**
  * 320×240×8 bit in BRAM. A full 640×480 frame is 2.46 Mb, but the chip only has 2.16 Mb of BRAM.
  * It is shown 2× (each stored pixel is used for a 2×2 block).
  * The laptop writes it over **JTAG-to-AXI** (`scripts/fpga_image.py`).
* **View mux:** SW1:0 selects 00 original, 01 smoothed, 10 strong edges, 11 classes (colour). The original and smoothed views are delayed by the same 2,415 clocks as the edges, so all views line up.
* **HDMI:** Digilent `rgb2dvi` serialises RGB to TMDS (10 bits per colour per pixel at 5× the clock, DDR). It is DVI-compatible, which is HDMI without audio.
* **Live mode (BTN2):**
  * The laptop shows the webcam full-screen on a second "monitor", which is really the FPGA's HDMI-in port at 800×600.
  * `dvi2rgb` receives it. We convert to gray and downscale 2.5:1 to 320×240.
  * An **asynchronous FIFO** crosses from the 40 MHz receive clock to the 25.18 MHz pixel clock, and the result is written into the frame store.
  * Why 800×600? The receiver IP needs at least 40 MHz to align.
* **SoC (`rtl/soc`):**
  * PicoRV32 is a small RV32I core (no multiplier), with 8 KB RAM, a mailbox and an **APB3 master**.
  * APB has two phases: SETUP (PSEL=1, PENABLE=0), then ACCESS (PENABLE=1, wait for PREADY).
  * Once per frame the firmware reads EDGE_CNT and the 64 bins, then writes THR_HI and THR_LO.
  * There is no interrupt; it polls FRAME_CNT.
* **Register map:** CTRL 0x00, THR_HI 0x04, THR_LO 0x08, STATUS 0x0C (sticky, write-1-to-clear), EDGE_CNT 0x10, FRAME_CNT 0x14, HIST_IDX 0x2C, HIST_DATA 0x30, VERSION 0x34.

---

## 5. What each course unit looks like in this project

### Unit 1: High-level representation (CDFG) and transformations
A **CDFG** is a graph of operations (nodes) and data dependencies (edges). Transformations we applied to Sobel:

| Version | Mult | Add | Critical path |
|---|---|---|---|
| Original 3×3 convolution (loop, 9 taps per gradient) | 22 | 19 | 12 steps |
| Constant folding + dead-code elimination (×0 removed, ×1 folded) | 8 | 13 | 9 |
| Strength reduction (×2, ×32 become shifts; ×13 becomes shift-add) | 0 | 17 | 9 |
| Tree-height reduction (balanced add trees instead of a chain) | 0 | 17 | 7 |
| CSE (share E1, E2 between Gx and Gy) | 0 | 15 | 7 |

* **Tree-height reduction:** `a+b+c+d` done left to right is 3 sequential adds (depth 3); `(a+b)+(c+d)` is depth 2. It is the same number of adders on a shorter critical path.
* **CSE:** compute a common subexpression once and reuse it. It saves adders without changing depth.

### Units 2–3: HLS. Scheduling, allocation and binding
* **ASAP:** schedule each op as early as its inputs allow.
* **ALAP:** schedule each op as late as the latency bound allows.
* **Mobility** = ALAP − ASAP. Mobility 0 means the op is on the critical path. Here only F, G (mobility 1) and the magnitude add (mobility 2) can move.
* **List scheduling** (resource-constrained):
  * In each step, from the ready ops, pick the highest priority (longest path to the end) up to the number of units.
  * With 2 adders + 1 abs unit: 9 steps. With 1 adder + 1 abs unit: 15 steps.
* **ILP** (exact): variables x[op,step] ∈ {0,1}, constraints "each op once", "precedence", "units per step ≤ N"; minimise N.
  * It confirmed that 9 steps needs 2 adders and 7 steps needs 3 adders + 2 abs, so list scheduling was optimal here.
  * FDS (force-directed scheduling) is the heuristic alternative to ILP for time-constrained scheduling; we used ILP because it is exact for this small graph.
* **Left-edge register binding:**
  * Each value lives from the step it is produced to its last use (an interval).
  * Sort the intervals by start and put each one in the first register that is free.
  * Result: 4 registers, which equals the maximum number of values alive at the same time, so it is optimal (interval graphs).
* **Clique partitioning (FU binding):**
  * Two ops are *compatible* if they are in different steps, so they can share a unit.
  * Group the compatibility graph into cliques; each clique becomes one adder. We got 2 cliques = 2 adders.
* **FSMD:** the controller (a step counter = the FSM) plus the datapath (shared units, multiplexers, registers). Our script **generates the FSMD Verilog** from the schedule and binding; both versions pass 100,000 random windows against the shipped Sobel.
* **Key surprise (be ready to explain it):** the FSMD with *fewer operators* uses **more LUTs** (358 and 256) than the pipelined version (141). There are two reasons:
  1. A shared unit must be as wide as its widest job: 16 bits for the comparators, against 9–11 bits for most adds.
  2. Every shared input needs a multiplexer, and on an FPGA a multiplexer costs about the same LUTs as the small adder it saves.
  Sharing only pays for expensive units such as multipliers. The pipeline is also the only design that meets 1 pixel per clock.
* **Operator library:** we measured each operator on the actual chip (e.g. an 11-bit add is 11 LUTs, 2.3 ns). At the 39.7 ns pixel clock, several operators fit in one clock. The shipped Sobel uses this *chaining* to pack 17 ops into 4 stages.

### Unit 3: Logic optimisation and FSMs
* **FSM studied:** the controller of the adaptive-threshold unit (`rtl/otsu_ctrl.sv`). It has 6 states: INIT, ARM, COLLECT, SWEEP, CLEAR, PEND.
* **State minimisation (implication chart):**
  * Make a table of all state pairs. Cross out (X) any pair whose outputs differ for some input.
  * For each remaining pair, list the next-state pairs it implies. Repeat: cross out a pair if any pair it implies is crossed out.
  * Pairs never crossed out are equivalent.
  * Our specification had 7 states, with RECOVER (after an overrun or disable) separate from INIT (after reset). The chart showed **INIT ≡ RECOVER** (same outputs, same next states), so 7 → 6 states.
* **State encoding:**

| Encoding | Bits | LUT | FF |
|---|---|---|---|
| binary | 3 | 16 | 17 |
| gray | 3 | 17 | 17 |
| Johnson | 3 | 16 | 17 |
| one-hot | 6 | **12** | 20 |
| our heuristic | 3 | 15 | 17 |

  * One-hot uses the fewest LUTs: each next-state bit depends on few bits, which suits 6-input LUTs. The cost is more flip-flops.
  * Heuristic: give "related" states (common next state, common previous state, same outputs) codes that differ in 1 bit; we searched all code assignments for the minimum weighted Hamming distance.
* **Two-level minimisation:**
  * *Quine–McCluskey:*
    1. Combine minterms that differ in one bit, repeatedly, to get all **prime implicants**.
    2. Solve the **unate covering problem (UCP)**: choose the fewest primes that cover all on-set minterms.
  * *UCP tricks:*
    * An **essential prime** (the only cover of some minterm) must be taken.
    * **Row dominance:** drop a minterm row that is covered whenever another row is.
    * **Column dominance:** drop a prime that covers a subset of another's minterms.
    * What remains is the cyclic core; solve it by **branch and bound**.
  * *ESPRESSO:* heuristic EXPAND–IRREDUNDANT–REDUCE loops; `-Dexact` gives the guaranteed minimum.
  * *Our result:* for the 12-input NMS keep function, QM gave 27 primes and a 6-term / 31-literal cover. ESPRESSO heuristic and exact agree. The cyclic core was empty: essentials + dominance solved it.
  * *Don't-cares:* c0 = c2 = 1 only happens when Gx = Gy = 0 (signs 0), so the other combinations are don't-cares.
* **Multilevel (kernels):**
  * A **kernel** is a cube-free quotient of the expression divided by a cube; that cube is the **co-kernel**. Common kernels can be factored out.
  * Our kernel `sx·sy' + sx'·sy` is an XOR. Factoring gives "decode the sector, then select the pair": 17 literals instead of 31.
  * Yosys+ABC on the RTL: 3 LUT6, or 8 gates with MUX/XOR.

### Units 4–5: Temporal logic (CTL) and model checking
* **Kripke structure** M = (S, R, L): states, a transition relation, and a labelling with atomic propositions.
* **CTL** = path quantifier (A = all paths, E = some path) + temporal operator (X next, F eventually, G always, U until).
  * `AG p` means p is always true on every path (safety).
  * `AG (req → AF ack)` means every request is eventually answered (liveness).
  * `AG EF init` means from anywhere you can always get back to init (no deadlock, resettable).
* **Labelling algorithm:**
  * `EF p`: backward reachability from the p-states.
  * `EG p`: keep only the p-states, find the strongly connected components (SCCs) with a cycle, then label everything that can reach them inside the p-states.
* **Fairness:** a liveness property can fail only because the environment never does something, e.g. the Otsu unit never says "done". `FAIRNESS odone` tells the checker to consider only paths where odone is true infinitely often.
  * Property P8 `AG(SWEEP → AF CLEAR)` is **false** without fairness and **true** (P9) with it. We found this by hand too: SWEEP has a self-loop, so `EG ¬clear` holds there.
* **Our results:**
  * 12 properties on the controller (safety, reachability, non-blocking, liveness with fairness, an Until property).
  * 10 on `vga_timing` (frame/line synchronisation: counters bounded, SOF only at (0,0), EOL only in active video, frame wraps, `AG EF sof`, `AG EF eof`).
  * 3 on `ctrl_sync`; no deadlock state anywhere.
* **Bug injection:**
  * B1: thresholds applied while a new frame has already started. P3 fails; the counterexample was replayed in simulation, which shows "thresholds changed inside frame".
  * B2: CLEAR waits for a signal that never comes. The liveness property fails with a loop counterexample; in simulation the threshold never updates.
* **A story to tell:** our first version of one property (`AG AF COLLECT`) was false even with fairness. With back-to-back frames the controller legitimately cycles PEND → SWEEP → CLEAR, so we corrected the property, not the design.

### Unit 6: BDDs
* **ROBDD:** a decision diagram with a fixed variable order and two reductions: merge identical subgraphs, and remove nodes whose two children are the same.
  * It is **canonical**: two functions are equal exactly when their BDDs are the same node. That makes equivalence checking trivial.
* **Variable order matters:**
  * Comparator `32|Gy| ≤ 13|Gx|` with 22 variables: interleaved MSB-first 554 nodes, interleaved LSB-first 403, blocked (all Gx bits, then all Gy bits) **4,085**.
  * **Sifting** (Rudell: move one variable at a time to its best position) gives **283** (228–405 depending on the order in which variables are visited; it is a greedy heuristic).
  * Why is blocked bad? The BDD has to "remember" all 11 bits of Gx before it sees Gy.
* **Equivalence check:** the specification, our QM cover, the ESPRESSO cover and the RTL after Yosys/ABC all give the same BDD node, so they are equivalent.
* **Symbolic reachability:** R₀ = reset state; R_{k+1} = R_k ∪ Image(R_k), where the image is ∃(present state, inputs).[R(s) ∧ T(s,i,s′)]. Repeat until nothing changes. We found 6 reachable states out of 8 codes, the same as NuSMV.

### Unit 7: Verification techniques
* **Golden model** (`model/golden.py`): the executable specification. Testbenches compare every stage, every pixel, at its exact position, so missing or extra pixels are caught too.
* **Directed + random + natural images**, three timing modes (continuous, random gaps, real blanking). Totals: 29.75 million pixels at 640×480 with 0 mismatches, plus an exhaustive 4,169,764-case direction test.
* **Mutation testing:** deliberately break the RTL (7 mutants) and check that the testbench catches each one. This proves the tests are not weak.
* **SVA assertions** (13, attached with `bind` so the RTL is untouched). Example: `out_valid == $past(in_valid, 4)` means Sobel has a fixed 4-clock latency and II = 1. A mutant that outputs the illegal class 2'b11 is caught by an assertion.
* **Coverage:** Verilator line + toggle coverage is 96.3%. The uncovered parts are histogram saturation, which cannot happen in a small frame and is tested separately.
* **Lint:** `verilator --lint-only -Wall` gives only intentional "unused bits" warnings.
* **SymbiYosys:**
  * **BMC** (bounded model checking): no assertion fails in the first 30 cycles from reset.
  * **k-induction:** if the assertions hold for k consecutive cycles, they hold in the next one. Together with the base case this proves them for *all* time.
  * Proved on `vga_timing` at the real 800×525 size, the controller, and the APB registers.
* **On the board: ILA** (Integrated Logic Analyzer, `make ila`). A debug build adds a logic analyzer inside the FPGA: 16 probes on the pixel clock (input pixel, Sobel magnitude/direction, output class and coordinates, thresholds, edge counter), 4,096 samples deep. It was triggered on output row 240 of an uploaded photo; all 3,260 classified pixels in the capture equal the golden model (0 mismatches). The register read-backs (edge count, 64-bin histogram) match the model too.

---

## 6. The research paper

* **Paper:** L. Guo and S. Wu, *FPGA implementation of a real-time edge detection system based on an improved Canny algorithm*, Applied Sciences 13(2):870, 2023.
* **Their idea:**
  * Choose T_hi automatically for each frame with **Otsu's method**: the threshold that best separates the histogram into two classes, i.e. maximises the between-class variance; T_lo = T_hi / 2.
  * Do it **without division**, using logarithms: log(a/b) = log a − log b, and log₂ is approximated by a leading-one detector plus a small lookup table.
* **Problem:**
  * Their design stores the whole frame, computes the threshold, then classifies the same frame. At 640×480 that needs **80 RAMB36**, and our chip has **60**. It does not fit.
  * It also delays the output by a frame.
* **Our streaming version** (`rtl/otsu_stream.sv` + `rtl/otsu_ctrl.sv`):
  * Video frames are similar from one to the next, so we compute the threshold from frame N and use it for frame N+1. No frame buffer is needed.
  * The 256-bin histogram is built on the fly in two ping-pong BRAMs. The read–add–write pipeline has one forwarding register, for when the same bin is hit on two clocks in a row.
  * At the frame end, the paper's own Otsu unit (unchanged) runs during vertical blanking: about 520 clocks out of 36,000 available.
  * The controller makes sure thresholds change **only between frames**. If a new frame has already started, the result waits for the next frame end (state PEND).
  * The zero border of 6,684 pixels is added to bin 0, so our histogram equals the paper's whole-frame histogram.
* **Results:**
  * Thresholds are **identical** to the paper engine on all 6 images (102, 110, 98, 84, 46, 80), and all 300,516 classes per image are equal.
  * Cost: +1 BRAM tile, +10 DSP, Fmax 52 MHz (more than 2× the 25.2 MHz needed). The slow path is the paper's combinational 48-bit log₂ unit (25 logic levels); one more pipeline register would fix it. The paper's version: 80 RAMB36, which does not fit.
  * Quality: the strong-edge F1 rises from 0.41 to 0.83, because a fixed T_hi = 192 is too high for low-contrast images (e.g. *chelsea* gets T_hi = 46).
  * For the strong+weak map, our fixed 64/192 thresholds are slightly better (0.925 vs 0.877). Say this honestly; there is a trade-off.
* **Status:** verified in simulation and synthesised, but **not yet in the board bitstream** (planned future work).

---

## 7. Hardware/software comparison
* The same algorithm was written in C (`fw/swedge/swedge.c`) and run on the same PicoRV32 in simulation: **437 clocks per pixel**, with an output bit-exact with the model.
* The hardware takes **1 clock per pixel**, so it is about **437× faster**.
* For a full 640×480 frame, software would take about 5.3 s at 25 MHz (0.19 fps) against 60 fps in hardware.
* That is why the CPU only supervises (statistics, thresholds) and the hardware does the pixels. This is **hardware/software partitioning** (Unit 2).

---

## 8. Key numbers cheat sheet

| What | Number |
|---|---|
| Resolution / rate / clock | 640×480 @ 60 Hz, 800×525 raster, 25.18 MHz |
| Throughput | 1 pixel / clock (II = 1) |
| Latency | 3 lines + 15 clocks (2,415 clocks) |
| Core resources | 2,108 LUT, 3,080 FF, 3 BRAM tiles, 0 DSP, ~87 MHz |
| Full board (Z7, still image) | 7,937 LUT, 6,683 FF, 27.5 BRAM, WNS +6.73 ns, 0.36 W |
| Full board (Z7, live) | 8,699 LUT, 7,585 FF, 27.5 BRAM, WNS +1.41 ns, 0.60 W |
| Sobel transformations | 22 mult + 19 add, 12 steps → 0 mult + 15 add, 7 steps |
| HLS schedules | 2 adders + 1 abs → 9 steps; 1 + 1 → 15 steps (ILP-optimal) |
| Left-edge registers | 4 |
| FSM | 7 → 6 states (INIT ≡ RECOVER); one-hot 12 LUT |
| NMS keep function | 12 inputs, 27 primes, 6 terms / 31 literals (QM = ESPRESSO = exact) |
| dir_decide | 10 terms / 40 literals → 4 / 10 |
| BDD comparator | 554 / 403 / 4,085 nodes → 283 after sifting (228–405) |
| CTL | 25 properties (12 controller, 10 vga_timing, 3 ctrl_sync) |
| SVA / coverage | 13 assertions, 4 covers (all hit), 96.3% line+toggle (31×23 run) |
| Pixels compared | 29,751,084 at 640×480, 0 mismatches |
| HW vs SW | 437 clocks/pixel in software, 437× speed-up |
| Paper (streaming) | T_hi identical on 6 images; 3,385 LUT, +1 BRAM, +10 DSP, 52 MHz vs 80 RAMB36 |

---

## 9. Likely viva questions, with short answers

**Algorithm**
1. *Why Gaussian before Sobel?* Sobel is a derivative, and derivatives amplify noise. Blurring first removes small false edges.
2. *Why |Gx|+|Gy|?* It is cheap (one adder) and keeps the ordering good enough for thresholding. √ would need multipliers or a CORDIC.
3. *How do you get the direction without arctan?* Compare 32|Gy| with 13|Gx|: tan 22.5° ≈ 13/32. Shifts and adds only.
4. *What does NMS do, and why the asymmetric tie rule?* It keeps only the local maximum across the edge, which gives thin edges. With "≥ earlier, > later", a plateau of equal values keeps exactly one pixel.
5. *Why a double threshold?* Strong edges are certain. Weak edges are kept as a separate class; full Canny would keep a weak edge only if it is connected to a strong one (hysteresis).

**Architecture / RTL**
6. *How does the line buffer work?* Two BRAM rows used alternately plus a 3×3 shift-register window. The row being overwritten holds line y−2, which is no longer needed.
7. *Why does the output have a 3-pixel border?* Each 3×3 stage needs a full neighbourhood, so each stage loses one pixel per side.
8. *What happens if the input pauses?* Nothing breaks: everything is qualified by `valid` and the coordinates travel with the data.
9. *Latency?* About 3 lines (one line per 3×3 stage) + 15 clocks of pipeline registers = 2,415 clocks.
10. *Why are all four views aligned?* The original and smoothed views go through a delay line of the same 2,415 clocks.
11. *What is II=1?* Initiation interval 1: a new input can start every clock.
12. *Why no DSP?* Every constant multiply is shift-add.
13. *Clock domain crossings?* In live mode, from the 40 MHz HDMI receive clock to the 25.18 MHz pixel clock, through an asynchronous FIFO (Gray-coded pointers inside), declared asynchronous in the constraints.
14. *Reset?* Synchronous, active high. The BRAMs are not reset; the valid logic ignores the first two rows instead.

**HLS**
15. *Difference between ASAP and ALAP?* Earliest vs latest possible step; the difference is the mobility. Ops with mobility 0 are critical.
16. *List scheduling vs ILP vs FDS?* List: greedy, resource-constrained, fast. ILP: exact, slow on big graphs. FDS: heuristic, time-constrained, balances the usage of units.
17. *Left edge?* Sort the lifetime intervals by start and pack them into the first free register. It is optimal for interval graphs.
18. *Why is the "minimum-area" FSMD bigger?* Multiplexers plus the 16-bit-wide shared units cost more than the small adders saved (Part 5).
19. *What did CSE save?* 2 adders (10 → 8 for the gradients).
20. *Tree-height reduction?* A balanced tree instead of a chain: depth log₂(n) instead of n−1.

**Logic / FSM**
21. *Implication chart?* Cross out pairs with different outputs, then pairs whose implied pairs are crossed out. Whatever is left is equivalent.
22. *Why does one-hot use fewer LUTs?* Each state bit's next-state equation is simple. It needs more FFs, but FPGAs have plenty of FFs.
23. *Prime implicant vs essential prime?* A prime cannot be made bigger. An essential prime is the only prime covering some minterm.
24. *ESPRESSO steps?* EXPAND (make cubes prime), IRREDUNDANT (remove redundant cubes), REDUCE (shrink cubes to escape a local minimum), repeated.
25. *What is a kernel?* A cube-free quotient of an expression by a cube (the co-kernel). It is used to find common factors in multilevel logic.

**Formal**
26. *Safety vs liveness?* Safety: something bad never happens (AG ¬bad); a finite counterexample exists. Liveness: something good eventually happens (AF good); its counterexample is an infinite loop (a lasso).
27. *Why fairness?* Without it, the checker can blame the environment (e.g. "the Otsu unit never finishes"). Fairness restricts the check to realistic paths.
28. *AG EF vs AF?* AG EF p: p is always *reachable* (non-blocking). AG AF p: p will *definitely* happen again.
29. *What is a counterexample, and how did you use it?* A trace that violates the property. We replayed both bug traces in simulation and saw the bugs.
30. *State explosion?* The number of states grows exponentially with the number of FFs. That is why we model-check reduced sizes in NuSMV, and use k-induction (SymbiYosys) for the real size.
31. *BMC vs k-induction?* BMC proves "no bug in the first k cycles". Induction proves "if correct for k cycles, then correct forever"; with the base case this is a complete proof.
32. *Why does BDD variable order matter?* A BDD's size can change exponentially with the order. Related bits should be close together: interleave the two operands of a comparator.
33. *How does a BDD do equivalence checking?* ROBDDs are canonical, so two equal functions give the same node.

**Verification**
34. *How do you know your testbench is good?* Mutation testing (7 + 1 mutants caught), 96% coverage, an exhaustive direction test, and two independent golden models that agree.
35. *What is `bind`?* It attaches an assertion module to an RTL module without editing the RTL.
36. *What did simulation find?* A zero-threshold corner case (a zero NMS value became "weak"), a histogram clear losing a sample, and an APB status event lost on a simultaneous clear. On hardware: BTN0 reset the thresholds to the presets (fixed in the firmware).

**Paper**
37. *Why didn't you implement the paper exactly?* It needs a frame buffer of 80 RAMB36, but the chip has 60. We kept their Otsu unit and changed the architecture to streaming.
38. *Is using frame N's threshold on frame N+1 correct?* For video, yes: consecutive frames are almost the same. For a still image it gives exactly the paper's result from the second frame on, as our test shows.
39. *Why log domain?* It avoids division: comparing (a²)/(b·c) becomes 2·log a − log b − log c, which is only subtractions.

**SoC / board**
40. *Why APB?* It is simple, low-power and has a fixed two-phase protocol, which is enough for a few control registers.
41. *How does the laptop talk to the board?* JTAG-to-AXI over the programming cable: it writes the photo and the firmware, and reads the mailbox.
42. *Why HDMI and not VGA?* The Z7-10 has no VGA connector. We generate exact VGA (VESA) timing and send it over DVI/HDMI.
43. *How did you debug on the board? (ILA screenshot)* An ILA build: Vivado inserts a logic analyzer core after synthesis on nets we marked `mark_debug`, connected through the JTAG debug hub. We trigger on `cv=1 && cy=240 && cx=3` (start of output row 240). In the screenshot the cursor is on pixel (451, 240) with `cls=2` (strong), and `running_edges` counts it. Probes are at different pipeline stages, so values in one column are different pixels. It costs ~11 BRAM tiles, so it is a separate debug bitstream, not the demo one.

---

## 10. Honest limitations, and how to say them

| Limitation | What to say |
|---|---|
| HDMI instead of VGA | The board has no VGA port. The timing is exactly VGA 640×480@60; only the physical layer differs (TMDS). |
| No DMA / DDR, no OV7670 | DMA needs the Zynq ARM side + DDR + AXI VDMA. We used a BRAM frame store loaded over JTAG, and live video over HDMI-in from a webcam instead of the OV7670. |
| 320×240 stored image | A full 8-bit 640×480 frame (2.46 Mb) is bigger than all the on-chip BRAM (2.16 Mb). It is shown 2× enlarged. |
| No interrupt | The firmware polls once per frame (60 Hz); an interrupt is easy to add. |
| Paper unit not on the board yet | It is verified and synthesised (fits, meets timing in OOC); integrating it behind a switch is next. |
| No SDF timing simulation | Static timing analysis passes with margin, and the routed-netlist functional simulation passes; the SDF run of the HDMI serialiser was not finished. |
| NuSMV uses small sizes | That is state explosion. SymbiYosys k-induction proves the real 800×525 size. |
| Full hysteresis not in the shipped design | Weak and strong are shown as separate classes. A hysteresis stage exists (`hyst_stage.sv`) but is not in the bitstream. |

---

## 11. Demo script (2 minutes)
1. Program the board, then show the photo: SW1:0 = 00 original, 01 blurred, 10 strong edges, 11 classes (weak/strong colours).
2. Change SW3:2 to show the threshold presets changing the edge count.
3. On the laptop, `fpga_image.py threshold 30 90`: the CPU applies new thresholds; the mailbox edge count matches the Python model.
4. Press BTN2 for live mode: wave a hand in front of the webcam, then switch the views live.
5. If asked: open `report/VL401_G07_P07.pdf` Section 9 for the paper, or run `make verify` for the regressions.

---

## 12. Where things are (file map)

| Topic | File |
|---|---|
| Core | `rtl/top.sv` (edge_pipeline), `linebuf.sv`, `gauss.sv`, `sobel.sv`, `dir_decide.sv`, `dirnms.sv`, `classify_hist.sv` |
| Board / video | `rtl/video/zybo_hdmi_top.sv`, `edge_video.sv`, `frame_store.sv`, `rx_timing.sv`, `rx_downscale.sv`, `rtl/vga_timing.sv` |
| SoC | `rtl/soc/cpu_subsys.sv`, `rtl/apb_regs.sv`, `fw/src/main.c` |
| Paper (streaming) | `rtl/otsu_stream.sv`, `rtl/otsu_ctrl.sv`, `rtl/study/edge_pipeline_otsu.sv`, `scripts/otsu_stream_check.py` |
| HLS | `hls/sobel_hls.py`, `rtl/study/sobel_fsmd_*.sv` |
| Logic / FSM | `logic/logic_study.py`, `logic/espresso_direction.py` |
| Formal | `formal/run_ctl.py`, `formal/otsu_ctl.py`, `formal/bdd_study.py`, `formal/run_sby.py`, `formal/sby/` |
| Verification | `tb/`, `tb/sva/core_sva.sv`, `scripts/core_regression.py`, `scripts/sva_coverage.py` |
| Golden model | `model/golden.py` |
