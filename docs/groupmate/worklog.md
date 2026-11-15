# Worklog -- P7 main pipeline (timestamps are real `date` output taken when each entry was written)

## Conflicts / deviations from the brief (flagged per the "master plan wins" rule)
- The master-plan PDF (doc/P7_Master_Project_Plan.pdf) was NOT in the zip I received, so I could not check the brief against it.
  I used the problem-statement image (P7 box) that was attached to the chat instead; the brief and that image agree on every item.
- The brief says golden.py and the test images are attached, and that FINAL_PAPER_REIMPLEMENTATION_REPORT.md is in the zip. None of
  the three is in the zip I received (it holds only the Otsu-stage files of the paper re-implementation). Decisions: golden.py was
  written fresh to the brief's rules (model/golden.py); the test images are scikit-image bundled images + 4 synthetic patterns; the
  paper-column numbers are measured here from the untouched paper RTL/model (see doc/FINAL_MAIN_PIPELINE_REPORT.md).
- Tool substitutions (nothing else was available): nuXmv could not be obtained (nuxmv.fbk.eu returns 403 from this sandbox).
  NuSMV-A (an extension of NuSMV 2.6.0 from github.com/hklarner/NuSMV-a) was built from source and used for the CTL checks.
  Vivado is not installable here: synthesis numbers come from Yosys (labelled as such), Vivado scripts are provided to run yourself.

## Log
- 2026-11-15 11:30:10 IST  Environment: iverilog 12.0, yosys 0.33, pyeda (pip), NuSMV-A (built from source, see above). espresso binary/pip not available.
- 2026-11-15 11:30:10 IST  Wrote model/golden.py (all stages) + scripts/selfcheck_golden.py (vector model == independent per-pixel loop model on 6 random images: PASS).
- 2026-11-15 11:30:10 IST  Wrote scripts/gen_main_vectors.py; generated 6 real + 4 synthetic images (640x480 and 64x48), stage .npz files, packed .bin vectors.
- 2026-11-15 11:30:10 IST  Wrote scripts/make_progression.py; 10 composite PNGs in doc/figures/progression/.
- 2026-11-15 11:32:21 IST  NOTE: the four entries above share one timestamp because I logged them in a single batch after finishing step 1; entries from here on are written as the work happens.
- 2026-11-15 11:32:21 IST  Architecture decision: core processes the FULL raster (WT x HT = 800x525 incl. blanking, active 640x480) continuously, no stalls; every stage carries an (x,y) tag; valid region shrinks by 1 px/side per 3x3 stage (margins 1,2,3). Blanking supplies the flush lines, so no flush logic is needed.
- 2026-11-15 11:33:10 IST  ctrl_sync + tag_center + linebuf written. tb_ctrl_sync PASS (20292 cycles, 0 mismatches), tb_linebuf PASS (camera, 112329 tap checks); mutant of linebuf (lb2 write column) correctly FAILS tb_linebuf.
- 2026-11-15 11:34:46 IST  doc/hand_hls_sobel.md written (a-d: shift-add expressions, shared terms E1/E2 found by coefficient-pairing, trees 5->3 levels, 10->8 adders, II=1 schedule table) BEFORE rtl/sobel.sv.
- 2026-11-15 11:38:27 IST  Step 3-6 done: rtl gauss/sobel/dirnms/classify/rgb2gray + 4 more tbs. Espresso: pyeda binding (apt/pip espresso-logic unavailable): 13 terms/52 lits -> 6 terms/19 lits (without don't-cares: 7/23). scripts/run_unit_all.sh -> 44 PASS 0 FAIL (sim/reports/unit_all.log).
- 2026-11-15 11:54:50 IST  core_top + apb_regs + delay_ram + tb_top written. First tb_top run on camera: 6.3M checks, only 3 startup-X mismatches (uninitialised pipeline regs); added translate_off zero-init blocks. Started scripts/run_top_all.sh (10 images x 3 frames, 640x480) in background.
- 2026-11-15 11:59:15 IST  Step 9 formal: 8 mutants run; all caught (matrix in sim/reports/formal_results.log). Finding: CTL 'AG EX TRUE' (P1) stayed TRUE on the deadlock mutant M5 (NuSMV EX ignores deadlock states), i.e. P1 is vacuous as a deadlock check; replaced by check_fsm (P11) which catches M5. P1 kept but flagged.
- 2026-11-15 12:06:51 IST  tb_top: 1 startup-only mismatch (X dir at tag (797,521), t=190ns, tag of non-existent pre-frame) traced via signal probes to un-primed pipeline before first frame; tap checks now start K cycles after origin (frames 0-tail,1,2 fully checked). Re-running all 10 images.
- 2026-11-15 12:13:26 IST  tb_demo found real bug: TPG address was 17 bit (max 131071) but the 2-image ROM has 153600 entries -> image 1 corrupted from source row ~170; widened to 18 bit. 10-image tb_top: 6/6 natural images PASS so far (0 mismatches over 6,288,630 checks each) after the check-window fix.
- 2026-11-15 12:27:03 IST  Step 10: demo_core/zybo_top/XDC/Vivado scripts written. tb_demo (full demo data path vs golden, 2 images, thr switch mid-frame, 4 views, 5 frames) PASS after fixing (a) TPG address width (b) tb threshold sampling instant (tb bug: sampled before the core latched). Re-running tb_demo on final RTL + a mutant (SRC_LAT=1: display alignment off by 1 clk) to show the tb is not vacuous. 10-image tb_top: 10 PASS 0 FAIL. Paper RTL (untouched except bins->hist_bins rename, Icarus keyword) simulated at 640x480 on 2 images: matches Python model exactly.
- 2026-11-15 12:31:39 IST  Step 12: FINAL_MAIN_PIPELINE_REPORT.md generated from logs (scripts/make_report.py). tb_demo final PASS (8,244,004 checks, 0 mismatches), mutant SRC_LAT=1 FAILS (1.5M tag mismatches). Yosys resource table for core/baseline/paper-system/demo. No Vivado: no WNS/WHS/fmax/bitstream (stated). Packaging.
