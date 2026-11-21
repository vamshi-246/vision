#!/usr/bin/env python3
"""Core regression with the SVA bind file (tb/sva/core_sva.sv) and Verilator line/toggle/assertion coverage.
Uses the vectors written by scripts/core_regression.py (build/core_regression/<WxH>).  Also runs one mutant
(classifier emits the illegal code 2'b11 for strong pixels) to show that the assertions are not vacuous."""
import json, re, shutil, subprocess, sys, tempfile
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "build/sva"; OUT.mkdir(parents=True, exist_ok=True)
MAIN = "tb/sva/cov_main.cpp"
SRC = [f"rtl/{s}.sv" for s in ("linebuf", "gauss", "dir_decide", "sobel", "dirnms", "classify_hist", "top")] + ["tb/sva/core_sva.sv", "tb/system/tb_core_regression.sv"]

def build(w, h, frames, tag, mutate=None, cov=True):
    exe = OUT / f"sim_{tag}"
    with tempfile.TemporaryDirectory(prefix="p7-sva-") as t:
        t = Path(t)
        for s in SRC + [MAIN]: (t / s).parent.mkdir(parents=True, exist_ok=True); shutil.copy2(ROOT / s, t / s)
        for f, a, b in (mutate or []):
            p = t / f; txt = p.read_text(); assert a in txt; p.write_text(txt.replace(a, b, 1))
        cmd = ["verilator", "--binary", "--timing", "--assert", "-j", "4", "-Wno-fatal", "-Wno-lint", "-Wno-style",
               "--top-module", "tb_core_regression", f"-GW={w}", f"-GH={h}", f"-GFRAMES={frames}", "--Mdir", "obj", *SRC]
        if cov: cmd = ["verilator", "--cc", "--exe", "--build", "--timing", "--assert", "-j", "4", "--coverage-line", "--coverage-toggle", "--coverage-user", "-Wno-fatal", "-Wno-lint", "-Wno-style",
                       "--top-module", "tb_core_regression", f"-GW={w}", f"-GH={h}", f"-GFRAMES={frames}", "--Mdir", "obj", MAIN, *SRC]
        p = subprocess.run(cmd, cwd=t, capture_output=True, text=True)
        if p.returncode: sys.exit(p.stdout[-4000:] + p.stderr[-4000:])
        shutil.copy2(t / "obj/Vtb_core_regression", exe)
    return exe

def main():
    res = {}
    base = ROOT / "build/core_regression/31x23"
    frames = json.loads((base / "manifest.json").read_text())["frames"]
    exe = build(31, 23, len(frames), "31x23")
    datfiles = []
    for mode in (0, 1, 2):
        run_dir = OUT / f"run_m{mode}"; shutil.rmtree(run_dir, ignore_errors=True); run_dir.mkdir()
        p = subprocess.run([str(exe), f"+BASE={base}", f"+MODE={mode}"], cwd=run_dir, capture_output=True, text=True, timeout=1800)
        dat = run_dir / "coverage.dat"
        line = next((l for l in p.stdout.splitlines() if l.startswith("PASS core")), p.stdout[-800:] + p.stderr[-800:])
        res[f"31x23 mode{mode}"] = line; print(line, flush=True); datfiles.append(str(dat))
    # merged coverage, per type, restricted to the RTL (testbench excluded)
    merged = OUT / "cov_merged.dat"
    subprocess.run(["verilator_coverage", "--write", str(merged), *datfiles], check=True, capture_output=True)
    ann = OUT / "annotated"; shutil.rmtree(ann, ignore_errors=True)
    subprocess.run(["verilator_coverage", "--annotate", str(ann), "--annotate-all", str(merged)], capture_output=True, text=True)
    cov = {}
    for f in sorted(ann.glob("*.sv")):
        if "tb_" in f.name or "sva" in f.name: continue
        txt = f.read_text().splitlines()
        hit = sum(1 for l in txt if re.match(r"^ [ 0-9]{5,}\s", l) and not l.lstrip().startswith("%"))
        miss = sum(1 for l in txt if l.startswith("%0"))
        tot_pts = [int(m.group(1)) for l in txt for m in [re.match(r"^[ %](\d{6})", l)] if m]
        covered = sum(1 for v in tot_pts if v > 0)
        cov[f.name] = dict(points=len(tot_pts), covered=covered, pct=round(100 * covered / max(len(tot_pts), 1), 1))
    allp = sum(v["points"] for v in cov.values()); allc = sum(v["covered"] for v in cov.values())
    covers = {}
    for d in datfiles:
        for m in re.finditer(r"o\x02(c_\w+)\x01.*?' (\d+)", Path(d).read_text(errors="replace")):
            covers[m.group(1)] = covers.get(m.group(1), 0) + int(m.group(2))
    res["cover_hits"] = covers; print("cover hits:", covers)
    res["coverage_by_file"] = cov; res["coverage_total_pct"] = round(100 * allc / max(allp, 1), 1)
    # assertion sanity: a mutant must fail an assertion
    mexe = build(31, 23, len(frames), "31x23_mut", [("rtl/classify_hist.sv", "cls <= 2'b10;", "cls <= 2'b11;"),
        ("tb/system/tb_core_regression.sv", '$fatal(1,"Output f=', '$display("SCOREBOARD Output f=')], cov=False)
    p = subprocess.run([str(mexe), f"+BASE={base}", "+MODE=0"], capture_output=True, text=True, timeout=600)
    fail = [l for l in (p.stdout + p.stderr).splitlines() if "core_sva" in l or "a_cls" in l][:2]
    res["mutant_cls11"] = fail; print("mutant:", fail)
    (OUT / "sva_coverage.json").write_text(json.dumps(res, indent=1) + "\n")
    print(json.dumps(cov, indent=1)); print("total", res["coverage_total_pct"])

if __name__ == "__main__": main()
