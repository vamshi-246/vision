# Group-mate's tree (preserved subset)

Source: the group-mate's `p7_main_pipeline/` folder (RTL written for the Zybo Z7-10; simulated with Icarus and estimated with Yosys; never built
in Vivado or run on a board by its author - see `docs/groupmate/FINAL_MAIN_PIPELINE_REPORT.md`, section 1 and 9).
Kept here: the RTL (`rtl/`), which `scripts/compare_resources.py` synthesises for the resource comparison (`GROUP-MATE core_top`), and his Z7 pin file.
His documentation, figures and Yosys estimates are in `docs/groupmate/`. His Espresso flow, hand-HLS derivation, formal model/mutants, paper study and
10-image corpus were merged into the main tree (`logic/`, `hls/`, `formal/abstract/`, `rtl/study/`, `model/corpus/`).
