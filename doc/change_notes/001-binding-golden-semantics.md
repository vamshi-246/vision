# 001 — Bind the golden contract to Appendix A

**Date:** 2026-10-28  
**Status:** approved by the binding plan  
**Affected requirements:** D1, D2, D4, D7, RQ3, RQ5, RQ6

## Reason

The supplied root-level `p7 golden.py` predates the binding 40-page plan and
has different arithmetic semantics. Keeping it as the source of truth would
make RTL satisfy a different project.

## Exact semantic contract

- Out-of-image taps read zero; Gaussian, Sobel, and NMS valid regions contract
  by one pixel each for the 3×3 baseline. The final output has a three-pixel
  zero border.
- Gaussian 3×3 rounds `(sum + 8) >> 4`.
- Direction uses the 13/32 comparisons of Appendix A and codes `00, 01, 10,
  11` exactly as defined there.
- NMS accepts `m > 0 && m >= earlier && m > later`.
- Baseline class output is double threshold only. K-stage hysteresis is a
  parameterised extension, with K=0 as baseline.
- Edge bytes are `00` or `FF`; frame CRC is `zlib.crc32` over active pixels.

## Migration action

The legacy script remains unchanged. `model/golden.py`, all exported vectors,
all RTL block testbenches, and the report will use this note's contract.
Regression tests will explicitly distinguish replicate-padding legacy outputs
from Appendix-A outputs at borders.

