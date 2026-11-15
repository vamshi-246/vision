# Non-maximum suppression -- exact rule (implemented in `model/golden.py::nms` and `rtl/dirnms.sv`)

Input: magnitude `m = |Gx|+|Gy|` (11 bit) and sector `d in {0,1,2,3}` from the direction quantiser.

| sector d | gradient direction | neighbour `a` (first) | neighbour `b` (second) |
|---|---|---|---|
| 0 | `|Gy|*32 <= |Gx|*13` (~horizontal) | W  (x-1, y)   | E  (x+1, y)   |
| 1 | diagonal, sign(Gx)==sign(Gy) (`\` axis) | NW (x-1, y-1) | SE (x+1, y+1) |
| 2 | `|Gx|*32 <= |Gy|*13` (~vertical) | N  (x, y-1)   | S  (x, y+1)   |
| 3 | diagonal, signs differ (`/` axis) | NE (x+1, y-1) | SW (x-1, y+1) |

(y grows downward; sector 0 is tested first, so `Gx=Gy=0` is sector 0.)

**Asymmetric tie rule:** the centre pixel is kept iff

    m >= a   AND   m > b

otherwise the output is 0. Ties with the `a` neighbour keep the pixel, ties with the `b` neighbour suppress it, so on a
plateau of equal magnitude exactly one pixel (the one whose `b` neighbour is smaller) survives instead of the whole
plateau or none of it. A pixel with `m = 0` is always suppressed (`m > b` fails because `b >= 0`).

Border rule (shrinking valid region): Gaussian valid on `[1,W-1) x [1,H-1)`, Sobel/direction on margin 2, NMS and
classification on margin 3; every stage output is a full W x H array with 0 outside its valid region.
The RTL reproduces this with a per-stage valid flag derived from the window-centre tag (`tag_center.sv`).

Classification: `cls = 2 if nms != 0 and nms >= thr_hi; 1 if nms != 0 and nms >= thr_lo; else 0`.
