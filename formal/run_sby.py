#!/usr/bin/env python3
"""Run the SymbiYosys proofs (formal/sby/*.sby): BMC (depth 30) and unbounded proof by k-induction (depth 20).
SymbiYosys + Yosys-SMTBMC with the z3 solver.  Work directories go to a space-free scratch copy (sby/yosys dislike spaces)."""
import json, os, re, shutil, subprocess, sys, tempfile
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
SBY = ROOT / "build/tools/sby/bin/sby"
OUT = ROOT / "build/sby"; OUT.mkdir(parents=True, exist_ok=True)

def main():
    res = {}
    env = dict(os.environ, PATH=str(ROOT / "build/venv/bin") + os.pathsep + os.environ["PATH"])
    with tempfile.TemporaryDirectory(prefix="p7sby") as t:
        t = Path(t); (t / "formal/sby").mkdir(parents=True); (t / "rtl").mkdir()
        for f in (ROOT / "rtl").glob("*.sv"): shutil.copy2(f, t / "rtl" / f.name)
        for f in (ROOT / "formal/sby").glob("*"): shutil.copy2(f, t / "formal/sby" / f.name)
        for sby in sorted((t / "formal/sby").glob("*.sby")):
            for task in ("bmc", "prove"):
                p = subprocess.run([sys.executable, str(SBY), "-f", sby.name, task], cwd=sby.parent, capture_output=True, text=True, env=env, timeout=3600)
                log = p.stdout + p.stderr
                (OUT / f"{sby.stem}_{task}.log").write_text(log)
                status = re.search(r"DONE \((\w+), rc=", log)
                ind = re.search(r"Induction step proven: \S+ ?(?:step )?(\d+)?|engine_0.*induction.*(\d+)", log)
                steps = re.findall(r"summary: engine_\d+ \(.*?\) returned (\w+) for (\w+)", log)
                res[f"{sby.stem}/{task}"] = dict(status=status.group(1) if status else "ERROR", engine=steps,
                                                 asserts=len(re.findall(r"assert ?\(", (ROOT / f"formal/sby/props_{sby.stem}.sv").read_text())))
                print(sby.stem, task, res[f"{sby.stem}/{task}"], flush=True)
                if not status: print(log[-1500:])
    (OUT / "sby_results.json").write_text(json.dumps(res, indent=1) + "\n")

if __name__ == "__main__": main()
