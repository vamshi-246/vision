#!/usr/bin/env python3
"""Unit-6 BDD study with the `dd` ROBDD package (build/venv).

 1. Variable ordering: the Sobel direction comparator c0 = (32*|Gy| <= 13*|Gx|) on the real 11-bit operands
    (22 BDD variables), built bit-level with ripple-carry adders: node counts for three orderings
    (interleaved MSB-first, interleaved LSB-first, blocked) and after Rudell sifting started from the worst one.
    Also the 12-input NMS-select function (sector bits first vs. comparator bits first, and sifting).
 2. Equivalence checking of the NMS-select block: specification truth table  vs  our QM/UCP cover  vs  ESPRESSO
    cover  vs  the RTL (dir_decide.sv + selection mux) mapped by Yosys+ABC to AND/NOT gates (read back from BLIF).
    Equal functions give the same ROBDD node (canonicity), so the check is a pointer comparison.
 3. Symbolic reachability of the controller RTL (rtl/otsu_ctrl.sv via Yosys -> BLIF next-state functions):
    R0 = reset state, R_{k+1} = R_k | Img(R_k), image by existential quantification of present state and inputs.
Outputs build/bdd/bdd_study.json.
"""
import json, os, re, subprocess, sys
if os.environ.get("PYTHONHASHSEED") != "0":            # dd sifting visits variables in hash order: fix it
    os.environ["PYTHONHASHSEED"] = "0"; os.execv(sys.executable, [sys.executable] + sys.argv)
from pathlib import Path
from dd import autoref as _bdd
_bdd.Function.__xor__ = lambda a, b: a.bdd.apply("xor", a, b)   # dd 0.6 has no ^ operator

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "build/bdd"; OUT.mkdir(parents=True, exist_ok=True)
sys.path.insert(0, str(ROOT / "logic"))
import logic_study as L

N = 11


# --------------------------- bit-vector helpers ---------------------------------------------------
def add(bdd, a, b):
    """Ripple-carry add of two little-endian vectors (lists of BDD nodes); result has len max+1."""
    n = max(len(a), len(b)); a = a + [bdd.false] * (n - len(a)); b = b + [bdd.false] * (n - len(b))
    out, c = [], bdd.false
    for x, y in zip(a, b):
        out.append(x ^ y ^ c); c = (x & y) | (c & (x ^ y))
    return out + [c]


def shl(bdd, a, k): return [bdd.false] * k + a


def le(bdd, a, b):
    """a <= b (unsigned, little-endian)."""
    n = max(len(a), len(b)); a = a + [bdd.false] * (n - len(a)); b = b + [bdd.false] * (n - len(b))
    lt, eq = bdd.false, bdd.true
    for x, y in reversed(list(zip(a, b))):          # MSB first
        lt = lt | (eq & ~x & y); eq = eq & ~(x ^ y)
    return lt | eq


def comparator(order):
    bdd = _bdd.BDD(); bdd.declare(*order)
    ax = [bdd.var(f"ax{i}") for i in range(N)]; ay = [bdd.var(f"ay{i}") for i in range(N)]
    thirteen = add(bdd, add(bdd, shl(bdd, ax, 3), shl(bdd, ax, 2)), ax)
    f = le(bdd, shl(bdd, ay, 5), thirteen)
    bdd.collect_garbage()
    return bdd, f


def ordering_study():
    inter_msb = [v for i in reversed(range(N)) for v in (f"ax{i}", f"ay{i}")]
    inter_lsb = [v for i in range(N) for v in (f"ax{i}", f"ay{i}")]
    blocked = [f"ax{i}" for i in reversed(range(N))] + [f"ay{i}" for i in reversed(range(N))]
    res = {}
    for name, order in [("interleaved, MSB first", inter_msb), ("interleaved, LSB first", inter_lsb), ("blocked (all |Gx| bits, then |Gy|)", blocked)]:
        bdd, f = comparator(order)
        res[name] = len(f)
    bdd, f = comparator(blocked)
    _bdd.reorder(bdd)                                 # Rudell sifting
    res["blocked, after sifting"] = len(f)
    res["sifted order"] = [bdd.var_at_level(i) for i in range(len(bdd.vars))]
    return res


# --------------------------- NMS select: equivalence --------------------------------------------
def cube_bdd(bdd, cube_text):
    f = bdd.true
    for lit in cube_text.split("&"):
        if lit == "1": continue
        f &= ~bdd.var(lit[1:]) if lit.startswith("~") else bdd.var(lit)
    return f


def blif_to_bdd(bdd, path, inputs):
    """Combinational BLIF (.names only) -> dict signal -> BDD."""
    sig = {i: bdd.var(i) for i in inputs}; sig["$true"] = bdd.true; sig["$false"] = bdd.false
    lines = path.read_text().replace("\\\n", " ").splitlines()
    i = 0
    while i < len(lines):
        l = lines[i].strip()
        if l.startswith(".names"):
            names = l.split()[1:]; ins, out = names[:-1], names[-1]; rows = []
            i += 1
            while i < len(lines) and lines[i].strip() and not lines[i].strip().startswith("."):
                rows.append(lines[i].split()); i += 1
            f = bdd.false
            for r in rows:
                if not ins: f = bdd.true if r[0] == "1" else f; continue
                c = bdd.true
                for ch, n in zip(r[0], ins):
                    if ch == "1": c &= sig[n]
                    elif ch == "0": c &= ~sig[n]
                f |= c
            sig[out] = f
            continue
        i += 1
    return sig


def nms_equivalence(two_level):
    names = L.NMS_IN
    res = {}
    for label, order in [("sector bits first", names), ("comparator bits first", names[4:] + names[:4])]:
        bdd = _bdd.BDD(); bdd.declare(*order)
        dcare = bdd.false; spec = bdd.false
        on, dc, n, _ = L.tables()["keep"]
        for m in dc: dcare |= bdd.cube({nm: bool((m >> (n - 1 - k)) & 1) for k, nm in enumerate(names)})
        for m in on: spec |= bdd.cube({nm: bool((m >> (n - 1 - k)) & 1) for k, nm in enumerate(names)})
        qm = bdd.false
        for c in two_level["keep"]["qm_ucp_cover"]: qm |= cube_bdd(bdd, c)
        esp = bdd.false
        res[label] = {"spec_nodes": len(spec), "qm_nodes": len(qm)}
        if label == "sector bits first":
            # Espresso cover
            p = subprocess.run([str(L.ESPRESSO), str(ROOT / "build/logic/keep.pla")], capture_output=True, text=True)
            for row in p.stdout.splitlines():
                if row and row[0] in "01-":
                    c = bdd.true
                    for ch, nm in zip(row.split()[0], names):
                        if ch == "1": c &= bdd.var(nm)
                        elif ch == "0": c &= ~bdd.var(nm)
                    esp |= c
            # RTL -> Yosys/ABC gate netlist -> BLIF
            blif = OUT / "nms_select_abc.blif"
            subprocess.run(["yosys", "-q", "-p", f"read_verilog \"{ROOT/'build/logic/nms_select.v'}\"; synth -top nms_select -flatten; abc -g AND; opt_clean; write_blif \"{blif}\""], check=True)
            rtl = blif_to_bdd(bdd, blif, names)["keep"]
            care = ~dcare
            res["equivalence"] = {
                "qm_vs_spec (care set)": (qm & care) == (spec & care),
                "espresso_vs_spec (care set)": (esp & care) == (spec & care),
                "rtl_abc_vs_spec (care set)": (rtl & care) == (spec & care),
                "rtl_abc_vs_qm (everywhere)": rtl == qm,
                "rtl_abc_vs_espresso (everywhere)": rtl == esp,
                "rtl_nodes": len(rtl), "espresso_nodes": len(esp)}
            _bdd.reorder(bdd)
            res["after sifting"] = {"qm_nodes": len(qm), "order": [bdd.var_at_level(i) for i in range(len(bdd.vars))]}
    return res


# --------------------------- controller reachability -------------------------------------------
def reachability():
    blif = OUT / "otsu_ctrl.blif"
    subprocess.run(["yosys", "-q", "-p", f"read_verilog -sv \"{ROOT/'rtl/otsu_ctrl.sv'}\"; hierarchy -top otsu_ctrl; proc; flatten; opt; techmap; opt; dffunmap; abc -g AND; opt_clean; write_blif \"{blif}\""], check=True)
    text = blif.read_text()
    latches = re.findall(r"^\.latch (\S+) (\S+)", text, re.M)          # (next-state signal, state bit)
    inputs = ["en", "sof", "eof", "odone", "cdone", "px", "ovr"]
    sbits = [q for _, q in latches]
    bdd = _bdd.BDD()
    cur = [s.replace("[", "_").replace("]", "") for s in sbits]; nxt = [c + "_n" for c in cur]
    bdd.declare(*inputs, "rst", *[v for pair in zip(cur, nxt) for v in pair])
    sig = {"rst": bdd.var("rst"), "$true": bdd.true, "$false": bdd.false}
    for i in inputs: sig[i] = bdd.var(i)
    for s, c in zip(sbits, cur): sig[s] = bdd.var(c)
    body = text.replace("\\\n", " ").splitlines(); i = 0
    while i < len(body):
        l = body[i].strip()
        if l.startswith(".names"):
            names = l.split()[1:]; ins, out = names[:-1], names[-1]; rows = []; i += 1
            while i < len(body) and body[i].strip() and not body[i].strip().startswith("."):
                rows.append(body[i].split()); i += 1
            f = bdd.false
            for r in rows:
                if not ins: f = bdd.true if r[0] == "1" else f; continue
                c = bdd.true
                for ch, n in zip(r[0], ins):
                    c = c & (sig[n] if ch == "1" else ~sig[n]) if ch in "01" else c
                f |= c
            sig[out] = f; continue
        i += 1
    T = bdd.true
    for (d, q), c, n in zip(latches, cur, nxt):
        T &= ~(bdd.var(n) ^ sig[d])
    T = bdd.let({"rst": False}, T)
    R = bdd.true
    for c in cur: R &= ~bdd.var(c)                    # reset state = 000 (INIT)
    iters = 0
    while True:
        img = bdd.exist(inputs + cur, R & T)
        img = bdd.let({n: bdd.var(c) for c, n in zip(cur, nxt)}, img)
        R2 = R | img; iters += 1
        if R2 == R: break
        R = R2
    count = int(bdd.count(R, nvars=len(cur)))
    states = sorted(int("".join("1" if a[c] else "0" for c in reversed(cur)), 2) for a in bdd.pick_iter(R, care_vars=cur))
    return {"state_bits": len(cur), "reachable_states": count, "codes": states, "image_iterations": iters, "T_nodes": len(T)}


def nusmv_reachable():
    smv = ROOT / "build/formal/otsu/rtl/rtl.smv"
    m = OUT / "reach.smv"
    body = smv.read_text() if smv.exists() else ""
    body = re.sub(r"^\s*VAR\n(\s+_en)", r"  IVAR\n\1", body, count=1, flags=re.M)   # back to IVAR inputs (state = register only)
    body = body.replace("_rst : unsigned word[1];", "", 1).replace("_rst", "0ub1_0")   # reset held low: constant
    m.write_text(body + "\nMODULE main\nVAR top : _otsu_ctrl;\nINIT top._state = 0ub3_000\n")
    r = subprocess.run([str(ROOT / "build/tools/NuSMV-2.6.0-Linux/bin/NuSMV"), "-r", str(m)], capture_output=True, text=True, stdin=subprocess.DEVNULL)
    mm = re.search(r"reachable states: (\S+)", r.stdout + r.stderr)
    return mm.group(1) if mm else (r.stdout + r.stderr)[-300:]


def main():
    two = json.loads((ROOT / "build/logic/logic_study.json").read_text())["two_level"]
    res = {"ordering_comparator_c0": ordering_study()}
    print("comparator:", {k: v for k, v in res["ordering_comparator_c0"].items() if k != "sifted order"})
    res["nms_select"] = nms_equivalence(two); print("nms:", res["nms_select"])
    res["reachability"] = reachability(); print("reach:", res["reachability"])
    res["nusmv_reachable"] = nusmv_reachable(); print("NuSMV reachable states:", res["nusmv_reachable"])
    (OUT / "bdd_study.json").write_text(json.dumps(res, indent=1) + "\n")


if __name__ == "__main__":
    main()
