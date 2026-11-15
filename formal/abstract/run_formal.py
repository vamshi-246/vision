#!/usr/bin/env python3
"""Run NuSMV on formal/ctrl_sync.smv and on deliberately broken copies (mutants); print a property x mutant matrix.
A property that is TRUE on the original and FALSE on a mutant is 'catching' that bug. A property that stays TRUE on
EVERY mutant would be suspect (possibly vacuous) and is reported."""
import os, re, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..")
F = HERE; os.makedirs(os.path.join(F, "mutants"), exist_ok=True)
NUSMV = os.path.join(ROOT, "build/tools/NuSMV-2.6.0-Linux/bin/NuSMV")
base = open(os.path.join(F, "ctrl_sync.smv")).read()

MUT = {
 "M1_y_never_wraps": ("y is not cleared at the end of the raster (frame wrap bug)",
    [("      st = RUN & last_x & last_y : 0;\n      st = RUN & last_x & y < 7 : y + 1;", "      st = RUN & last_x & y < 7 : y + 1;")]),
 "M2_frame_end_trap": ("absorbing state at the last cell: counters freeze, run_en/sof ignored (deadlock-like trap)",
    [("  next(st) := case\n", "  next(st) := case\n      st = RUN & last_x & last_y : RUN;\n"),
     ("  next(x) := case\n", "  next(x) := case\n      st = RUN & last_x & last_y : x;\n"),
     ("  next(y) := case\n", "  next(y) := case\n      st = RUN & last_x & last_y : y;\n")]),
 "M3_idle_keeps_x": ("abort does not clear the x counter (stale coordinate in IDLE)",
    [("      st = RUN & !run_en       : 0;\n      st = RUN & sof & !at_origin : 1;", "      st = RUN & sof & !at_origin : 1;")]),
 "M4_abort_ignored": ("run_en=0 is ignored while RUN (cannot return to idle)",
    [("      st = RUN & !run_en       : IDLE;\n", "")]),
 "M5_dead_state": ("transition relation has no successor for (RUN, last cell, run_en=0): a true deadlock",
    [("ASSIGN\n", "TRANS !(st = RUN & last_x & last_y & !run_en)\nASSIGN\n")]),
 "M6_x_wraps_to_1": ("x wraps to 1 instead of 0 (off-by-one at line end)",
    [("      st = RUN & last_x        : 0;", "      st = RUN & last_x        : 1;")]),
 "M7_line_too_long": ("line ends one pixel late (last_x compares with WT, not WT-1): counter exceeds its bound",
    [("  last_x := (x = WT - 1);", "  last_x := (x = WT);")]),
 "M8_frame_too_short": ("frame wraps one line early (y never reaches HT-1, frame end unreachable)",
    [("      st = RUN & last_x & last_y : 0;\n      st = RUN & last_x & y < 7 : y + 1;", "      st = RUN & last_x & y = HT - 2 : 0;\n      st = RUN & last_x & y < 7 : y + 1;")]),
}

def run(path):
    cmds = os.path.join(F, "mutants", "_cmds.txt")
    open(cmds, "w").write("go\ncheck_fsm\ncheck_ctlspec\nquit\n")
    r = subprocess.run([NUSMV, "-ctt", path], capture_output=True, text=True, timeout=300, stdin=subprocess.DEVNULL)
    out = r.stdout + r.stderr
    res = {}
    for m in re.finditer(r"-- specification (.*?)\s+is (true|false)", out):
        res[m.group(1).strip()] = (m.group(2) == "true")
    res["DF: transition relation total (no deadlock state)"] = ("No deadlock state exists" in out)
    return res, out

base_res, base_out = run(os.path.join(F, "ctrl_sync.smv"))
log = ["==== ORIGINAL formal/ctrl_sync.smv (NuSMV-A, NuSMV 2.6.0 engine) ====",
       "\n".join(l for l in base_out.splitlines() if not l.startswith("***") and l.strip()), ""]
props = list(base_res.keys())  # includes DF (check_fsm) as last column
matrix = {}
for name, (desc, edits) in MUT.items():
    s = base
    for old, new in edits:
        assert old in s, (name, old[:40])
        s = s.replace(old, new, 1)
    p = os.path.join(F, "mutants", name + ".smv")
    open(p, "w").write(f"-- MUTANT {name}: {desc}\n" + s)
    res, out = run(p)
    matrix[name] = res
    log.append(f"==== MUTANT {name}: {desc} ====")
    log.append("\n".join(l for l in out.splitlines() if (l.startswith("-- specification") or "deadlock" in l.lower() or "total" in l.lower())))
    log.append("")
short = {p: f"P{i+1}" for i, p in enumerate(props)}
log.append("==== SUMMARY  (T = property TRUE, F = FALSE i.e. bug caught) ====")
log.append("property legend:")
for p in props: log.append(f"  {short[p]}: {p}")
log.append("")
log.append(f"{'':22s}" + " ".join(f"{short[p]:>3s}" for p in props))
log.append(f"{'ORIGINAL':22s}" + " ".join(f"{'T' if base_res[p] else 'F':>3s}" for p in props))
ok = all(base_res.values())
for name in MUT:
    log.append(f"{name:22s}" + " ".join(f"{'T' if matrix[name].get(p, True) else 'F':>3s}" for p in props))
caught = {name: [short[p] for p in props if not matrix[name].get(p, True)] for name in MUT}
never = [short[p] for p in props if all(matrix[n].get(p, True) for n in MUT)]
log.append("")
log.append(f"original: all {len(props)} properties TRUE = {ok}")
for n, c in caught.items(): log.append(f"{n}: caught by {c if c else 'NOTHING (!)'}")
log.append(f"properties that stayed TRUE on every mutant (not exercised by any mutant): {never if never else 'none'}")
txt = "\n".join(log)
open(os.path.join(HERE, "formal_results.log"), "w").write(txt + "\n")
print(txt)
