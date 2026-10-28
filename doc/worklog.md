# Work log

## 003 - 2026-10-28 - executable reference and RTL arithmetic baseline

**Scope.** Per the requested code-first order, research, reports, temporal
thresholding, control-plane work, and FPGA integration are deferred. This
increment creates only the independently executable image contract and the
first streaming primitives needed to consume it.

**Files added/updated.** `model/golden.py`, `model/fixedpoint.py`, and their
seven pytest checks implement the frozen Appendix-A integer operations:
zero-padded Gaussian, Sobel L1 magnitude, 13/32 direction comparisons,
asymmetric NMS, threshold classification, and optional iterative hysteresis.
`rtl/pkg.sv`, `rtl/vga_timing.sv`, `rtl/linebuf.sv`, `rtl/gauss.sv`,
`rtl/sobel.sv`, and `rtl/dirnms.sv` provide the corresponding shared constants,
video timing, O(width) two-line window storage, Gaussian, Sobel/direction, and
NMS selection primitives. Five focused testbenches are added under `tb/unit/`.
The Makefile `sim` target now runs them rather than reporting a placeholder.

**Verification run.** `make sim; make golden` completed with all checks
passing: `tb_vga_timing`, `tb_gauss`, `tb_linebuf`, `tb_sobel`, `tb_dirnms`,
and `7 passed` from `model/tests`. During development the tests caught and
corrected a Gaussian data/valid pipeline skew, a timing-test port-map issue,
and a centre-kernel rounding-vector error. Icarus notes that it ignores the
simulation-only `unique case` quality in `dirnms`; this is not a functional
failure. Vivado synthesis, formal proof, and board execution remain NOT RUN
because the required tools/hardware are unavailable.

**Next.** Connect the primitives under a frame/border-aware pipeline and
compare full-frame RTL output against generated golden vectors before adding
thresholding, memory control, or board-specific integration.

This log records commands actually run, measured results, changed files, and
the next action. `NOT RUN` means a required tool or hardware item was absent;
it never represents a substitute result.

## 001 — 2026-10-28 — P0 — binding-plan review and specification freeze

**What I understood.** The binding design is a one-pixel-per-clock,
640×480@60 Hz, single-pixel-clock-domain streaming edge pipeline. It uses
only O(width) line storage: Gaussian 3×3 (default), Sobel L1 magnitude and
four directions, asymmetric NMS, double threshold, and optional K-step
geodesic hysteresis. The priority source is a 320×240 ROM expanded 2×2;
DDR/VDMA is later. The required test contract is the Appendix-A integer model,
not the earlier supplied model's replicate-border contract. The primary display
target is a Pmod VGA (J1 on JC, J2 on JD); HDMI is a later fallback that needs
the external rgb2dvi dependency. The APB slave is CPU-agnostic and ARM PS is
the default control CPU.

**Commands run.** `pdftotext -layout` was run across pages 1–40 of
`P7_Master_Project_Plan.pdf`; pages 15–16 were rendered with `pdftoppm` and
visually inspected. `Get-Content -Raw Zybo-Z7-Master.xdc`, `python --version`,
`iverilog -V`, `make --version`, `git --version`, and package/tool discovery
commands were run.

**Measured / observed result.** The PDF is 40 pages. Python 3.12.5, NumPy,
Pillow, Matplotlib, OpenCV, SciPy, pytest, GNU Make 4.4.1, Git 2.51.2, and
Icarus Verilog 12.0 are present. Vivado, Verilator, Yosys, SymbiYosys, a
NuSMV/nuXmv executable, Espresso, a RISC-V GCC toolchain, and scikit-image are
absent. The existing XDC gives K17 for the 125 MHz clock; G15/P15/W13/T16 for
switches; K18/P16/K19/Y16 for buttons; M14/M15/G14/D18 for LEDs; JC/JD for the
two Pmod VGA headers.

**Assumptions frozen.** Target `xc7z010clg400-1` / Zybo Z7-10; default
GAUSS_N=3, direction constant 13/32, baseline K=0, 11-bit magnitude,
zero-padded shrinking valid regions, ARM PS or JTAG-to-AXI control, and Pmod
VGA wiring stated in `doc/decisions.md`.

**Critical checks required before accepting the plan.**

1. Confirm the plan's BRAM calculation: an 8-bit 640×480 cache is 2,457,600
   bits, which is **more than** 60×36,864 = 2,211,840 bits; the text saying
   67 RAMB36 is an underestimate (ceil is 67), and the 60-BRAM conclusion is
   still correct.
2. Measure—not assume—the exact latency after each line-window and registered
   stage. The plan's `L ≈ 3+K` lines is an estimate and blanking must supply
   the actual flush count.
3. Stress same-bin consecutive histogram survivors; a synchronous BRAM
   read-modify-write will otherwise lose increments without forwarding.
4. Test all Gaussian/Sobel/NMS border margins. The final margin is exactly 3
   pixels for 3×3 Gaussian, not the supplied legacy model's replicate border.
5. Test NMS plateaus with the prescribed earlier `>=` / later `>` asymmetric
   tie rule; reversing either sign changes the selected ridge pixel.
6. Check that 125 MHz can generate a legal MMCM output near 25.175 MHz and
   report the exact Vivado value rather than claiming a nominal frequency.
7. Confirm whether the physical Pmod VGA is available; constraints are valid
   only when its J1 header is plugged into JC and J2 into JD.
8. Verify the temporal-threshold scan fits the actual V-blank budget and that
   histogram bank swap cannot overlap an increment.

**Files changed.** Initial `doc/evidence/plan-15.png` and `plan-16.png` are
rendered evidence of the reviewed architecture/timing figures. This log,
decisions, traceability, coding checklist, Makefile, `.gitignore`, and the
P7-specific XDC skeleton are added in the same P0 step.

**Next.** Run the scripted P0 smoke target, record its output, initialise the
repository history, and start P1 literature verification plus the new
Appendix-A golden model.

## 002 — 2026-10-28 — P0 — scripted tool smoke test

**Commands run.** `git init`; `make smoke`.

**Result.** PASS for the available Python scientific stack and Icarus Verilog
12.0. The machine has no Vivado, Verilator, Yosys, SymbiYosys, nuXmv/NuSMV,
Espresso, or RISC-V GCC, each reported as `NOT RUN (missing)`. This is a real
environment limitation, not a waived verification result. The concise command
log is saved as `doc/evidence/p0_make_smoke.txt`.

**Files changed.** `Makefile`, `.gitignore`, `doc/*`, `fpga/zybo_z7.xdc`, and
the specified directory skeleton. Git repository initialised.

**P0 exit gate.** PASS WITH TOOL LIMITATIONS: the specification is frozen,
the repository layout and reproducible target names exist, and all installed
tools passed their smoke invocation. EDA-dependent work is explicitly held as
NOT RUN until the tools become available.

**Next.** P1 starts with an evidence-based re-search of the Appendix-E queries
and a new Appendix-A fixed-point golden model plus tests.

