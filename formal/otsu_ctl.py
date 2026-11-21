#!/usr/bin/env python3
"""CTL model checking of the adaptive-threshold controller RTL (rtl/otsu_ctrl.sv) with NuSMV 2.6, incl. fairness.

RTL -> Yosys write_smv.  Yosys emits the module inputs as IVARs; here they are turned into unconstrained state VARs
(a free input chosen anew in every state) so that Mealy outputs and FAIRNESS constraints can be expressed.
rst is held low (INVAR) and the reset state INIT is the initial state.  Each property runs in its own NuSMV call,
once without and (for liveness) once with fairness assumptions on the environment:
  FAIRNESS odone  - the Otsu sweep eventually finishes;  FAIRNESS cdone - a clear pass eventually ends;
  FAIRNESS eof    - frames keep ending;  FAIRNESS en & sof - adaptive mode is on when some frame starts.
Two bugs are injected into the RTL; their counterexamples are saved (build/formal/otsu/*.cex) and replayed in
simulation by scripts/otsu_stream_check.py --mutant.
"""
import json, re, subprocess, sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
NUSMV = ROOT / "build/tools/NuSMV-2.6.0-Linux/bin/NuSMV"
OUT = ROOT / "build/formal/otsu"; OUT.mkdir(parents=True, exist_ok=True)
S = {n: f"0ub3_{v:03b}" for n, v in dict(INIT=0, ARM=1, COLLECT=2, SWEEP=3, CLEAR=4, PEND=5).items()}
st = lambda n: f"top._state = {S[n]}"
b = lambda s: f"bool(top._{s})"
FAIR = ["bool(top._odone)", "bool(top._cdone)", "bool(top._eof)", "(bool(top._en) & bool(top._sof))"]

PROPS = [  # (id, type, CTL, needs-fairness?)
 ("P1", "Safety", f"AG !({b('clr_both')} & {b('count_en')})", False),
 ("P2", "Safety", f"AG !({b('clr_both')} & {b('clr_one')})", False),
 ("P3", "Safety (frame-aligned update)", f"AG ({b('apply')} -> (({st('PEND')}) & {b('eof')}) | (({st('CLEAR')}) & !{b('px')}))", False),
 ("P4", "Safety", f"AG ({b('swap')} -> AX {st('SWEEP')})", False),
 ("P5", "Safety (legal states)", "AG (top._state <= 0ub3_101)", False),
 ("P6", "Reachability", f"EF ({st('PEND')} & {b('apply')})", False),
 ("P7", "Non-blocking (reset reachable)", f"AG EF {st('INIT')}", False),
 ("P8", "Liveness, no fairness", f"AG ({st('SWEEP')} -> AF {st('CLEAR')})", False),
 ("P9", "Liveness, fair", f"AG ({st('SWEEP')} -> AF {st('CLEAR')})", True),
 ("P10", "Liveness, fair (every swap ends in a threshold update or a re-arm)", f"AG ({b('swap')} -> AX AF ({b('apply')} | {st('INIT')}))", True),
 ("P11", "Until, fair (counting continues while the sweep runs)", f"AG ({st('SWEEP')} -> A[{b('count_en')} U {st('CLEAR')}])", True),
 ("P12", "Liveness, fair (a frame is always being collected or a result is pending)", f"AG AF ({st('COLLECT')} | {st('PEND')})", True),
]

MUTANTS = {
 "B1 apply even if the next frame has started": ("else if (px) next = C_PEND;\n          else begin next = C_COLLECT; apply = 1'b1; end",
                                                 "else begin next = C_COLLECT; apply = 1'b1; end"),
 "B2 CLEAR waits for odone as well (stuck)": ("C_CLEAR: begin\n        count_en = 1'b1; clr_one = 1'b1;\n        if (cdone) begin",
                                              "C_CLEAR: begin\n        count_en = 1'b1; clr_one = 1'b1;\n        if (cdone && odone) begin"),
}


def export(src, d):
    d.mkdir(parents=True, exist_ok=True)
    (d / "otsu_ctrl.sv").write_text(src)
    subprocess.run(["yosys", "-q", "-p", f"read_verilog -sv \"{d/'otsu_ctrl.sv'}\"; hierarchy -top otsu_ctrl; proc; flatten; opt -fast; dffunmap; write_smv \"{d/'rtl.smv'}\""], check=True)
    return (d / "rtl.smv").read_text().replace("  IVAR\n", "  VAR\n", 1)


def check(body, d, i, spec, fair):
    m = d / f"p{i}{'_fair' if fair else ''}.smv"
    m.write_text(body + "\nMODULE main\nVAR top : _otsu_ctrl;\nINVAR top._rst = 0ub1_0\nINIT " + st("INIT") + "\n"
                 + "".join(f"FAIRNESS {f}\n" for f in (FAIR if fair else [])) + f"CTLSPEC {spec};\n")
    r = subprocess.run([str(NUSMV), "-ctt", str(m)], capture_output=True, text=True, timeout=300, stdin=subprocess.DEVNULL)
    out = r.stdout + r.stderr; (m.with_suffix(".log")).write_text(out)
    mm = re.search(r"-- specification .*? is (true|false)", out)
    if not mm: raise RuntimeError(out[-1500:])
    total = "No deadlock state exists" in out
    return mm.group(1) == "true", total, out


def trace(out):
    """Condensed counterexample: state and the inputs that are 1, per step."""
    steps, cur = [], {}
    for line in out.splitlines():
        if line.strip().startswith("-> State:") or "-- Loop starts here" in line:
            if cur: steps.append(cur)
            cur = {"loop": True} if "Loop" in line else {}
        m = re.match(r"\s+top\._(state|en|sof|eof|odone|cdone|px|ovr|apply|swap) = (\S+)", line)
        if m: cur[m.group(1)] = m.group(2)
    if cur: steps.append(cur)
    # carry values forward (NuSMV prints only changes)
    full, last = [], {}
    for s in steps:
        last = {**last, **{k: v for k, v in s.items() if k != "loop"}}; full.append(dict(last, loop=s.get("loop", False)))
    names = {v.replace("ub", "ud"): k for k, v in S.items()}; names.update({v: k for k, v in S.items()})
    names.update({f"0ud3_{i}": n for i, n in enumerate(["INIT", "ARM", "COLLECT", "SWEEP", "CLEAR", "PEND"])})
    return [f"{'[loop] ' if s['loop'] else ''}{names.get(s.get('state'), s.get('state'))} in={{" +
            ",".join(k for k in ("en", "sof", "eof", "odone", "cdone", "px", "ovr") if s.get(k, '').endswith("_1")) + "}" for s in full]


def main():
    src = (ROOT / "rtl/otsu_ctrl.sv").read_text()
    body = export(src, OUT / "rtl")
    res = {"properties": {}, "mutants": {}}
    for i, (pid, typ, spec, fair) in enumerate(PROPS):
        v, total, _ = check(body, OUT / "rtl", i, spec, fair)
        res["properties"][pid] = dict(type=typ, ctl=spec, fairness=fair, result=v)
        res["deadlock_free"] = total
        print(f"{pid:4s} {'TRUE ' if v else 'FALSE'} {'(fair) ' if fair else ''}{typ}")
    for name, (old, new) in MUTANTS.items():
        assert old in src, name
        mb = export(src.replace(old, new, 1), OUT / name.split()[0])
        caught = {}
        for i, (pid, typ, spec, fair) in enumerate(PROPS):
            v, _, out = check(mb, OUT / name.split()[0], i, spec, fair)
            if v != res["properties"][pid]["result"]:
                caught[pid] = trace(out)
        res["mutants"][name] = caught
        first = next(iter(caught.items()), None)
        print(f"mutant {name}: properties now failing {list(caught)}")
        if first: print("   counterexample", first[0], ":", " -> ".join(first[1][:12]))
        (OUT / f"{name.split()[0]}.cex").write_text(json.dumps(caught, indent=1))
    res["replay"] = replay(src)
    (OUT / "otsu_ctl_results.json").write_text(json.dumps(res, indent=1) + "\n")


def replay(src):
    """Replay each counterexample scenario in simulation: the mutated controller inside the full enhanced pipeline
    (tb/study/tb_otsu_stream.sv), with the stream conditions the counterexample needs."""
    sys.path.insert(0, str(ROOT / "scripts")); import otsu_stream_check as o
    cases = {"B1": (64, 48, 5, 0, 0, "+EXPECT_APPLY=2"),        # no blanking -> px is set when the sweep ends
             "B2": (64, 48, 3, 16, 1000, "+EXPECT_APPLY=1")}   # blanking -> CLEAR must end for the threshold to apply
    out = {}
    for name, (old, new) in MUTANTS.items():
        key = name.split()[0]; w, h, fr, hb, vb, exp = cases[key]
        mdir = OUT / f"replay_{key}"; mdir.mkdir(exist_ok=True)
        (mdir / "otsu_ctrl.sv").write_text(src.replace(old, new, 1))
        srcs = [s if s != "rtl/otsu_ctrl.sv" else str(mdir / "otsu_ctrl.sv") for s in o.SRC]
        exe = mdir / "sim.vvp"
        subprocess.run(["iverilog", "-g2012", "-Wno-timescale", "-s", "tb_otsu_stream", f"-Ptb_otsu_stream.W={w}", f"-Ptb_otsu_stream.H={h}",
                        f"-Ptb_otsu_stream.FRAMES={fr}", f"-Ptb_otsu_stream.HB={hb}", f"-Ptb_otsu_stream.VB={vb}", "-o", str(exe), *srcs], cwd=ROOT, check=True)
        r = subprocess.run(["vvp", "-n", str(exe), f"+IMG={o.img_hex('camera', w, h)}", exp], cwd=ROOT, capture_output=True, text=True)
        lines = [l for l in r.stdout.splitlines() if l.startswith(("ERROR", "FAIL", "PASS", "CLASS"))][:3]
        out[key] = lines; print(f"replay {key}:", lines)
    return out


if __name__ == "__main__":
    main()
