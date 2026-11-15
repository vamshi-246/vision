# N4 -- direction quantiser + NMS select as an Espresso-minimised block

Reproduce: `python3 scripts/espresso_dirnms.py` (full verbatim output in `sim/reports/espresso_dirnms.log`).

## Which tool actually ran (brief's order: espresso-logic -> pyeda -> sympy)
1. `espresso-logic` via apt: **not available** (`apt-get install espresso` -> "Unable to locate package"; `apt-cache search`
   only finds an unrelated chemistry package called quantum-espresso).
2. `espresso-logic` / `espresso-logic-minimizer` / `espresso_py` via pip: **no matching distribution**.
3. **pyeda 0.29.0 (installed with pip) -- its espresso binding, i.e. the UC Berkeley Espresso C engine bundled in pyeda.
   This is what produced every number below.** pyeda installs a command-line wrapper `/usr/local/bin/espresso`
   (a Python script around the same binding, reads a PLA file); the script calls it and captures its output verbatim.
   sympy was not needed.

## The function
Direction quantisation is `|Gy|*32 <= |Gx|*13` (sector 0), `|Gx|*32 <= |Gy|*13` (sector 2), otherwise a diagonal whose
orientation comes from the sign bits. The two comparators are arithmetic (shift-add + compare, `dir_quant` stage D1);
what is minimised here is the **decision logic that follows them**: 4 inputs, 4 one-hot outputs. The one-hot output is
also the NMS neighbour-pair select (it picks which two of the 8 neighbours are compared).

| inputs | meaning |
|---|---|
| c0 | `|Gy|*32 <= |Gx|*13` |
| c2 | `|Gx|*32 <= |Gy|*13` |
| sx, sy | sign bits of Gx, Gy (1 = negative) |

| output | sector | NMS pair (a, b) |
|---|---|---|
| s0 | 0 | W, E |
| s1 | 1 (diagonal, signs equal) | NW, SE |
| s2 | 2 | N, S |
| s3 | 3 (diagonal, signs differ) | NE, SW |

Truth table (16 rows). `c0=c2=1` can only occur when `|Gx|=|Gy|=0`, whose sign bits are both 0, so the three rows
`1101, 1110, 1111` are **unreachable -> don't-care** (`-`). Row `1100` (both gradients zero) is reachable and maps to sector 0.

```
c0 c2 sx sy | s0 s1 s2 s3          c0 c2 sx sy | s0 s1 s2 s3
 0  0  0  0 |  0  1  0  0           1  0  0  0 |  1  0  0  0
 0  0  0  1 |  0  0  0  1           1  0  0  1 |  1  0  0  0
 0  0  1  0 |  0  0  0  1           1  0  1  0 |  1  0  0  0
 0  0  1  1 |  0  1  0  0           1  0  1  1 |  1  0  0  0
 0  1  0  0 |  0  0  1  0           1  1  0  0 |  1  0  0  0
 0  1  0  1 |  0  0  1  0           1  1  0  1 |  -  -  -  -
 0  1  1  0 |  0  0  1  0           1  1  1  0 |  -  -  -  -
 0  1  1  1 |  0  0  1  0           1  1  1  1 |  -  -  -  -
```

## Real tool output (verbatim from the run)
```
.i 4
.o 4
.ilb c0 c2 sx sy
.ob s0 s1 s2 s3
.p 6
01-- 0010
1--- 1000
0010 0001
0000 0100
0001 0001
0011 0100
.e
```
As equations (this is exactly what `rtl/dirnms.sv::dirq_decision` implements):
```
s0 = c0
s2 = ~c0 & c2
s1 = ~c0&~c2&~sx&~sy | ~c0&~c2&sx&sy
s3 = ~c0&~c2&sx&~sy | ~c0&~c2&~sx&sy
```

## Before / after (counted by the script from the tool's output)

| | product terms | literals |
|---|---|---|
| BEFORE: canonical minterm SOP of the 4 outputs (each ON-set minterm = a 4-literal product) | **13** | **52** |
| AFTER: Espresso cover (shared multi-output PLA) | **6** | **19** |
| reference: Espresso on the same function with the don't-cares forced to 0 | 7 | 23 |

So minimisation removes 7 of 13 terms and 33 of 52 literals, and using the don't-cares saves a further product term
and 4 literals compared with ignoring them.

Correctness: the script re-evaluates the minimised cover against the specification on all 12 reachable rows (True),
`tb/tb_dirq.sv` checks the RTL against the specification on those 12 rows (outputs also one-hot), and runs
`dir_quant` on 67,338 (gx,gy) pairs concentrated on the 13/32 and 32/13 boundaries, against `golden.direction`: 0 mismatches
(`sim/reports/tb_dirq.log`).

## Honest limits of this result
* The block is tiny (4 inputs). On the FPGA every output is a function of 4 inputs and maps to **one LUT regardless of
  minimisation**; the literal/term reduction is a real, measured gate-level reduction (ASIC-style cost), not a LUT saving.
  I did not run a with/without LUT comparison because it would show no difference for a 4-input function.
* The two diagonal outputs are XOR/XNOR of the signs gated by `~c0&~c2`; a two-level SOP tool cannot merge them,
  which is why s1 and s3 stay at 2 terms / 8 literals each.
* No BDD tool was run; the brief's "ESPRESSO/BDD block" is covered by Espresso alone.
