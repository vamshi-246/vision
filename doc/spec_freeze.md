# P0 specification freeze

> Historical P0 snapshot. The 2026-11-13 review uses the supplied problem
> statement as its scope; change note 002 corrects zero-threshold semantics and
> streaming corner cases. Vivado and Verilator are now available and were run.
> See [current core review](../docs/CORE_RTL_REVIEW.md) for measured results.

**Date:** 2026-10-28  
**Gate:** PASS WITH TOOL LIMITATIONS

The 40-page `P7_Master_Project_Plan.pdf` is binding. Its Appendix A defines
the sole golden/RTL arithmetic contract. Decisions D-001 through D-005 freeze
the Z7-10, Pmod VGA wiring, CPU boundary, fixed-point defaults, and
line-buffer-only policy. The precise migration is recorded in change note 001.

The required P0 development environment is only partially installed. Python,
OpenCV/SciPy, pytest, Make, Git, and Icarus work; Vivado and formal/synthesis
tools do not. P1/P2 software work proceeds. Any statement requiring the absent
tools remains `NOT RUN` and no resource, timing, bitstream, or proof result
will be claimed.

The implementation gate will re-open this file only for an explicit semantic
change note or a new board fact.
