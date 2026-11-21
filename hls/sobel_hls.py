#!/usr/bin/env python3
"""Hand-HLS of the Sobel window + magnitude + direction comparators (VL401 Units 1-3).

Everything the report's Section 4 quotes is computed here, not typed in:
  * DFGs of five versions of the kernel (original 3x3 convolution -> constant folding / dead code
    -> strength reduction -> tree-height reduction -> CSE), with operation counts and critical paths;
  * ASAP, ALAP (latency bound = critical path) and mobility of the final DFG;
  * list scheduling (priority = longest path to a sink, then mobility) under two resource constraints;
  * an exact time-constrained ILP (scipy.optimize.milp) giving the minimum number of units per latency;
  * left-edge register binding and clique-partitioning functional-unit binding (compatibility graph);
  * generation of the FSMD RTL (rtl/study/sobel_fsmd_*.sv) that realises a schedule + binding exactly.
Unit-delay model: each add/sub/compare/abs/multiply takes one control step, shifts by constants are wiring.
Outputs: build/hls/hls_results.json, build/hls/*.dot (+ .pdf), rtl/study/sobel_fsmd_<name>.sv
"""
import json, subprocess, sys
from pathlib import Path
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "build" / "hls"

# ----------------------------------------------------------------------------------------------
# 1. DFG versions.  op = name -> (type, [predecessor ops], text).  Inputs (pixels) are not ops.
# ----------------------------------------------------------------------------------------------
KX = {(0, 0): -1, (0, 1): 0, (0, 2): 1, (1, 0): -2, (1, 1): 0, (1, 2): 2, (2, 0): -1, (2, 1): 0, (2, 2): 1}
KY = {(0, 0): -1, (0, 1): -2, (0, 2): -1, (1, 0): 0, (1, 1): 0, (1, 2): 0, (2, 0): 1, (2, 1): 2, (2, 2): 1}


def tail(ops, gx, gy, strength_reduced, tree_13):
    """|Gx|, |Gy|, magnitude and the two direction comparators 32|Gy| <= 13|Gx|, 32|Gx| <= 13|Gy|."""
    ops["absx"] = ("ABS", [gx], "|Gx|")
    ops["absy"] = ("ABS", [gy], "|Gy|")
    ops["mag"] = ("ADD", ["absx", "absy"], "|Gx|+|Gy|")
    for a, b, c in (("absx", "absy", "c0"), ("absy", "absx", "c2")):
        if strength_reduced:          # 13a = (a<<3)+(a<<2)+a : 2 adders; 32b = b<<5 : wiring
            ops[f"t13{a}"] = ("ADD", [a], f"8{a}+4{a}")
            ops[f"m13{a}"] = ("ADD", [f"t13{a}", a], f"13{a}")
            ops[c] = ("ADD", [f"m13{a}", b], f"32{b}<=13{a}")          # comparator = subtract + sign
        else:
            ops[f"m13{a}"] = ("MUL", [a], f"13*{a}")
            ops[f"m32{b}"] = ("MUL", [b], f"32*{b}")
            ops[c] = ("ADD", [f"m13{a}", f"m32{b}"], f"32{b}<=13{a}")
    return ops


def v_original():
    """Textbook 3x3 convolution: 9 products, accumulated left to right (loop), for each gradient."""
    ops = {}
    for g, K in (("x", KX), ("y", KY)):
        prev = None
        for (r, c), k in K.items():
            ops[f"mul{g}{r}{c}"] = ("MUL", [], f"{k}*p{r}{c}")
            if prev is None:
                prev = f"mul{g}{r}{c}"
            else:
                ops[f"acc{g}{r}{c}"] = ("ADD", [prev, f"mul{g}{r}{c}"], "acc")
                prev = f"acc{g}{r}{c}"
        ops[f"G{g}"] = ops.pop(prev)
        # re-point users of prev (none yet) - prev was last op
    return tail(ops, "Gx", "Gy", False, False)


def chain_form(strength_reduced):
    """Zero taps removed and x1 / x-1 folded into add/sub (constant folding + dead-code elimination)."""
    ops = {}
    for g, K in (("x", KX), ("y", KY)):
        terms = [((r, c), k) for (r, c), k in K.items() if k != 0]
        # the natural written order: positive taps first, then negative ones
        terms.sort(key=lambda t: -t[1] if False else (t[1] < 0))
        prev = None
        for (r, c), k in terms:
            src = None
            if abs(k) == 2 and not strength_reduced:
                ops[f"mul{g}{r}{c}"] = ("MUL", [], f"2*p{r}{c}")
                src = f"mul{g}{r}{c}"
            if prev is None:
                prev = src if src else f"p{r}{c}"
                continue
            preds = [p for p in (prev, src) if p and not p.startswith("p")]
            ops[f"acc{g}{r}{c}"] = ("ADD", preds, "+/-")
            prev = f"acc{g}{r}{c}"
        ops[f"G{g}"] = ops.pop(prev)
        for n, (t, pr, txt) in list(ops.items()):
            ops[n] = (t, [f"G{g}" if p == prev else p for p in pr], txt)
    return tail(ops, "Gx", "Gy", strength_reduced, False)


def v_treeheight():
    """Balanced trees: Gx = ((p02-p00) + (p22-p20)) + 2(p12-p10), Gy likewise - no sharing yet."""
    ops = {}
    for g, (a, b, c, d, e, f) in (("x", ("p02", "p00", "p22", "p20", "p12", "p10")),
                                  ("y", ("p20", "p00", "p22", "p02", "p21", "p01"))):
        ops[f"d1{g}"] = ("ADD", [], f"{a}-{b}")
        ops[f"d2{g}"] = ("ADD", [], f"{c}-{d}")
        ops[f"d3{g}"] = ("ADD", [], f"{e}-{f}")
        ops[f"s{g}"] = ("ADD", [f"d1{g}", f"d2{g}"], "sum")
        ops[f"G{g}"] = ("ADD", [f"s{g}", f"d3{g}"], f"G{g}")
    return tail(ops, "Gx", "Gy", True, True)


def v_final():
    """CSE (E1 = p22-p00 and E2 = p02-p20 shared by Gx and Gy) on top of the balanced trees.  Shipped form."""
    ops = {
        "E1": ("ADD", [], "p22-p00"), "E2": ("ADD", [], "p02-p20"),
        "F": ("ADD", [], "p12-p10"), "G": ("ADD", [], "p21-p01"),
        "P": ("ADD", ["E1", "E2"], "E1+E2"), "Q": ("ADD", ["E1", "E2"], "E1-E2"),
        "Gx": ("ADD", ["P", "F"], "P+2F"), "Gy": ("ADD", ["Q", "G"], "Q+2G"),
    }
    return tail(ops, "Gx", "Gy", True, True)


VERSIONS = [
    ("Original (3x3 convolution, loop order)", v_original),
    ("+ constant folding, dead-code elimination", lambda: chain_form(False)),
    ("+ strength reduction (x2, x32 wiring; x13 shift-add)", lambda: chain_form(True)),
    ("+ tree-height reduction", v_treeheight),
    ("+ CSE of E1, E2 (shipped kernel)", v_final),
]


def topo(ops):
    order, seen = [], set()
    def visit(n):
        if n in seen: return
        seen.add(n)
        for p in ops[n][1]: visit(p)
        order.append(n)
    for n in ops: visit(n)
    return order


def succs(ops):
    s = {n: [] for n in ops}
    for n, (_, pr, _) in ops.items():
        for p in pr: s[p].append(n)
    return s


def asap(ops):
    t = {}
    for n in topo(ops):
        t[n] = 1 + max([t[p] for p in ops[n][1]], default=0)
    return t


def alap(ops, lam):
    s = succs(ops); t = {}
    for n in reversed(topo(ops)):
        t[n] = min([t[c] for c in s[n]], default=lam + 1) - 1
    return t


def counts(ops):
    c = {"MUL": 0, "ADD": 0, "ABS": 0}
    for t, _, _ in ops.values(): c[t] += 1
    return c


# ----------------------------------------------------------------------------------------------
# 2. Scheduling
# ----------------------------------------------------------------------------------------------
def longest_to_sink(ops):
    s = succs(ops); d = {}
    for n in reversed(topo(ops)):
        d[n] = 1 + max([d[c] for c in s[n]], default=0)
    return d


def list_schedule(ops, res):
    """Resource-constrained list scheduling; priority = longest path to sink, tie -> lower mobility, name."""
    lp = longest_to_sink(ops)
    lam = max(asap(ops).values())
    mob = {n: alap(ops, lam)[n] - asap(ops)[n] for n in ops}
    sched, step = {}, 0
    while len(sched) < len(ops):
        step += 1
        ready = [n for n in ops if n not in sched and all(p in sched and sched[p] < step for p in ops[n][1])]
        for typ, cap in res.items():
            cand = sorted([n for n in ready if ops[n][0] == typ], key=lambda n: (-lp[n], mob[n], n))
            for n in cand[:cap]:
                sched[n] = step
    return sched


def ilp_min_units(ops, lam, weight={"ADD": 1.0, "ABS": 1.0}):
    """Exact time-constrained scheduling: minimise sum(weight_k * N_k) subject to latency <= lam."""
    from scipy.optimize import milp, LinearConstraint, Bounds
    a, l = asap(ops), alap(ops, lam)
    var = [(n, t) for n in ops for t in range(a[n], l[n] + 1)]
    types = sorted({ops[n][0] for n in ops})
    nv = len(var) + len(types)
    idx = {v: i for i, v in enumerate(var)}
    tix = {k: len(var) + i for i, k in enumerate(types)}
    rows, lo, hi = [], [], []
    for n in ops:                               # each op scheduled exactly once
        r = np.zeros(nv)
        for t in range(a[n], l[n] + 1): r[idx[(n, t)]] = 1
        rows.append(r); lo.append(1); hi.append(1)
    for n, (_, pr, _) in ops.items():           # precedence: t_n - t_p >= 1
        for p in pr:
            r = np.zeros(nv)
            for t in range(a[n], l[n] + 1): r[idx[(n, t)]] += t
            for t in range(a[p], l[p] + 1): r[idx[(p, t)]] -= t
            rows.append(r); lo.append(1); hi.append(np.inf)
    for k in types:                             # resources per step
        for t in range(1, lam + 1):
            r = np.zeros(nv)
            for n in ops:
                if ops[n][0] == k and (n, t) in idx: r[idx[(n, t)]] = 1
            r[tix[k]] = -1
            rows.append(r); lo.append(-np.inf); hi.append(0)
    c = np.zeros(nv)
    for k in types: c[tix[k]] = weight.get(k, 1.0)
    integ = np.ones(nv)
    ub = np.ones(nv); [ub.__setitem__(tix[k], len(ops)) for k in types]
    res = milp(c, constraints=LinearConstraint(np.array(rows), lo, hi), integrality=integ, bounds=Bounds(np.zeros(nv), ub))
    if not res.success: return None
    x = res.x
    sched = {n: t for (n, t) in var if x[idx[(n, t)]] > 0.5}
    return {k: int(round(x[tix[k]])) for k in types}, sched


# ----------------------------------------------------------------------------------------------
# 3. Binding
# ----------------------------------------------------------------------------------------------
INPUTS = ["p00", "p01", "p02", "p10", "p12", "p20", "p21", "p22"]


def lifetimes(ops, sched):
    """Value v lives in a register from the end of its producing step until the step of its last use.
    Interval [birth, death): birth = producing step, death = last consuming step (outputs live to L+1)."""
    s = succs(ops); L = max(sched.values())
    lt = {}
    for n, (t, _, _) in ops.items():
        if n in ("c0", "c2"): continue          # 1-bit flags -> own flag registers
        last = max([sched[c] for c in s[n]], default=L + 1)
        lt[n] = (sched[n], last)
    return lt


def left_edge(lt):
    regs = []                                   # list of (last_death, [values])
    for v in sorted(lt, key=lambda v: (lt[v][0], lt[v][1], v)):
        b, d = lt[v]
        for r in regs:
            if r[0] <= b:                       # register free when the new value is written
                r[0] = d; r[1].append(v); break
        else:
            regs.append([d, [v]])
    return [r[1] for r in regs]


def clique_partition(nodes, compatible):
    """Tseng-Siewiorek style greedy clique partitioning: merge the compatible pair with most common neighbours."""
    groups = [[n] for n in nodes]
    def comp(g, h): return all(compatible(a, b) for a in g for b in h)
    while True:
        best, bscore = None, -1
        for i in range(len(groups)):
            for j in range(i + 1, len(groups)):
                if not comp(groups[i], groups[j]): continue
                common = sum(1 for k in range(len(groups)) if k not in (i, j) and comp(groups[k], groups[i]) and comp(groups[k], groups[j]))
                if common > bscore: best, bscore = (i, j), common
        if best is None: return groups
        i, j = best
        groups[i] = groups[i] + groups[j]; del groups[j]


# ----------------------------------------------------------------------------------------------
# 4. FSMD generator: one control step per state, explicit FUs with operand muxes, bound registers.
# ----------------------------------------------------------------------------------------------
OPSPEC = {   # op -> (kind, (srcA, shiftA), (srcB, shiftB))   kind: add/sub/le/abs
    "E1": ("sub", ("p22", 0), ("p00", 0)), "E2": ("sub", ("p02", 0), ("p20", 0)),
    "F": ("sub", ("p12", 0), ("p10", 0)), "G": ("sub", ("p21", 0), ("p01", 0)),
    "P": ("add", ("E1", 0), ("E2", 0)), "Q": ("sub", ("E1", 0), ("E2", 0)),
    "Gx": ("add", ("P", 0), ("F", 1)), "Gy": ("add", ("Q", 0), ("G", 1)),
    "absx": ("abs", ("Gx", 0), None), "absy": ("abs", ("Gy", 0), None),
    "mag": ("add", ("absx", 0), ("absy", 0)),
    "t13absx": ("add", ("absx", 3), ("absx", 2)), "m13absx": ("add", ("t13absx", 0), ("absx", 0)),
    "t13absy": ("add", ("absy", 3), ("absy", 2)), "m13absy": ("add", ("t13absy", 0), ("absy", 0)),
    "c0": ("le", ("absy", 5), ("m13absx", 0)), "c2": ("le", ("absx", 5), ("m13absy", 0)),
}


def gen_fsmd(name, ops, sched, regs, fus):
    L = max(sched.values())
    reg_of = {v: f"r{i}" for i, vs in enumerate(regs) for v in vs}
    fu_of = {o: f"{typ.lower()}{i}" for typ, groups in fus.items() for i, g in enumerate(groups) for o in g}
    def src(s):
        n, sh = s
        base = f"$signed({{8'd0, {n}_q}})" if n in INPUTS else f"{reg_of[n]}"
        return f"({base} <<< {sh})" if sh else base
    sw = max(3, (L + 1).bit_length())
    lines = [f"`default_nettype none",
             f"// GENERATED by hls/sobel_hls.py - FSMD design point '{name}': {L} control steps,",
             f"// units {', '.join(f'{len(g)} {t}' for t, g in fus.items())}, {len(regs)} data registers (left-edge binding).",
             f"// One window is accepted when idle (start); out_valid pulses after the last step.  Throughput 1 window / {L+1} clocks.",
             f"module sobel_fsmd_{name} (",
             "  input  wire clk, input wire rst, input wire start,",
             "  input  wire [7:0] w00, w01, w02, w10, w11, w12, w20, w21, w22,",
             "  output logic busy, output logic out_valid, output logic [10:0] magnitude, output logic [1:0] direction);",
             f"  logic [{sw-1}:0] step;"]
    lines.append("  logic [7:0] " + ", ".join(f"{p}_q" for p in INPUTS) + ";")
    lines.append("  logic signed [15:0] " + ", ".join(f"r{i}" for i in range(len(regs))) + ";")
    lines.append("  logic c0_q, c2_q, sx_q, sy_q;")
    fu_names = sorted(set(fu_of.values()))
    for f in fu_names:
        if f.startswith("add"):
            lines.append(f"  logic signed [15:0] {f}_a, {f}_b, {f}_y; logic [1:0] {f}_op; logic {f}_le;")
        else:
            lines.append(f"  logic signed [15:0] {f}_a, {f}_y; logic {f}_neg;")
    # operand muxes (combinational, driven by the controller state)
    lines.append("  always_comb begin")
    for f in fu_names:
        if f.startswith("add"): lines.append(f"    {f}_a = '0; {f}_b = '0; {f}_op = 2'd0;")
        else: lines.append(f"    {f}_a = '0;")
    lines.append("    unique case (step)")
    for t in range(1, L + 1):
        body = []
        for o in [o for o in ops if sched[o] == t]:
            kind, a, b = OPSPEC[o]; f = fu_of[o]
            if kind == "abs":
                body.append(f"{f}_a = {src(a)};")
            else:
                code = {"add": 0, "sub": 1, "le": 2}[kind]
                body.append(f"{f}_a = {src(a)}; {f}_b = {src(b)}; {f}_op = 2'd{code}; /* {o} */")
        lines.append(f"      {sw}'d{t}: begin " + " ".join(body) + " end")
    lines.append("      default: ;")
    lines.append("    endcase")
    lines.append("  end")
    for f in fu_names:
        if f.startswith("add"):
            lines.append(f"  assign {f}_y = ({f}_op == 2'd0) ? {f}_a + {f}_b : {f}_a - {f}_b;   // shared adder/subtractor")
            lines.append(f"  assign {f}_le = ({f}_a <= {f}_b);")
        else:
            lines.append(f"  assign {f}_neg = {f}_a < 0;  assign {f}_y = {f}_neg ? -{f}_a : {f}_a;   // absolute-value unit")
    # register writes
    lines.append("  always_ff @(posedge clk) begin")
    lines.append("    if (rst) begin step <= '0; busy <= 1'b0; out_valid <= 1'b0; end")
    lines.append("    else begin")
    lines.append("      out_valid <= 1'b0;")
    lines.append("      if (!busy) begin")
    lines.append("        if (start) begin busy <= 1'b1; step <= 1; " + " ".join(f"{p}_q <= w{p[1:]};" for p in INPUTS) + " end")
    lines.append("      end else begin")
    lines.append("        unique case (step)")
    for t in range(1, L + 1):
        body = []
        for o in [o for o in ops if sched[o] == t]:
            kind = OPSPEC[o][0]; f = fu_of[o]
            if kind == "le":
                body.append(f"{o}_q <= {f}_le;")
            elif kind == "abs":
                body.append(f"{reg_of[o]} <= {f}_y; {'sx' if o == 'absx' else 'sy'}_q <= {f}_neg;")
            else:
                body.append(f"{reg_of[o]} <= {f}_y;")
        lines.append(f"          {sw}'d{t}: begin " + " ".join(body) + " end")
    lines.append("          default: ;")
    lines.append("        endcase")
    lines.append(f"        if (step == {sw}'d{L}) begin busy <= 1'b0; out_valid <= 1'b1; step <= '0; end")
    lines.append("        else step <= step + 1'b1;")
    lines.append("      end")
    lines.append("    end")
    lines.append("  end")
    lines.append(f"  assign magnitude = {reg_of['mag']}[10:0];")
    lines.append("  dir_decide u_dir(.c0(c0_q), .c2(c2_q), .sx(sx_q), .sy(sy_q), .dir(direction));")
    lines.append("endmodule")
    lines.append("`default_nettype wire")
    return "\n".join(lines) + "\n"


def dot_dfg(ops, sched, path, title):
    col = {"ADD": "lightblue", "ABS": "khaki", "MUL": "salmon"}
    L = ["digraph G {", "rankdir=TB; node [shape=circle, style=filled, fontsize=10, fixedsize=true, width=0.62];",
         f'labelloc=t; label="{title}";']
    for p in INPUTS:
        L.append(f'"{p}" [shape=box, fillcolor=white, width=0.45, height=0.3];')
    for n, (t, pr, txt) in ops.items():
        lab = {"absx": "|Gx|", "absy": "|Gy|", "t13absx": "8a+4a", "m13absx": "13ax", "t13absy": "8a+4a", "m13absy": "13ay"}.get(n, n)
        L.append(f'"{n}" [label="{lab}", fillcolor={col[t]}];')
    for n in ["E1", "E2", "F", "G"]:
        for p in OPSPEC[n][1:]:
            L.append(f'"{p[0]}" -> "{n}";')
    for n, (t, pr, _) in ops.items():
        for p in pr: L.append(f'"{p}" -> "{n}";')
    L.append('"mag" -> "out_mag" ; "c0" -> "dir"; "c2" -> "dir"; "out_mag" [shape=box, fillcolor=white]; "dir" [shape=box, fillcolor=white, label="dir_decide"];')
    L.append("}")
    path.write_text("\n".join(L) + "\n")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    res = {"versions": []}
    for name, f in VERSIONS:
        ops = f(); c = counts(ops)
        res["versions"].append(dict(name=name, mul=c["MUL"], add=c["ADD"], abs=c["ABS"], critical=max(asap(ops).values()), ops=len(ops)))
    ops = v_final()
    lam = max(asap(ops).values())
    A, Lt = asap(ops), alap(ops, lam)
    res["asap_alap"] = {n: dict(type=ops[n][0], text=ops[n][2], asap=A[n], alap=Lt[n], mobility=Lt[n] - A[n]) for n in topo(ops)}
    res["latency_bound"] = lam
    # ASAP resource usage
    use = {}
    for n in ops: use.setdefault((ops[n][0], A[n]), 0); use[(ops[n][0], A[n])] += 1
    res["asap_max_units"] = {k: max(v for (t, s), v in use.items() if t == k) for k in ("ADD", "ABS")}
    points = {"r2a1b": {"ADD": 2, "ABS": 1}, "r1a1b": {"ADD": 1, "ABS": 1}}
    res["list"] = {}
    for pname, r in points.items():
        s = list_schedule(ops, r)
        lt = lifetimes(ops, s); regs = left_edge(lt)
        addops = [o for o in ops if ops[o][0] == "ADD"]
        fus = {"ADD": clique_partition(addops, lambda a, b: s[a] != s[b]),
               "ABS": clique_partition([o for o in ops if ops[o][0] == "ABS"], lambda a, b: s[a] != s[b])}
        res["list"][pname] = dict(resources=r, latency=max(s.values()), schedule=s, lifetimes=lt, registers=regs,
                                  fu_binding={k: [sorted(g, key=lambda o: s[o]) for g in v] for k, v in fus.items()})
        (ROOT / "rtl" / "study" / f"sobel_fsmd_{pname}.sv").write_text(gen_fsmd(pname, ops, s, regs, fus))
        # compatibility graph of the ADD-class operations (edge = different control steps)
        L = ["graph C {", "layout=circo; node [shape=circle, fontsize=9, width=0.5, fixedsize=true, style=filled];"]
        colors = ["lightblue", "palegreen", "khaki", "pink"]
        for i, g in enumerate(fus["ADD"]):
            for o in g: L.append(f'"{o}" [fillcolor={colors[i % 4]}, label="{o}\\n@{s[o]}"];')
        for i, a in enumerate(addops):
            for b in addops[i + 1:]:
                if s[a] != s[b] and len(addops) <= 15: L.append(f'"{a}" -- "{b}" [color=gray70];')
        L.append("}")
        (OUT / f"compat_{pname}.dot").write_text("\n".join(L) + "\n")
    res["ilp"] = {}
    for lam_i in range(lam, 17):
        r = ilp_min_units(ops, lam_i)
        if r: res["ilp"][lam_i] = r[0]
    dot_dfg(ops, A, OUT / "dfg_final.dot", "")
    for d in OUT.glob("*.dot"):
        subprocess.run(["dot" if "dfg" in d.name else "circo", "-Tpdf", str(d), "-o", str(d.with_suffix(".pdf"))], check=False)
    (OUT / "hls_results.json").write_text(json.dumps(res, indent=1) + "\n")
    # console summary
    for v in res["versions"]: print(f"{v['name']:55s} MUL={v['mul']:2d} ADD={v['add']:2d} ABS={v['abs']} crit={v['critical']}")
    print("latency bound", lam, "ASAP units", res["asap_max_units"])
    for n, d in res["asap_alap"].items(): print(f"  {n:8s} {d['type']} asap={d['asap']} alap={d['alap']} mob={d['mobility']}  {d['text']}")
    for p, d in res["list"].items():
        print(p, "latency", d["latency"], "regs", len(d["registers"]), d["registers"])
        print("   ADD binding", d["fu_binding"]["ADD"])
    print("ILP min units per latency:", res["ilp"])


if __name__ == "__main__":
    main()
