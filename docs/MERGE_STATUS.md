# Merge of the two P7 work trees - review and status (2026-11-15)

Two trees were reviewed: this repository (the "main tree", Vivado-verified, running on a physical original Zybo) and the group-mate's
`p7_main_pipeline/` folder (his tree, written for the Zybo Z7-10, simulated with Icarus/Yosys only). After the merge that folder was removed from
this repository (its author keeps the original); the parts still used are preserved in `study/groupmate/` and `docs/groupmate/`.
Everything below was copied or re-derived, and every number was re-measured here.

## 1. What the review found

| Claim / item in `p7_main_pipeline` | Re-checked how | Result |
|---|---|---|
| Golden model equals the contract | Ran both golden models on all 10 of his images, 7 stages each (70 arrays) | **Bit-identical, 0 differences** (his strong-edge counts also match). One algorithm, two independent implementations. |
| 44 unit tests pass | Re-ran `scripts/run_unit_all.sh` on a scratch copy | **44 PASS, 0 FAIL** |
| Paper RTL (adaptive Otsu) cross-check | Simulated the paper RTL in Icarus on our NMS stream, scored its real class output (`scripts/paper_quality.py`) | **Reproduced** his thresholds, edge counts, PSNR 13.64 / F1 0.685 / 0.829 (his table) - his paper column is real. The reference model his script imports (`paper_hw_model`) is not in his folder, so his script itself cannot run; the RTL-in-the-loop script replaces it. |
| Espresso step | Re-ran with PyEDA's Espresso binding | Reproduced; see section 2 (now wired into the shipped RTL). |
| "HDMI interfacing done" | Read `FINAL_MAIN_PIPELINE_REPORT.md` section 9 + files | His own report says: **written, never synthesised, implemented or run on hardware; no bitstream.** The verbal "all done" overstates it. The HDMI that works on a board is the main tree's. |
| Vivado numbers | He had no Vivado. His report uses Yosys estimates. | Re-measured with Vivado 2024.2 (`scripts/compare_resources.py`, same OOC flow for every design). His own `ooc_synth.tcl` fails in `read_verilog` here; ours does not. |
| CPU / RV32 | grep + report | Not built in either tree. |
| Formal CTL | Read `formal/ctrl_sync.smv`, `run_formal.py`, logs | Real work (8 mutants, 11 properties, honest finding that `AG EX TRUE` is vacuous). It models **his** `ctrl_sync`, not the main tree's, and needs NuSMV (not installed here). |

### What each tree contributes to the merged project
| Area | Take from | Why |
|---|---|---|
| Shipped RTL, HDMI, upload flow, hardware proof, Vivado flow, timing/CDC/DRC, regressions, mutation checks | main tree | built, simulated at netlist level and demonstrated on a board |
| Espresso/BDD block, Boolean-minimisation write-up | group-mate (flow) -> re-implemented in `logic/` and wired into `rtl/sobel.sv` | assignment item; main tree had only an unminimised reference |
| Paper (adaptive Otsu) RTL + quality comparison | group-mate | assignment item; re-measured here |
| 10-image corpus (6 natural + 4 synthetic) | group-mate -> `model/corpus/` | more pixel-exact images, now in the 640x480 RTL regression |
| CTL properties + mutant harness, hand-HLS write-up, progression figures, doc set | group-mate | to be adapted to the shipped modules (open) |
| APB register map | main tree (`rtl/apb_regs.sv`, follows plan Section 7.6, superset of his 11 registers) | richer; his is a subset |

## 2. Changes made so far (all RTL changes are batched; **no new bitstream yet**)
* `logic/espresso_direction.py` -> generates `rtl/dir_decide.sv` (Espresso: 10 canonical terms / 40 literals -> **4 terms / 10 literals**,
  cover == spec on all care rows) and `rtl/sobel.sv` now uses it. Passed: exhaustive direction test (4,169,764 magnitude/sign
  combinations), 7 scoreboard mutants (a new `espresso_dir_block` mutant is caught), quick and **full 640x480 core regression
  including the 10 imported images** (all PASS).
* Board switch: `P7_BOARD=zybo` (default, hardware-tested) or `zybo_z7` (new `fpga/zybo_z7_hdmi.xdc`, **build-only, never run on a Z7**).
  `hdmi_out_en` exists only for the original Zybo. `program_hdmi.tcl` now refuses to run without `P7_BOARD`.
* `rtl/study/paper/` (paper RTL), `tb/study/`, `scripts/paper_quality.py`, `scripts/compare_resources.py`, `scripts/ooc_measure.tcl`.

## 3. Measured so far (Vivado 2024.2, xc7z010clg400-1, OOC, 10 ns clock, place+route)
| core | LUT | FF | RAMB36 | RAMB18 | DSP | WNS @10 ns |
|---|---|---|---|---|---|---|
| main tree `edge_pipeline` | 3379 | 4318 | 0 | 6 | 0 | -3.88 ns (about 72 MHz) |
| group-mate `core_top` (incl. APB regs, aligned view RAMs) | 759 | 1521 | 1 | 7 | 0 | +3.13 ns (about 146 MHz) |

Hierarchical split of ours: `classify_hist` = 2959 LUT / 3710 FF; the Gaussian, Sobel and NMS stages together are about 250 LUT.
The 64-bin histogram (snapshot registers) is the whole difference. Both cores run at the 25.175 MHz pixel clock with large margin.
The two designs differ in features (64 vs 16 histogram bins, CRC, view alignment RAMs), so this is not a like-for-like winner;
see "open items".

Paper quality (RTL-in-the-loop, 6 images; full tables in `build/paper/quality_detail.json`): paper adaptive-Otsu strong+weak
vs project golden map F1 0.833, ours strong+weak 1.000 (by construction), baseline plain Sobel 0.422.

## 4. Outcome (later the same day)
The open items above were completed: tools were installed with the user's permission (NuSMV 2.6.0, xPack riscv-none-elf-gcc 15.2.0-1, PicoRV32),
the RV32 SoC and firmware were built and verified (simulation + hardware), the histogram snapshot copy was removed (2,959 -> smaller),
the Sobel was changed to the shared-subexpression form (8 adders), CTL proofs were run on the shipped RTL, the resource/quality comparison was redone on
frozen sources, both boards were rebuilt, and docs were regenerated. Final numbers and evidence: **docs/FINAL_REPORT.md**; archive: `build/archive_final_zybo/`.
Remaining open items: see STATUS.md.
