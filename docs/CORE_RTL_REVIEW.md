# Core RTL and software review — 13 November 2026

## Verdict and scope

The corrected **3x3 Gaussian → Sobel L1/direction → NMS → double-threshold**
core passes the regressions described below. Its software reference is
`model/golden.py`. This is substantial simulation evidence for the supported
baseline, not an exhaustive proof of every possible input or a complete FPGA
deployment sign-off.

The supplied `problem statement.png` is the primary requirement. Existing
`doc/decisions.md` supplies arithmetic choices that the statement leaves open:
Gaussian rounding, 13/32 direction boundaries, asymmetric NMS ties, and a
three-pixel invalid margin. Change note
[`002`](../doc/change_notes/002-core-audit-corrections.md) records the fixes.
Research-paper/adaptive variants and camera/DMA/display integration are outside
this audit. The VGA timing unit received its existing smoke test only.

## Confirmed issues corrected

| Finding | Consequence before correction | Correction and evidence |
| --- | --- | --- |
| Vivado input declarations with `default_nettype none` | Original core failed synthesis with `Synth 8-6735` | Explicit input net types; Vivado 2024.2 synthesizes all six core sources |
| Asynchronous cascade between row memories | Vivado rejected `ram_style=block` on three memories and substituted LUT RAM | Alternating synchronous read-first row banks; six RAMB18 primitives, zero LUT RAM |
| SOF used old line-buffer write address | A frame restart partway through a line could corrupt the first new pixel | SOF applies address (0,0) to the current sample; 76 restart positions tested |
| `thr_hi=0` accepted NMS zero | Flat/suppressed pixels and software borders became strong edges | Nonzero prerequisite for both classes, in RTL and model |
| Histogram clear reset classifier valid | A valid image sample disappeared when clearing statistics | Separate classifier and histogram reset/clear behavior |
| APB clear overwrote new status events | A simultaneous software clear could lose an error/event | Event bits are set-dominant; collision test included |
| Missing SOF not checked | Source checker accepted a frame with no SOF | Check both missing and unexpected SOF |
| No-resize image path used OpenCV gray conversion | Different software gray bytes depending on CLI resize option | Both paths use the integer 77/150/29 conversion |
| RGB vector exporter flattened raw RGB | Three samples per pixel instead of the RTL gray input | Export the model's grayscale array |
| Competing golden entry points | `golden/p7_golden.py` ran a semantically different legacy model | Compatibility entry point now uses `model/golden.py`; original legacy file preserved |
| Image bench lacked output coverage checks | Missing/duplicate zero pixels could escape a final binary-image comparison | Strict ordered coordinates, markers and output count; input valid deasserted after frame |
| Image-report CLI returned success on mismatch | Shell automation could report a passing process after a failed comparison | Nonzero exit status on mismatch |
| PowerShell runner did not forward custom thresholds or stop reliably on native-tool errors | RTL could run 80/200 while the model used requested values | Forward THR_LO/THR_HI and check each tool's exit code; bench plusargs tested with 30/90 |

Arithmetic widths are explicit in Gaussian and Sobel; unused coordinate and
gradient delay registers were removed. The Gaussian still rounds `(sum+8)>>4`.
No overflow error was found in the supported 8-bit arithmetic. Sobel accepts a
window each clock through four register stages; its unused center tap is
intentional.

## Verification performed

| Check | Coverage | Result |
| --- | --- | --- |
| Python suite | 20 tests, including 100 small-image/configuration comparisons against independent scalar loops, tiny images, borders, RGB paths and report failure status | PASS |
| Existing RTL unit suite | 11 benches; updated drain timing for synchronous line memories | PASS |
| Full Verilator regression | 642 frame presentations; sizes 7x7, 8x8, 13x9, 31x23, 320x240, 640x480 | PASS |
| Independent Icarus pipeline regression | 504 small-frame presentations across all three traffic modes | PASS |
| VGA coverage | 23 frames in each of three modes: uninterrupted, randomly stalled, 160-clock horizontal/45-line vertical blanking | PASS |
| Stage comparisons | 26,358,834 Gaussian samples; 26,107,986 Sobel samples; 25,862,274 NMS samples and output classes | Zero mismatches |
| Output coverage | Exact ordered coordinates, SOF/EOL, count, all classes, every histogram bin and Nnz after every frame | PASS |
| Arithmetic stress | All 512 binary 3x3 extrema plus 100,000 random windows, with valid bubbles | PASS |
| Direction comparator | All 4,169,764 combinations of `ax,ay=0..1020` and four sign pairs; includes exact rational ties and axes | PASS |
| NMS stress | 73,728 comparison/tie cases and 100,000 random neighborhoods | PASS |
| Histogram/classifier stress | 16,384 magnitudes, eight snapshots/bank swaps, 4-bit counter saturation, invalid cycles, clear with valid pixel | PASS |
| Recovery | 76 line-buffer SOF restarts and 40 core abort positions with one-cycle reset and immediate clean frame | PASS |
| CRC | 110 frames, 327,395 bytes including a VGA-length frame; Python zlib oracle, gaps and adjacent frames | PASS |
| APB/source checker | Address-decode sweep, access errors, W1C/event collision, thresholds and malformed/missing markers | PASS |
| Test sensitivity | Six temporary mutants: Gaussian rounding, magnitude, NMS tie, coordinate offset, final histogram pixel and row selection | All six rejected |
| Supplied JPEG through Icarus image flow | All 307,200 reconstructed output bytes; 4,804 strong edges, CRC `39abe3c7` | Zero mismatches |
| Custom-threshold JPEG flow | Thresholds 30/90 forwarded through the image bench's plusargs | Zero mismatches |
| Vivado synthesized-netlist simulation | Two consecutive 640x480 frames through Xilinx RAM/logic primitives; 601,032 classes, coordinates, markers and histogram bins | PASS |
| Auxiliary synthesis | APB registers, source checker, CRC and isolated hysteresis stage | PASS, no latches |

The full-resolution corpus contains the five existing synthetic images, black,
white, pixel checkerboard, wrapped ramp, horizontal step, diagonal, five seeded
random images, the supplied JPEG, and six threshold corner cases. The core
regression compares intermediate magnitudes/directions and **weak as well as
strong classes**, so an all-zero output cannot pass unnoticed. Frame statistics
are checked across consecutive frames without reset. Deterministic seeds and
thresholds are saved in each generated manifest.

The direction-domain test forces the comparator's magnitude/sign registers;
it tests the comparator exhaustively over that domain. The separate window
test verifies Sobel arithmetic and pipeline alignment. This is not a formal
proof of the complete pipeline.

The XSim netlist run took approximately 574 seconds. Its result and preserved tool evidence are recorded in
[`doc/evidence/core_audit`](../doc/evidence/core_audit/). Large generated vectors,
executables, full logs and checkpoints remain under ignored `build/`.

## Vivado results and limits

Tool: Vivado 2024.2, target **xc7z010clg400-1**, inferred from repository decisions;
the physical board/part was not independently identified.

| Routed experiment | LUTs including SRLs | Flip-flops | RAMB18 | DSP |
| --- | ---: | ---: | ---: | ---: |
| Bare `edge_pipeline` | 3,396 | 4,307 | 6 | 0 |
| Core with registered timing shell | 3,395 | 4,415 | 6 | 0 |

The shell has 108 boundary flip-flops. Resource numbers can change with the
surrounding design and placement. The register-based histogram dominates LUT/FF
cost; it is not a hidden frame store. All image row storage is now BRAM.

The registered shell routes at a **39.722 ns period (~25.175 MHz)** with
**setup slack +20.567 ns**, **hold slack +0.014 ns**, zero setup/hold failing
endpoints and no latches. It uses 0.200 ns clock uncertainty. Every core path
and every shell-register/core path is timed; only paths between external ports
and the shell's boundary registers are excluded. This establishes internal
timing for this experiment, not board I/O timing or maximum frequency.

The bare OOC experiment also reports a useful limitation: with assumed
0.5..10 ns I/O delays it has **557 boundary hold violations**, worst
**-0.940 ns**, despite positive setup slack. These paths start at unplaced
ports, and Vivado warns that OOC port routing lacks partition pin locations.
Do not treat that experiment as full timing closure, or copy the shell's
external false paths into a board design. Integrate actual synchronous
neighbors and rerun timing with real clock and interface constraints.

DRC reports no errors; it retains `ZPS7-1` (PS7 absent in this standalone Zynq
core). Methodology retains six `SYNTH-6` warnings because BRAM output registers
are not absorbed into the optional BRAM output register. Current timing meets
the registered experiment, but these are acknowledged warnings. The Sobel
center-input unused-port warnings and lint warnings for discarded rounding bits,
unused neighboring direction bits, and filename/module naming are intentional.
No board bitstream, hardware test, timing simulation, or CTL/formal proof is
claimed.
PowerShell itself is unavailable here; the updated `.ps1` wrapper was inspected,
and its underlying prepare/simulate/report commands were exercised directly.

## Requirement coverage remaining

| Problem-statement item | Status after this review |
| --- | --- |
| 3x3 Gaussian, Sobel L1 and quantized direction, NMS, double threshold | Implemented and tested for grayscale input |
| One accepted input per clock | Tested with sustained traffic; no ready/backpressure interface |
| BRAM line buffers | Verified in Vivado, six RAMB18s |
| At least five pixel-exact image comparisons | Exceeded by the full VGA regression |
| Hand-HLS Sobel, sharing and pipelining | Four-stage RTL present and tested; `hls/` schedule/CSE/tree-height documentation remains absent |
| Espresso/BDD direction/NMS deliverable | Direct comparator/mux implementation works; minimization/equivalence artifacts remain absent in `logic/` |
| APB thresholds and histogram | Blocks unit tested; CPU/bus integration remains separate |
| Edge count readable by RV32 | APB exposes an input port only; strong-edge counter, connection and RV32 integration are not implemented |
| CTL synchronization/no-deadlock proofs | Not implemented; empty formal directories are not proof evidence |
| 5x5 Gaussian / K-stage hysteresis | Software options / isolated stage only; not supported by the audited top |
| RGB conversion RTL | Not inside `edge_pipeline`; supply grayscale or add a converter |
| DMA, camera, VGA/HDMI views, research comparison | Deferred as requested |

Do not infer full project completion from the core's functional result. See
[`FPGA_NEXT_STEPS.md`](FPGA_NEXT_STEPS.md) for the interface contract, file list,
reproduction commands and an ordered deployment guide.
