#!/usr/bin/env python3
"""Unit-3 logic and FSM optimisation study (all numbers in report Section 5 come from here).

 1. State minimisation of the adaptive-Otsu controller: the specification STG (7 states, a separate RECOVER state for the
    overrun / disable path) -> implication chart (pair table, iterated to a fixed point) -> equivalence classes.
 2. Heuristic state assignment: adjacency weights (states with a common successor / predecessor / same outputs should get
    codes at Hamming distance 1), exhaustive search of 3-bit codes minimising sum(w * distance).  The chosen codes are then
    synthesised with FSM extraction off (logic/fsm_encodings via scripts/ooc_batch.py).
 3. Two-level minimisation of the ESPRESSO/BDD block - the direction quantiser + NMS select:
      dir_decide (4 inputs, 2 outputs) and the full NMS-keep function (sector bits + 8 neighbour comparators, 12 inputs)
    by our own Quine-McCluskey (prime generation) + unate covering (essentials, row/column dominance, branch and bound
    with an independent-set lower bound), and by Berkeley ESPRESSO (heuristic and -Dexact).
 4. Multilevel: algebraic kernels / co-kernels of the NMS-keep cover, literal count after factoring, and Yosys+ABC.
Outputs: build/logic/logic_study.json (+ PLA files, ABC logs).
"""
import itertools, json, re, subprocess
from functools import lru_cache
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "build" / "logic"; OUT.mkdir(parents=True, exist_ok=True)
ESPRESSO = ROOT / "build/tools/src/espresso-logic/bin/espresso"

# ------------------------------------------------------------------------------------------------
# 1. FSM: specification STG of the adaptive-threshold controller (Mealy).  Inputs: en sof eof odone cdone px ovr.
# ------------------------------------------------------------------------------------------------
INPUTS = ["en", "sof", "eof", "odone", "cdone", "px", "ovr"]
OUTS = ["count_en", "clr_both", "clr_one", "swap", "apply", "init_done"]


def spec_step(s, i):
    """Specification STG (written from the English spec before minimisation).  Returns (next, outputs)."""
    en, sof, eof, odone, cdone, px, ovr = i
    o = dict.fromkeys(OUTS, 0)
    if s in ("INIT", "RECOVER"):             # INIT after reset; RECOVER after an overrun or a disable
        o["clr_both"] = 1
        if cdone: o["init_done"] = 1; return "ARM", o
        return s, o
    if s == "ARM":
        if en and sof: o["count_en"] = 1; return "COLLECT", o
        return s, o
    if s == "COLLECT":
        o["count_en"] = 1
        if not en: return "RECOVER", o
        if eof: o["swap"] = 1; return "SWEEP", o
        return s, o
    if s == "SWEEP":
        o["count_en"] = 1
        return ("CLEAR" if odone else s), o
    if s == "CLEAR":
        o["count_en"] = 1; o["clr_one"] = 1
        if cdone:
            if ovr or not en: return "RECOVER", o
            if px: return "PEND", o
            o["apply"] = 1; return "COLLECT", o
        return s, o
    if s == "PEND":
        o["count_en"] = 1
        if not en: return "RECOVER", o
        if eof: o["swap"] = 1; o["apply"] = 1; return "SWEEP", o
        return s, o
    raise ValueError(s)


SPEC_STATES = ["INIT", "ARM", "COLLECT", "SWEEP", "CLEAR", "PEND", "RECOVER"]
ALL_IN = list(itertools.product([0, 1], repeat=len(INPUTS)))


def implication_chart(states, step):
    pairs = [(a, b) for i, a in enumerate(states) for b in states[i + 1:]]
    chart = {}
    for a, b in pairs:   # pass 0: different outputs for some input -> X ; otherwise list implied pairs
        if any(step(a, i)[1] != step(b, i)[1] for i in ALL_IN):
            chart[(a, b)] = "X"
        else:
            imp = set()
            for i in ALL_IN:
                na, nb = step(a, i)[0], step(b, i)[0]
                if na != nb: imp.add(tuple(sorted((na, nb), key=states.index)))
            chart[(a, b)] = imp
    passes = [dict((k, ("X" if v == "X" else sorted(v))) for k, v in chart.items())]
    changed = True
    while changed:
        changed = False
        for k, v in chart.items():
            if v != "X" and any(chart.get(p) == "X" for p in v):
                chart[k] = "X"; changed = True
        passes.append({k: ("X" if v == "X" else sorted(v)) for k, v in chart.items()})
    eq = [k for k, v in chart.items() if v != "X"]
    return chart, eq, len(passes) - 1, passes[0]


def encoding_heuristic(states, step):
    """Adjacency weights (De Micheli / lecture rules): +2 per common successor under the same input (fan-out rule),
    +1 per common predecessor (fan-in rule), +1 if the Moore part of the outputs is identical."""
    succ = {s: {step(s, i)[0] for i in ALL_IN} for s in states}
    pred = {s: {p for p in states if s in succ[p]} for s in states}
    w = {}
    for a, b in itertools.combinations(states, 2):
        same_next = sum(1 for i in ALL_IN if step(a, i)[0] == step(b, i)[0])
        w[(a, b)] = 2 * (same_next > 0) + len((pred[a] & pred[b]) - {a, b}) + (step(a, ALL_IN[0])[1] == step(b, ALL_IN[0])[1]) \
                    + (1 if b in succ[a] or a in succ[b] else 0)
    best = None
    for codes in itertools.permutations(range(8), len(states)):
        if codes[0] != 0: continue                      # reset state INIT = 000 (cheap synchronous reset)
        cost = sum(wt * bin(codes[states.index(a)] ^ codes[states.index(b)]).count("1") for (a, b), wt in w.items())
        if best is None or cost < best[0]: best = (cost, codes)
    binary_cost = sum(wt * bin(states.index(a) ^ states.index(b)).count("1") for (a, b), wt in w.items())
    return {f"{a}-{b}": v for (a, b), v in w.items()}, dict(zip(states, best[1])), best[0], binary_cost


# ------------------------------------------------------------------------------------------------
# 3. Two-level: Quine-McCluskey + unate covering
# ------------------------------------------------------------------------------------------------
def qm_primes(on, dc, n):
    """Tabular method: group by number of ones, merge cubes differing in one bit; cubes as (value, mask)."""
    cur = {(m, 0) for m in on | dc}
    primes = set(); levels = []
    while cur:
        levels.append(len(cur))
        nxt, used = set(), set()
        cl = sorted(cur)
        bymask = {}
        for c in cl: bymask.setdefault(c[1], []).append(c)
        for mask, cs in bymask.items():
            s = set(cs)
            for v, m in cs:
                for b in range(n):
                    if (m >> b) & 1 or (v >> b) & 1: continue
                    partner = (v | (1 << b), m)
                    if partner in s:
                        nxt.add((v, m | (1 << b))); used.add((v, m)); used.add(partner)
        primes |= cur - used
        cur = nxt
    return primes, levels


def covers(c, m): return (m & ~c[1]) == c[0]


def lits(c, n): return n - bin(c[1]).count("1")


def ucp(primes, on, n):
    """Minimum-cost cover (cost = 1 per cube, ties broken by literals): reductions + branch and bound."""
    primes = sorted(primes)
    rows0 = {m: frozenset(j for j, p in enumerate(primes) if covers(p, m)) for m in on}
    stats = {"rows": len(rows0), "cols": len(primes)}

    def reduce(rows, cols, chosen):
        changed = True
        while changed:
            changed = False
            for m, r in list(rows.items()):                 # essential columns
                if len(r) == 1:
                    j = next(iter(r)); chosen = chosen | {j}
                    rows = {k: v for k, v in rows.items() if j not in v}; cols = cols - {j}; changed = True; break
            if changed: continue
            rl = list(rows.items())                          # row dominance: drop rows that contain another row
            for (m1, r1), (m2, r2) in itertools.permutations(rl, 2):
                if m1 in rows and m2 in rows and r2 <= r1 and (r1 != r2 or m1 > m2):
                    del rows[m1]; changed = True
            if changed: continue
            for j1, j2 in itertools.permutations(sorted(cols), 2):   # column dominance (equal cost columns)
                if j1 in cols and j2 in cols:
                    s1 = {m for m, r in rows.items() if j1 in r}; s2 = {m for m, r in rows.items() if j2 in r}
                    if s1 <= s2 and (s1 != s2 or j1 > j2):
                        cols = cols - {j1}; rows = {m: r - {j1} for m, r in rows.items()}; changed = True
        return rows, cols, chosen

    best = [None]; nodes = [0]; core = [None]

    def lower_bound(rows):                                   # maximal independent set of rows
        lb, used = 0, set()
        for m, r in sorted(rows.items(), key=lambda kv: len(kv[1])):
            if not (r & used): lb += 1; used |= r
        return lb

    def bb(rows, cols, chosen):
        nodes[0] += 1
        rows, cols, chosen = reduce(rows, cols, chosen)
        if core[0] is None: core[0] = (len(rows), len(cols), len(chosen))
        if not rows:
            key = (len(chosen), sum(lits(primes[j], n) for j in chosen))
            if best[0] is None or key < best[0][0]: best[0] = (key, chosen)
            return
        if best[0] is not None and len(chosen) + lower_bound(rows) > best[0][0][0]: return
        m, r = min(rows.items(), key=lambda kv: len(kv[1]))
        for j in sorted(r, key=lambda j: -sum(1 for rr in rows.values() if j in rr)):
            bb({k: v for k, v in rows.items() if j not in v}, cols - {j}, chosen | {j})

    bb(dict(rows0), set(range(len(primes))), frozenset())
    stats.update(nodes=nodes[0], cyclic_core_rows=core[0][0], cyclic_core_cols=core[0][1], essentials=core[0][2])
    cover = [primes[j] for j in sorted(best[0][1])]
    return cover, stats


def cube_str(c, names):
    out = []
    for b, nm in enumerate(names):
        bit = len(names) - 1 - b
        if (c[1] >> bit) & 1: continue
        out.append(nm if (c[0] >> bit) & 1 else "~" + nm)
    return "&".join(out) if out else "1"


# functions --------------------------------------------------------------------------------------
DIR_IN = ["c0", "c2", "sx", "sy"]


def dir_spec(c0, c2, sx, sy):
    """Sector from the two comparators and signs: 00 horizontal-gradient sector (W/E), 10 vertical (N/S),
    01 diagonal with equal signs (NW/SE), 11 diagonal with different signs (NE/SW).  c0&c2 only if Gx=Gy=0 (signs 0)."""
    if c0 and c2 and (sx or sy): return None              # impossible -> don't care
    if c0: return 0b00
    if c2: return 0b10
    return 0b01 if sx == sy else 0b11


NMS_IN = DIR_IN + ["geW", "gtE", "geNW", "gtSE", "geN", "gtS", "geNE", "gtSW"]


def nms_spec(bits):
    d = dir_spec(*bits[:4])
    if d is None: return None
    ge, gt = {0b00: (4, 5), 0b01: (6, 7), 0b10: (8, 9), 0b11: (10, 11)}[d]
    return int(bits[ge] and bits[gt])


def tables():
    n = 4; on1, on0, dc = set(), set(), set()
    for m in range(16):
        b = [(m >> (3 - k)) & 1 for k in range(4)]
        d = dir_spec(*b)
        if d is None: dc.add(m)
        else:
            if d & 2: on1.add(m)
            if d & 1: on0.add(m)
    N = 12; onk, dck = set(), set()
    for m in range(1 << N):
        b = [(m >> (N - 1 - k)) & 1 for k in range(N)]
        v = nms_spec(b)
        if v is None: dck.add(m)
        elif v: onk.add(m)
    return {"dir1": (on1, dc, 4, DIR_IN), "dir0": (on0, dc, 4, DIR_IN), "keep": (onk, dck, 12, NMS_IN)}


def write_pla(path, on, dc, n, names, out="f"):
    L = [f".i {n}", ".o 1", ".ilb " + " ".join(names), f".ob {out}", ".type fd"]
    L += [format(m, f"0{n}b") + " 1" for m in sorted(on)] + [format(m, f"0{n}b") + " -" for m in sorted(dc)]
    L.append(".e"); path.write_text("\n".join(L) + "\n")


def espresso(path, exact=False):
    args = [str(ESPRESSO)] + (["-Dexact"] if exact else []) + [str(path)]
    p = subprocess.run(args, capture_output=True, text=True, timeout=600)
    cubes = [l.split()[0] for l in p.stdout.splitlines() if l and l[0] in "01-"]
    return len(cubes), sum(sum(ch != "-" for ch in c) for c in cubes), cubes


# ------------------------------------------------------------------------------------------------
# 4. Multilevel: kernels and co-kernels (algebraic, cubes as frozensets of literals)
# ------------------------------------------------------------------------------------------------
def to_alg(cover, names, n):
    return [frozenset(lit for lit in cube_str(c, names).split("&")) for c in cover]


def divide_cube(F, c): return [cube - c for cube in F if c <= cube]


def kernels(F):
    res = {}
    lits_all = sorted({l for cube in F for l in cube})
    def rec(G, cok, start):
        for i, l in enumerate(lits_all):
            if i < start: continue
            if sum(1 for cube in G if l in cube) >= 2:
                Q = divide_cube(G, frozenset([l]))
                common = frozenset.intersection(*Q)
                if any(lits_all.index(x) < i for x in common): continue
                K = [q - common for q in Q]
                ck = cok | {l} | common
                res[frozenset(ck)] = K
                rec(K, ck, i + 1)
    common = frozenset.intersection(*F) if F else frozenset()
    if not common: res[frozenset()] = F
    rec([c - common for c in F], frozenset(common), 0)
    return res


def lit_count(F): return sum(len(c) for c in F)


def abc_stats(verilog_text, top):
    v = OUT / f"{top}.v"; v.write_text(verilog_text)
    out = {}
    for label, cmd in (("aig_and_not", "abc -g AND"), ("gates_and_or_xor_mux", "abc -g AND,OR,NAND,NOR,XOR,XNOR,MUX"),
                       ("lut6", "abc -lut 6"), ("lut4", "abc -lut 4")):
        p = subprocess.run(["yosys", "-p", f"read_verilog \"{v}\"; synth -top {top} -flatten; {cmd}; opt_clean; stat"], capture_output=True, text=True)
        tail = p.stdout[p.stdout.rindex("Number of cells"):]
        out[label] = {m[0]: int(m[1]) for m in re.findall(r"(\$\w+)\s+(\d+)", tail.split("End of script")[0])}
    return out


def main():
    res = {}
    chart, eq, passes, first = implication_chart(SPEC_STATES, spec_step)
    res["fsm"] = {"spec_states": SPEC_STATES, "equivalent_pairs": [list(p) for p in eq], "passes": passes,
                  "chart_pass0": {f"{a}|{b}": v for (a, b), v in first.items()},
                  "chart_final": {f"{a}|{b}": ("X" if v == "X" else "=") for (a, b), v in chart.items()}}
    MIN = [s for s in SPEC_STATES if s != "RECOVER"]
    def min_step(s, i):
        n, o = spec_step(s, i); return ("INIT" if n == "RECOVER" else n), o
    chart2, eq2, _, _ = implication_chart(MIN, min_step)
    res["fsm"]["minimised_states"] = MIN; res["fsm"]["minimised_equivalent_pairs"] = [list(p) for p in eq2]
    w, codes, cost, bincost = encoding_heuristic(MIN, min_step)
    res["fsm"]["weights"] = w; res["fsm"]["heuristic_codes"] = {s: format(c, "03b") for s, c in codes.items()}
    res["fsm"]["heuristic_cost"] = cost; res["fsm"]["binary_cost"] = bincost
    # two-level
    res["two_level"] = {}
    for name, (on, dc, n, names) in tables().items():
        primes, levels = qm_primes(on, dc, n)
        cover, st = ucp(primes, on, n)
        pla = OUT / f"{name}.pla"; write_pla(pla, on, dc, n, names, name)
        eh = espresso(pla); ex = espresso(pla, exact=True)
        canon = (len(on), len(on) * n)
        res["two_level"][name] = dict(inputs=n, on_minterms=len(on), dc_minterms=len(dc), canonical_terms=canon[0], canonical_literals=canon[1],
                                      qm_column_sizes=levels, primes=len(primes), ucp=st,
                                      qm_ucp_terms=len(cover), qm_ucp_literals=sum(lits(c, n) for c in cover),
                                      qm_ucp_cover=[cube_str(c, names) for c in cover],
                                      espresso_terms=eh[0], espresso_literals=eh[1], espresso_exact_terms=ex[0], espresso_exact_literals=ex[1])
        if name == "keep":
            F = to_alg(cover, names, n)
            K = kernels(F)
            res["multilevel"] = {"sop_literals": lit_count(F), "kernels": len(K),
                                 "kernel_list": [{"cokernel": "&".join(sorted(ck)) or "1", "kernel": " + ".join("&".join(sorted(c)) or "1" for c in k)} for ck, k in list(K.items())[:40]]}
    # factored form of keep, derived from the best kernel: keep = sum over sectors of sel_d * (ge_d gt_d)
    fact = ("keep = ~c0&~c2&( (sx~^sy)&geNW&gtSE + (sx^sy)&geNE&gtSW ) + c0&geW&gtE + ~c0&c2&geN&gtS")
    res["multilevel"]["factored"] = fact
    res["multilevel"]["factored_literals"] = 2 + 2 + 2 + 2 + 2 + 2 + 2 + 1 + 2 + 2 + 2   # counted from the expression above
    verilog = """module nms_select(input c0,c2,sx,sy,geW,gtE,geNW,gtSE,geN,gtS,geNE,gtSW, output keep);
  wire [1:0] dir; dir_decide d(.c0(c0),.c2(c2),.sx(sx),.sy(sy),.dir(dir));
  assign keep = (dir==2'b00) ? (geW&gtE) : (dir==2'b01) ? (geNW&gtSE) : (dir==2'b10) ? (geN&gtS) : (geNE&gtSW);
endmodule
""" + (ROOT / "rtl/dir_decide.sv").read_text().replace("`default_nettype none", "").replace("`default_nettype wire", "").replace("wire", "wire", 1)
    res["abc"] = abc_stats(verilog, "nms_select")
    (OUT / "logic_study.json").write_text(json.dumps(res, indent=1) + "\n")
    print(json.dumps({k: v for k, v in res.items() if k != "multilevel"}, indent=1)[:6000])
    print("multilevel:", res["multilevel"]["sop_literals"], "SOP literals,", res["multilevel"]["kernels"], "kernels")
    for k in res["multilevel"]["kernel_list"][:12]: print("  ", k)


if __name__ == "__main__":
    main()
