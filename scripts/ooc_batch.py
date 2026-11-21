#!/usr/bin/env python3
"""Run the shared OOC Vivado flow (scripts/ooc_measure.tcl) on a list of designs, in parallel, and write JSON.
usage: ooc_batch.py <job-file.json> <result.json> [parallel]
job file: {"name": {"top": ..., "files": [...], "period": ns, "impl": true, "generics": ""}, ...}"""
import json, os, re, subprocess, sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
VIVADO = os.environ.get("VIVADO", "/tools/Xilinx/Vivado/2024.2/bin/vivado")
sys.path.insert(0, str(ROOT / "scripts"))
from compare_resources import util

def run(item):
    name, j = item
    out = ROOT / "build" / "ooc" / re.sub(r"\W", "_", name); out.mkdir(parents=True, exist_ok=True)
    (out / "clk.xdc").write_text(f"create_clock -name clk -period {j['period']} [get_ports clk]\n")
    env = dict(os.environ, P7_ROOT=str(ROOT), P7_TOP=j["top"], P7_FILES=" ".join(j["files"]), P7_OUT=str(out),
               P7_PERIOD=str(j["period"]), P7_IMPL="1" if j.get("impl", True) else "0", P7_GENERICS=j.get("generics", ""))
    subprocess.run([VIVADO, "-mode", "batch", "-source", str(ROOT / "scripts/ooc_measure.tcl"), "-log", str(out / "vivado.log"),
                    "-journal", str(out / "vivado.jou")], env=env, capture_output=True, text=True)
    log = (out / "vivado.log").read_text()
    r = re.search(r"RESULT top=\S+ period=\S+ WNS=(-?[0-9.]+) WHS=(-?[0-9.]+)", log)
    rpt = out / ("impl_utilization.rpt" if j.get("impl", True) else "synth_utilization.rpt")
    if not rpt.exists():
        return name, {"error": [l for l in log.splitlines() if l.startswith("ERROR")][:3]}
    d = util(rpt); d.update(period=j["period"])
    if r:
        wns = float(r.group(1)); d.update(wns=wns, whs=float(r.group(2)), path_ns=round(j["period"] - wns, 3), fmax_mhz=round(1000 / (j["period"] - wns), 1))
    print(name, d, flush=True)
    return name, d

if __name__ == "__main__":
    jobs = json.loads(Path(sys.argv[1]).read_text())
    par = int(sys.argv[3]) if len(sys.argv) > 3 else 3
    with ThreadPoolExecutor(par) as ex: res = dict(ex.map(run, jobs.items()))
    Path(sys.argv[2]).write_text(json.dumps(res, indent=1) + "\n")
