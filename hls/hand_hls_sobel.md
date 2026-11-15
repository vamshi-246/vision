# Hand-HLS of the Sobel window + magnitude (`rtl/sobel.sv`)

Assignment item: *"Sobel window + magnitude from your own hand HLS: CSE between Gx/Gy, tree-height reduction, pipelined schedule with
initiation interval 1."*  The derivation (a-b) was worked out first by the group-mate (original write-up preserved in `docs/groupmate/hand_hls_sobel.md`) and is
adopted here because it saves two adders over the column-sum form that the first version of `sobel.sv` used; section d maps it onto the
shipped 4-stage schedule. Every statement below is checked by `tb/unit/tb_sobel.sv`, `tb_arithmetic_stress.sv` (100,000 random windows),
`tb_direction_exhaustive.sv` and the full-frame regressions against `model/golden.py`.

Window (blurred 8-bit pixels, row 0 = top, column 0 = oldest column):

```
        c0    c1    c2
  r0   p00   p01   p02
  r1   p10   p11   p12
  r2   p20   p21   p22
```
`x<<1` is wiring only.

## a. Gx and Gy as sums of shifted taps
```
Gx =  p02 + 2*p12 + p22  -  p00 - 2*p10 - p20        (right column minus left column)
Gy =  p20 + 2*p21 + p22  -  p00 - 2*p01 - p02        (bottom row minus top row)
mag = |Gx| + |Gy|                                      (L1 only, 0..2040)
```
p11 has coefficient 0 in both. Only the four corners have a non-zero coefficient in both sums, so only corner pairs can be shared.

## b. Common-subexpression elimination
Pairing the corners by their `(Gx, Gy)` coefficients gives exactly two shareable differences:

| term | definition | used as |
|---|---|---|
| E1 | `p22 - p00` | +1 in Gx and +1 in Gy |
| E2 | `p02 - p20` | +1 in Gx and **-1** in Gy |
| F | `p12 - p10` | Gx only (weight 2) |
| G | `p21 - p01` | Gy only (weight 2) |

```
Gx = E1 + E2 + 2F          Gy = E1 - E2 + 2G
```
(Expanding gives back a. exactly.) Two-input adder/subtractor count, shifts free:

| form | adders |
|---|---|
| naive, 6 operands per gradient | 10 |
| column/row sums (`R-L`, `B-T`), the first version of `sobel.sv` | 10 - no sharing between Gx and Gy |
| **CSE (this design)**: E1, E2, F, G (4) + P=E1+E2, Q=E1-E2 (2) + `P+2F`, `Q+2G` (2) | **8** |

## c. Tree-height reduction
With E1/E2/F/G ready, each gradient is a depth-2 tree (`(E1+E2)+2F`) instead of a chain of five adders (depth 5 for a left-to-right
sum of six operands). Magnitude adds one more level after the absolute values.

## d. Schedule, initiation interval 1 (one new window per clock, four registers deep)
| stage | work (all in one clock) | registers |
|---|---|---|
| 0 | `E1=p22-p00`, `E2=p02-p20`, `F=p12-p10`, `G=p21-p01` (4 parallel subtractors, 10-bit signed) | e1, e2, f, g |
| 1 | `P=E1+E2`, `Q=E1-E2`, `Gx=P+2F`, `Gy=Q+2G` (11-bit signed; max |G| = 1020) | gx, gy |
| 2 | `|Gx|`, `|Gy|`, sign bits | ax, ay, sx, sy |
| 3 | `mag = ax + ay`; the two direction comparators `32*ay <= 13*ax`, `32*ax <= 13*ay` (shift-add) and the **Espresso-minimised** sector decision (`rtl/dir_decide.sv`, see `logic/`) | magnitude, direction |

Latency from window to result: 4 clocks, a constant that `rtl/top.sv` (`sm_sof0..3`) and `rtl/video/edge_video.sv` rely on. The
comparators multiply by 13 as `(x<<3)+(x<<2)+x` and by 32 as `x<<5`: no multipliers, no DSP blocks (Vivado reports 0 DSP).
