# Design decisions

## D-001 — Binding source and legacy model

`P7_Master_Project_Plan.pdf` is the binding design source. The supplied
`p7 golden.py` is retained unchanged as legacy input evidence, but it cannot be
the RTL contract because it has replicate borders, a 106/256 direction
constant, a different NMS tie convention, and a one-pass hysteresis option.
`model/golden.py` will implement Appendix A exactly. See change note 001.

## D-002 — Board and display default

The target is the smaller Zybo Z7-10 (`xc7z010clg400-1`). The primary output is
the Digilent Pmod VGA Rev. C, with its J1 header on Zybo JC and J2 header on
Zybo JD. J1 carries R[3:0] and B[3:0]; J2 carries G[3:0], HS and VS. This is an
implementation default only: board/monitor bring-up remains NOT RUN until the
hardware is available. HDMI/rgb2dvi remains a fallback, not a claimed build.

## D-003 — Control CPU boundary

The APB register block is CPU-independent. ARM PS behind AXI-to-APB or
JTAG-to-AXI is the default; a soft RV32 is deferred and costed separately only
if the course requires it.

## D-004 — Fixed-point baseline

Default Gaussian is 3×3 with `(sum + 8) >> 4`; Sobel magnitude is 11-bit
`abs(Gx)+abs(Gy)`; direction uses `32*ay <= 13*ax`, then
`32*ax <= 13*ay`; NMS accepts a nonzero magnitude iff it is `>=` the earlier
neighbour and `>` the later neighbour. The baseline ends at double threshold,
with K=0. Any semantic adjustment requires a numbered change note.

## D-005 — Memory and alignment policy

No on-chip full-frame cache is allowed in the baseline. Valid regions contract
through the 3×3 stages and V-blank carries zero flush data. Views use separate
sync phases by default; alignment RAM is a measured fallback, not silently
included.

