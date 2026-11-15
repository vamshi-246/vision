# 002 — Corrections from the 2026-11-13 core audit

The supplied problem statement is the scope for this audit. The existing
3x3, 13/32 direction, asymmetric-NMS, K=0 arithmetic remains the baseline.

One corner case in the older arithmetic contract is corrected: a zero NMS
value is always class 0, including when both thresholds are zero. A suppressed
pixel or invalid border must not become an edge because the threshold is zero.
Both `model/golden.py` and `rtl/classify_hist.sv` implement this rule. Nonzero
values still use inclusive low/high threshold comparisons.

Histogram clear now affects statistics only; it does not discard a valid class
sample. Clear has priority over histogram increment and snapshot on the same
clock. Therefore a mid-frame clear intentionally produces a partial-frame
histogram; use it between frames for full-frame statistics.

Line memories now use alternating synchronous read-first BRAM banks. Each
`linebuf` adds one clock compared with the earlier asynchronous-read version;
the complete core adds three clocks. Valid/data/markers remain aligned.
The first output latency for uninterrupted input is `6*IMG_W + 17` clocks,
measured from the first input sample's acceptance edge to the first output's
publication edge. SOF addresses the new frame's first pixel at (0,0).

APB status events win over simultaneous W1C/CTRL clears. The source checker now
flags missing SOF as well as unexpected SOF and incorrect EOL.

`golden/p7_golden.py` now forwards to the active model. The original root-level
`p7 golden.py` is retained as legacy evidence and is not an interchangeable
reference.

Verification evidence and integration limits are in
[`docs/CORE_RTL_REVIEW.md`](../../docs/CORE_RTL_REVIEW.md) and
[`docs/FPGA_NEXT_STEPS.md`](../../docs/FPGA_NEXT_STEPS.md).
