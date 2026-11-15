#!/usr/bin/env python3
"""Run the same Vivado OOC flow on every design in the 3-way comparison and tabulate the results."""
import json, os, re, subprocess, sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
VIVADO = os.environ.get("VIVADO", "/tools/Xilinx/Vivado/2024.2/bin/vivado")
G = Path(os.environ.get("P7_GROUPMATE", ROOT / "study" / "groupmate"))

def designs():
    ours = ["rtl/linebuf.sv", "rtl/gauss.sv", "rtl/dir_decide.sv", "rtl/sobel.sv", "rtl/dirnms.sv", "rtl/classify_hist.sv", "rtl/top.sv"]
    paper = [f"rtl/study/paper/{f}.sv" for f in ("paper_frame_buffer", "paper_histogram", "paper_otsu_logunit", "paper_classify", "paper_top")]
    gm = [f"rtl/{f}.sv" for f in "ctrl_sync tag_center linebuf gauss sobel dirnms classify rgb2gray apb_regs delay_ram core_top".split()]
    # name: (root, top, files, implement?, generics)
    return {
     "OURS (edge_pipeline, shipped core)": (ROOT, "edge_pipeline", ours, True, ""),
     "BASELINE (plain Sobel + 1 threshold)": (ROOT, "baseline_top", ["rtl/linebuf.sv", "rtl/dir_decide.sv", "rtl/sobel.sv", "rtl/study/baseline_top.sv"], True, ""),
     "PAPER system (our front end + paper engine)": (ROOT, "paper_system", [f for f in ours if "classify_hist" not in f and "top.sv" not in f] + paper + ["rtl/study/paper_system.sv"], False, ""),
     "PAPER engine alone (640x480)": (ROOT, "paper_top", paper, False, "-generic W=640 -generic H=480"),
     "GROUP-MATE core_top (his RTL)": (G, "core_top", gm, True, ""),
    }

def util(rpt):
    t = Path(rpt).read_text()
    def g(pat):
        m = re.search(pat, t); return float(m.group(1)) if m else 0
    return dict(lut=g(r"\| Slice LUTs\*?\s+\|\s+(\d+)"), ff=g(r"\| Slice Registers\s+\|\s+(\d+)"),
                ramb36=g(r"\|\s*RAMB36/FIFO\*\s+\|\s+(\d+)"), ramb18=g(r"\|\s*RAMB18\s+\|\s+(\d+)"),
                bram_tiles=g(r"\| Block RAM Tile\s+\|\s+([\d.]+)"), dsp=g(r"\|\s*DSPs\s+\|\s+(\d+)"))

def main(period=10.0):
    res = {}
    for name, (root, top, files, impl, generics) in designs().items():
        out = ROOT / "build" / "ooc" / re.sub(r"\W", "_", name); out.mkdir(parents=True, exist_ok=True)
        (out / "clk.xdc").write_text(f"create_clock -name clk -period {period} [get_ports clk]\n")
        env = dict(os.environ, P7_ROOT=str(root), P7_TOP=top, P7_FILES=" ".join(files), P7_OUT=str(out), P7_PERIOD=str(period), P7_IMPL="1" if impl else "0", P7_GENERICS=generics)
        p = subprocess.run([VIVADO, "-mode", "batch", "-source", str(ROOT / "scripts/ooc_measure.tcl"), "-log", str(out / "vivado.log"), "-journal", str(out / "vivado.jou")],
                           env=env, capture_output=True, text=True)
        log = (out / "vivado.log").read_text()
        r = re.search(r"RESULT top=\S+ period=\S+ WNS=(-?[0-9.]+) WHS=(-?[0-9.]+)", log)
        rpt = out / ("impl_utilization.rpt" if impl else "synth_utilization.rpt")
        if not rpt.exists():
            print(name, "FAILED:", [l for l in log.splitlines() if l.startswith("ERROR")][:3]); continue
        d = util(rpt); d.update(wns=float(r.group(1)) if r else None, whs=float(r.group(2)) if r else None, period=period)
        res[name] = d; print(name, d, flush=True)
    (ROOT / "build/ooc/results.json").write_text(json.dumps(res, indent=2) + "\n")
if __name__ == "__main__": main()
