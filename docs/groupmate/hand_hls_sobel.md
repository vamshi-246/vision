# Hand-HLS of the Sobel window + magnitude (written BEFORE `rtl/sobel.sv`)

Goal (problem statement): *Sobel window + magnitude from your own hand HLS: CSE between Gx/Gy,
tree-height reduction, pipelined schedule with initiation interval 1.*

Notation: the 3x3 window of blurred pixels, row 0 = top, column 0 = left (oldest column):

```
        c0    c1    c2
  r0   p00   p01   p02
  r1   p10   p11   p12
  r2   p20   p21   p22
```
`x<<1` means "x times 2" (pure wiring in hardware, zero logic). All pixels are 8-bit unsigned.

## a. Gx and Gy as sums of shifted taps

```
Gx =  p02 + (p12<<1) + p22  -  p00 - (p10<<1) - p20          (right column minus left column)
Gy =  p20 + (p21<<1) + p22  -  p00 - (p01<<1) - p02          (bottom row minus top row)
```
p11 has coefficient 0 in both. Magnitude (L1 only): `mag = |Gx| + |Gy|`, range 0..2040.

Coefficient table (tap : coefficient in Gx, in Gy):

| tap | Gx | Gy | | tap | Gx | Gy |
|---|---|---|---|---|---|---|
| p00 | -1 | -1 | | p20 | -1 | +1 |
| p01 |  0 | -2 | | p21 |  0 | +2 |
| p02 | +1 | -1 | | p22 | +1 | +1 |
| p10 | -2 |  0 | | p12 | +2 |  0 |

## b. Finding the shared partial sums (by hand) and applying CSE

A sub-expression can be shared only if it appears in BOTH Gx and Gy with the same (or exactly
negated) coefficients. Only taps with a non-zero coefficient in both can take part: the four
corners p00, p02, p20, p22. The edge-centre taps p01, p21 (Gy only) and p10, p12 (Gx only) can never be shared.

Pair the corners and compare their coefficient pairs `(Gx, Gy)`:

| pair | coefficients | result |
|---|---|---|
| p22 , p00 | p22: (+1,+1), p00: (-1,-1) | `p22 - p00` appears as **+1 in Gx and +1 in Gy** -> shared term **E1** |
| p02 , p20 | p02: (+1,-1), p20: (-1,+1) | `p02 - p20` appears as **+1 in Gx and -1 in Gy** -> shared term **E2** (used with opposite sign) |
| p22 , p02 | (+1,+1) vs (+1,-1) | not proportional -> nothing shared |
| p22 , p20 | (+1,+1) vs (-1,+1) | not proportional |
| p00 , p02 | (-1,-1) vs (+1,-1) | not proportional |
| p00 , p20 | (-1,-1) vs (-1,+1) | not proportional |

The remaining, unshared, pieces are the two edge-centre differences:
`F = p12 - p10` (Gx only, weight 2) and `G = p21 - p01` (Gy only, weight 2).

```
E1 = p22 - p00        (shared by Gx and Gy)
E2 = p02 - p20        (shared by Gx, and by Gy with a minus sign)
F  = p12 - p10
G  = p21 - p01

Gx = E1 + E2 + (F<<1)
Gy = E1 - E2 + (G<<1)
```
Check by expansion: `E1+E2+2F = p22-p00+p02-p20+2p12-2p10 = Gx` and
`E1-E2+2G = p22-p00-p02+p20+2p21-2p01 = Gy`  (both verified symbolically; also verified numerically
by `rtl/sobel.sv` against the golden model).

Further common term of the two sums: `P = E1 + E2` (-> Gx) and `Q = E1 - E2` (-> Gy) are computed once each.

Alternatives considered and rejected (adder counts, two-input add/sub):
* Column/row sums `R=p02+2p12+p22, L=..., B=..., T=...`: Gx=R-L, Gy=B-T. They share the corner taps but no
  common partial sum: 4 column/row sums x 2 adders + 2 subtractions = 10 adders, no saving.
* Sum/difference transform `Gx = D1 + D2, Gy = D1 - D2` with `D1 = (p12+p21+p22)-(p00+p01+p10)`,
  `D2 = (p01+p02+p12)-(p10+p20+p21)`: D1, D2 are fully shared but each costs 5 adders -> 12 total. Worse.

Adder count (two-input adders/subtractors, shifts are free):

| form | Gx | Gy | total |
|---|---|---|---|
| naive (6 operands each) | 5 | 5 | **10** |
| after CSE | E1,E2,F,G (4, shared/own) + P,Q (2) + final (2) | | **8** |

## c. Tree heights, before and after

**Naive, as written (left-to-right chain)** -- height 5 adder levels per output:

```
 Gx = ((((( p02 + 2*p12 ) + p22 ) - p00 ) - 2*p10 ) - p20 )

          -
         / \
        -   p20            level 5
       / \
      -   2*p10            level 4
     / \
    -   p00                level 3
   / \
  +   p22                  level 2
 / \
p02  2*p12                 level 1
```

**Tree-height reduction alone** (balance the 6 operands) -- height ceil(log2 6) = 3:

```
 Gx = ( (p02 + p22) + 2*p12 )  -  ( (p00 + p20) + 2*p10 )

                 -                  level 3
              /     \
            +         +             level 2
           / \       / \
          +  2*p12  +  2*p10        level 1
         / \       / \
       p02 p22   p00 p20
```
(Same for Gy.) Naive total after balancing: 5 + 5 = 10 adders, height 3.

**CSE + tree-height reduction (the implemented datapath)** -- 8 adders, height 3, with the shared
level-1 nodes E1, E2 feeding both outputs:

```
  level 1 : E1 = p22-p00    E2 = p02-p20    F = p12-p10    G = p21-p01
  level 2 : P  = E1+E2      Q  = E1-E2      (2F, 2G are wires)
  level 3 : Gx = P + 2F     Gy = Q + 2G

     p22  p00     p02  p20            p12 p10       p21 p01
       \  /         \  /                \  /          \  /
       [E1]         [E2]                [F]           [G]        level 1
        |  \       /  |                  |             |
        |   \     /   |                  |             |
        |   [P] [Q]   |                  |             |         level 2
        |    |   |    |                  |             |
        |    +---+----+------[+]<--2F----+             |
        |        |           Gx                        |         level 3
        |        +----------[+]<-------2G---------------+
        |                    Gy
        +--(E1 and E2 each fan out to both P and Q: the shared sub-expressions)
```
The same, drawn as two trees that share their leaves:

```
 Gx:        +                        Gy:        +
          /   \                               /   \
        P       2F                          Q       2G
       / \       |                         / \       |
     E1   E2     F                       E1   E2     G
    (shared)(shared)                    (shared)(shared)
```
Bit growth: p: 8 bit unsigned; E1,E2,F,G: signed 9 bit (|v|<=255); P,Q,2F,2G: signed 10 bit (|v|<=510);
Gx,Gy: signed 11 bit (|v|<=1020, range -1024..1023). `ax=|Gx|`, `ay=|Gy|`: 10 bit unsigned (<=1020);
`mag = ax + ay`: 11 bit unsigned (<=2040).

Summary:

| | adders (Gx,Gy) | adder levels |
|---|---|---|
| naive chain | 10 | 5 |
| balanced only | 10 | 3 |
| **CSE + balanced** | **8** | **3** |

## d. Pipelined schedule, initiation interval II = 1

One register boundary after every adder level, so the clock period is one 10-11 bit adder plus
routing, and **a new window enters every clock** (no stall, no handshake). "px n" below means the
pixel that entered the line buffer at cycle n.

Stage definitions (cycle numbers are relative to the cycle `t` in which the pixel enters `linebuf`):

| stage | cycle | registered operation |
|---|---|---|
| L0 | t   | line-buffer RAMs read at column x, new pixel written |
| L1 | t+1 | rows y-2, y-1, y in registers |
| S1 | t+2 | 3x3 window registers (taps p00..p22), centre = (x-1,y-1) |
| S2 | t+3 | `E1=p22-p00, E2=p02-p20, F=p12-p10, G=p21-p01` |
| S3 | t+4 | `P=E1+E2, Q=E1-E2`, `F,G` carried |
| S4 | t+5 | `Gx=P+(F<<1), Gy=Q+(G<<1)`  (also forced to 0 outside the valid region) |
| S5 | t+6 | `ax=abs(Gx), ay=abs(Gy), sx=Gx[10], sy=Gy[10]` |
| S6 | t+7 | `mag = ax + ay`; `ax,ay,sx,sy,Gx,Gy` delayed one register to stay aligned |

Cycle-by-cycle schedule (rows = clock cycles, each cell = which pixel that stage is working on; every
stage is busy every cycle in steady state, one pixel leaves S6 per cycle => II = 1):

| cycle | L0 read/write | L1 | S1 window | S2 diffs | S3 sums | S4 Gx,Gy | S5 abs | S6 mag |
|---|---|---|---|---|---|---|---|---|
| 0 | px0 |  |  |  |  |  |  |  |
| 1 | px1 | px0 |  |  |  |  |  |  |
| 2 | px2 | px1 | px0 |  |  |  |  |  |
| 3 | px3 | px2 | px1 | px0 |  |  |  |  |
| 4 | px4 | px3 | px2 | px1 | px0 |  |  |  |
| 5 | px5 | px4 | px3 | px2 | px1 | px0 |  |  |
| 6 | px6 | px5 | px4 | px3 | px2 | px1 | px0 |  |
| 7 | px7 | px6 | px5 | px4 | px3 | px2 | px1 | px0 (first mag) |
| 8 | px8 | px7 | px6 | px5 | px4 | px3 | px2 | px1 |
| ... | ... | ... | ... | ... | ... | ... | ... | ... |

Latency from "newest pixel in" to "result out" = 7 cycles; throughput = 1 result/cycle.
The window centre is one line + one pixel behind the newest pixel, so the Sobel result for
pixel (x-1,y-1) leaves in the cycle where pixel (x,y) + 7 is on the input bus (the tag carried
along with the data is the centre coordinate, see `tag_center.sv`).

Per-stage register inventory (what the schedule costs): S2 4x9 b, S3 2x10 b + 2x9 b, S4 2x11 b,
S5 2x10 b + 2 b, S6 11 b + delayed copies. Datapath adders: 4 (S2) + 2 (S3) + 2 (S4) + 2 abs + 1 mag.

The direction quantiser (`dir_quant`, in `dirnms.sv`) attaches after S5/S6 and is described in
`doc/n4_espresso_results.md`.
