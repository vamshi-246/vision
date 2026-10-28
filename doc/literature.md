# Literature survey and evidence ledger

This file begins with the requested transcription of Sections 4.1 and 4.2 of
the binding plan (pages 9-10), reformatted only as Markdown tables.  The
evidence ledger beneath it is the authoritative place to distinguish a claim
read in a source from a result we have independently checked.  Do not turn a
source-reported number into a project result without a separately recorded
reproduction.

## Evidence legend

| Label | Meaning |
| --- | --- |
| **Plan** | Transcribed from the supplied project-plan PDF; not independently checked here. |
| **Full text read** | The complete paper was available and reviewed. Its reported results remain source claims. |
| **Abstract/metadata only** | Only the abstract, record, repository page, or plan summary was read. It must not support detailed technical claims. |
| **Verified locally** | Recomputed, measured, or tested in this repository; command/data are named. |
| **Not verified** | A number or claim observed in a source but not independently reproduced. |

## 4.1 Papers and what we take from each (plan transcription)

| ID | Reference | Key content | What we take / gap left |
| --- | --- | --- | --- |
| L1 | L. Guo, S. Wu, *FPGA Implementation of a Real-Time Edge Detection System Based on an Improved Canny Algorithm*, Applied Sciences 13(2):870, Jan. 2023 | Cyclone IV E; Sobel, `abs(Gx)+abs(Gy)`, shift-based 8-zone direction; Otsu on a 256-bin NMS histogram; division replaced by a log unit (CLZ + barrel shifter); low = high/2. NMS output is cached in external SDRAM. About 1.231 ms for 512x512 at 50 MHz; quality judged visually. | Paper design selected for re-implementation (D6). Gap: a whole-frame cache is needed for Otsu and there is no quantitative quality metric. |
| L2 | G. Sujatha et al., *FPGA Implementation for Image Improved Edge Detection Algorithm Using Xilinx ISE Simulator*, ICITSM Part II, 2025 | Verilog, Virtex-7, FIFO line buffers, Otsu with log unit, SDRAM cache. Reports 889 slice LUTs versus 1,854 (other sections quote 1,908 or 1,324). Simulation uses fixed threshold 27. | Lesson in rigour: internal number inconsistency and adaptive behaviour not demonstrated. Report consistent measured tables and show adaptation working. |
| L3 | S. H. K. Malik, S. Mirzaei, *An Optimized FPGA Based Canny Edge Detection System Using High-Level Synthesis*, IEEE SysCon 2025 | Zybo/Zynq-7000, 100 MHz, Vitis HLS; four-bin direction from `abs(Gx),abs(Gy)` rather than CORDIC; DFS hysteresis; AXI DMA/VDMA IP. Reports 6,267 LUT, 94 BRAM, 5 DSP and 512x512 in 11.49 ms. The CORDIC variant reports 86,840 LUT. Quality is visual only. | Same board family/tool family. Take the four-bin direction idea, IP integration pattern, and resource yardstick. Gap: BRAM-heavy hysteresis and no quality metric. |
| L4 | pm2m1, *fpga-block-adaptive-canny*, GitHub project, 2026 (not peer reviewed) | Artix-7, 640x480 at 100 MHz; 32x32 blocks; 32-bin NMS histogram; top about 20% sets HIGH; LOW = `2*HIGH/5`; one-pass local weak-edge promotion. Core reports 3,834 LUT and 52 BRAM18, with bit-exact Python comparison (zero mismatches over 614,400 pixels); no physical-board run. | Take bit-accurate verification culture and design-space table style. Gap: no F-score, one-pass promotion unquantified, no hardware run. |
| L5 | Z. Zhang, *Towards real-time high-resolution edge detection: a highly efficient FPGA implementation of the Canny algorithm*, M.S. thesis, UIUC, 2024 | HLS + OpenCL, streaming multi-sliding-window; claims 61 us hardware latency for 512x512 at 300 MHz and 3.67x versus the fastest open-source FPGA design. | Throughput-oriented rather than resource-limited; upper-bound reference only. |
| L6 | A. Alhomoud et al., *Model-based Design of a High-Throughput Canny Edge Detection Accelerator on Zynq-7000*, ETASR 14(2):13547-13553, 2024 | Simulink + HDL Coder to VHDL; real-time claim; abstract gives no figures. | Alternative design flow; context only. |
| L7 | A. H. Jalilvand, P. H. Shariat Panahi, M. H. Najafi, *A Low-Latency ASIC Architecture for Real-Time Line Segment Detection*, arXiv:2608.06439, 2026 | Gaussian/Sobel/magnitude/8-class angle/NMS/double threshold at one pixel per clock. Three-row register line buffer with circular pointer, one write/cycle; multiplierless MCM filters; latency `5W+27` cycles. FreePDK45 synthesis only. | Deterministic-latency expression, circular-pointer window, multiplierless filters. Use BRAM rather than registers for the FPGA. |
| L8 | Y. Shimizu, *SweepLSD: a one-pass, O(width)-memory line segment detector with an integer-only streaming core and a real-time FPGA realization*, arXiv:2608.22086, Aug. 2026 | One row-stream pass, memory grows with width rather than area, integer-only; claims 1080p30 without a frame buffer/external memory and hardware bit-exact with software. | Strong recent support for O(width)-memory and bit-exact HW/SW. Plan notes that only the abstract was read. |
| L9 | V. B. Devarakonda, K. Babulu, M. Hema, *Power-Efficient Gaussian Filter Architecture Utilizing Approximate 4:2 Compressors for Edge Detection*, IJCESEN 11(4):8574-8584, Nov. 2025 | Two approximate 4:2 and one 3:2 compressor in a Gaussian filter; reports 1.10-1.31 W, about 2.3 ns, and 32.6-36.1 dB PSNR versus prior designs; no area figure. | Gap: power/delay/PSNR but no LUT/FF. N3 asks whether such ideas help carry-chain FPGAs. |
| L10 | J. de Oliveira, L. Soares, E. Costa, S. Bampi, *Exploiting approximate adder circuits for power-efficient Gaussian and gradient filters for Canny*, IEEE LASCAS 2016 | Approximate adders in 5x5 Gaussian and 3x3 gradient filters; plan states full text was unavailable. | Older N3 seed; read before citing its results. |
| L11 | *Efficient Compression-Based Line Buffer Design for Image/Video Processing Circuits*, IEEE document 8746699 | Compression used to reduce line-buffer memory. Not read. | Candidate for the line-buffer direction, but 640x480 already needs few BRAMs; related work only. |
| L12 | Classical anchors cited by L3: Canny (1986); Gentsos et al. (ECCTD 2010, 0.66 ms at 200 MHz); Xu et al., distributed Canny (IEEE TIP 2014, Virtex-5, 250 MHz, 0.15 ms) | Block-adaptive thresholds and high-speed Canny references. | Historic baselines; Xu et al. is the origin of block-adaptive thresholding in this plan. |
| L13 | Digilent Zybo Z7 Reference Manual; AMD UG908 / UG936 | Board resources, clocks, Pmods, ILA insertion/triggers/cross-trigger. | Implementation facts for the board/debug section; not a research-paper result. |

## 4.2 Gap analysis (plan transcription)

| Gap | Evidence in surveyed work | Our response |
| --- | --- | --- |
| G1: Adaptive threshold costs a frame cache or block logic | L1 and L2 cache the NMS image in SDRAM for Otsu; L4 and Xu et al. use per-block histograms. | N1: reuse the previous frame's histogram (video has temporal redundancy) without a cache; study scene cuts, rapid illumination changes, and a guard. |
| G2: Hysteresis is memory-hungry or unquantified | L3 uses DFS hysteresis with large BRAM; L4 uses one-pass promotion without a quality number. | N2: K-stage geodesic hysteresis; plot F-score versus K versus resource and prove a property. |
| G3: Approximate-arithmetic papers stop at ASIC-style metrics | L9 reports power/delay/PSNR; L10 is older and ASIC-oriented. | N3: measure LUT/FF/power/fmax on 7-series as well as quality. A negative result is valid. |
| G4: Evaluation is qualitative or inconsistent | L1 and L3 are visual only; L2 has inconsistent figures. | Bit-exact RTL-vs-golden, F-score and PSNR against float and Otsu references; regenerate every table by script. |
| G5: Little formal assurance on control/sync or hardware | Surveyed work shows simulation/screenshots; L4 and L8 show bit-exactness only. | CTL/SVA properties for frame/line/FIFO/K-stage control, plus on-board CRC self-check (N5). |

## Corrections and scope notes discovered during review

1. **L3 bibliographic correction.** The plan's provisional venue wording is
   corrected: the record is a 2025 IEEE International Systems Conference
   (SysCon) paper, pages 1-4, DOI
   [10.1109/SYSCON64521.2025.11014645](https://doi.org/10.1109/SYSCON64521.2025.11014645),
   not an IEEE journal citation.
2. **G1 novelty needs a narrower claim.** A 2022 streaming-video FPGA paper
   found in the P1 search also derives a threshold from a previous-frame
   histogram during blanking. Therefore N1 must be presented as a quantified,
   bit-exact FPGA trade-off study (64-bin percentile/IIR/scene guard against
   oracle and previous-frame alternatives), not as the generic idea of using a
   previous-frame histogram.
3. **No source result is a project result.** The project has no synthesis,
   implementation, power, board, or paper-algorithm-reproduction result yet.

## Full-paper evidence entries

### L1 - Guo and Wu (2023)

**Status:** Full text read. Open-access version of record:
[Applied Sciences 13(2), 870](https://doi.org/10.3390/app13020870).

**What was taken.** The paper supplies the D6 reproduction target: Sobel L1
magnitude, approximate direction, NMS, 256-bin Otsu threshold selection, and
a logarithmic replacement for division. Its external-memory NMS cache is the
comparison point for RQ1's O(width)-storage argument. Its lack of a numerical
edge-quality metric feeds G4/RQ1/RQ2 evaluation requirements.

**Claims seen in full text, not verified locally.** Cyclone IV E target;
512x512 image; 50 MHz; 1.231 ms detection time; 256-bin histogram; 32-bit
logarithmic unit; and the claim of least logical resources among compared
implementations. These are source-reported, not project measurements.

**Verified locally.** The model test suite verifies only our Appendix-A
baseline semantics (`make golden`: 7 tests passed). It does **not** reproduce
Guo/Wu's Otsu/log unit, cache behaviour, direction quantisation, resource
table, timing, or image quality. A basic single-lane arithmetic check gives
`512*512 / 50 MHz = 5.243 ms`; this does not invalidate the paper's 1.231 ms
claim, but it means a future D6 reproduction must document its effective
parallelism/latency definition before comparing times.

**Feeds:** D6 primarily; RQ1 (storage/latency comparison), RQ2 (threshold
comparison), RQ4 (approximation quality), and G1/G4.

**Next evidence needed.** A separately named Guo/Wu variant in the Python
model, a reproduced threshold histogram on fixed images, and an analytical
SDRAM/BRAM/latency comparison. Do not claim reproduction until those exist.

### L3 - Malik and Mirzaei (2025)

**Status:** Full paper reviewed from the accessible copy; bibliographic record
verified at [IEEE SysCon DOI](https://doi.org/10.1109/SYSCON64521.2025.11014645).

**What was taken.** The four-bin comparison direction scheme supports D4/RQ5
as a CORDIC-free baseline. The Zynq/HLS + AXI DMA/VDMA structure informs D8/D11
integration planning. DFS hysteresis is a comparison baseline for D9/RQ3 and
supports the G2 motivation for bounded K-stage propagation.

**Claims seen in paper, not verified locally.** The reported core results are
100 MHz, 94 BRAM, 5 DSP, 3,956 FF, 6,267 LUT, and 11.49 ms for 512x512. The
paper's table reports a CORDIC alternative at 24 DSP and 86,840 LUT. Treat all
of these as the authors' measurements, not ours.

**Verified locally.** No Malik/Mirzaei resource, timing, DMA/VDMA, or quality
result has been reproduced. The only locally checked related behaviour is the
Appendix-A Sobel/direction RTL unit test (`tb_sobel`), which tests two axial
step windows and is not the paper's algorithm or benchmark.

**Feeds:** D4, D8, D9, D11; RQ3, RQ5, RQ6; and G2/G4.

**Next evidence needed.** Confirm the accessible-paper extraction against the
publisher PDF, build a comparison row with like-for-like resource units, and
avoid comparing post-route project results to HLS estimates without labelling
the distinction.

## Reading queue and per-item evidence contract

Each entry below must be upgraded only after the complete primary source has
been read. Until then the plan table is a lead, not evidence.

| ID | Current access status | What to take / deliverable or RQ | Number status |
| --- | --- | --- | --- |
| L2 | Not read | D6/G4: audit the conflicting resource figures and fixed-threshold experiment. | All plan figures are **Plan / not verified**. |
| L4 | Repository page/readme only; not peer reviewed | D7/G4: bit-exact harness style; RQ2/RQ3: block threshold and causal-promotion comparator. | 3,834 LUT, 52 BRAM18 and zero mismatches are **repository claims / not verified**. |
| L5 | Not read | RQ1/RQ6 throughput/latency upper bound. | 61 us, 300 MHz, and 3.67x are **Plan / not verified**. |
| L6 | Abstract/metadata only | Context for a model-based implementation route; no planned deliverable depends on it. | No numerical claim accepted. |
| L7 | Not read | D3/RQ1/RQ6: circular pointer, one-pixel-per-clock line-window latency accounting. | `5W+27` is **Plan / not verified**. |
| L8 | Abstract only | D1/D3/D7/G5: O(width) memory and HW/SW bit-exact methodology. | 1080p30 and implementation claims are **abstract claims / not verified**. |
| L9 | Not read | RQ4/G3: approximate compressor variant and the required FPGA-versus-ASIC comparison. | Power/delay/PSNR are **Plan / not verified**. |
| L10 | Full text unavailable in this session | RQ4/G3 historical approximate-adder baseline. | No result may be cited until primary text is obtained. |
| L11 | Not read | RQ1 only; establish whether compression matters once 640-pixel row buffers are costed. | No accepted number. |
| L12 | Citation leads only | Related-work context for thresholds and high-speed Canny. | All timing/frequency numbers are **Plan / not verified**. |
| L13 | Official manuals, not a paper | D8/D11 implementation/debug facts. | Pin/resource facts are checked against the board XDC/manual separately, not treated as research results. |

## Literature-to-project matrix

| Project item | Evidence source(s) | Present status |
| --- | --- | --- |
| D1/D7, bit-exact test culture | L4, L8; Appendix-A contract | Local baseline tests exist; no system-level proof yet. |
| D3/RQ1, O(width) storage | L1 cache contrast, L7/L8/L11 | Two-line RTL buffer unit-tested; storage comparison table pending. |
| D4/RQ5, direction/NMS | L1/L3 | Appendix-A four-sector RTL exists; paper variants and minimisation study pending. |
| D6, paper reproduction | L1 | Literature specification complete enough to begin; implementation/reproduction pending. |
| RQ2/G1, threshold adaptation | L1/L2/L4 plus prior-art correction above | No threshold RTL/model experiment yet. |
| RQ3/G2, hysteresis | L3/L4 | Baseline model has optional K-step operation; quality/resource curve pending. |
| RQ4/G3, approximate arithmetic | L1/L9/L10 | No FPGA-aware variant measured. |
| G4/G5, reproducibility/formal assurance | L1-L4/L8 | Unit tests started; formal and board CRC pending. |

## Update protocol

For every new full-paper read, append a subsection with exactly these fields:

1. **Status and permanent citation** - primary-source URL/DOI and whether the
   entire paper or only abstract/metadata was obtained.
2. **What was taken** - a concise algorithm/design/verification lesson.
3. **Feeds** - exact D-number(s), RQ-number(s), and gap(s).
4. **Claims seen in source, not verified locally** - every resource, timing,
   accuracy, and quality number, retaining units and conditions.
5. **Verified locally** - command, data set, commit, and resulting number; use
   `none` when there is no reproduction.
6. **Next evidence needed** - the smallest artefact that would make the claim
   useful in this project.
