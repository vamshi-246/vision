#!/usr/bin/env python3
"""Verify the streaming adaptive-Otsu design (rtl/study/edge_pipeline_otsu.sv) against the paper's whole-frame engine.
Cases: the 6 natural corpus images at 640x480 with VESA-like blanking (thresholds must apply from frame 1), the same
at 64x48 with blanking, without blanking (result waits one frame: applies from frame 2), and a 16x12 stream whose frames
are shorter than one Otsu sweep (overrun: never applies, never changes thresholds mid-frame)."""
import json, subprocess, sys
from pathlib import Path
import numpy as np
from PIL import Image
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "build/otsu"; OUT.mkdir(parents=True, exist_ok=True)
SRC = ["rtl/linebuf.sv", "rtl/gauss.sv", "rtl/dir_decide.sv", "rtl/sobel.sv", "rtl/dirnms.sv", "rtl/classify_hist.sv",
       *[f"rtl/study/paper/{f}.sv" for f in ("paper_frame_buffer", "paper_histogram", "paper_otsu_logunit", "paper_classify", "paper_top")],
       "rtl/otsu_ctrl.sv", "rtl/otsu_stream.sv", "rtl/study/edge_pipeline_otsu.sv", "tb/study/tb_otsu_stream.sv"]
IMGS = ["camera", "astronaut", "coins", "coffee", "chelsea", "rocket"]

def build(w, h, frames, hb, vb):
    exe = OUT / f"sim_{w}x{h}_{frames}_{hb}_{vb}.vvp"
    p = subprocess.run(["iverilog", "-g2012", "-Wno-timescale", "-s", "tb_otsu_stream", f"-Ptb_otsu_stream.W={w}", f"-Ptb_otsu_stream.H={h}",
                        f"-Ptb_otsu_stream.FRAMES={frames}", f"-Ptb_otsu_stream.HB={hb}", f"-Ptb_otsu_stream.VB={vb}", "-o", str(exe), *SRC],
                       cwd=ROOT, capture_output=True, text=True)
    if p.returncode: sys.exit(p.stdout[-3000:] + p.stderr[-3000:])
    return exe

def img_hex(name, w, h):
    g = np.load(ROOT / "model/corpus" / f"{name}.npz")["gray"]
    if g.shape != (h, w): g = np.asarray(Image.fromarray(g).resize((w, h), Image.BILINEAR))
    f = OUT / f"{name}_{w}x{h}.hex"; f.write_text("".join(f"{v:02x}\n" for v in g.ravel())); return f

def run(exe, img, *extra):
    p = subprocess.run(["vvp", "-n", str(exe), f"+IMG={img}", *extra], cwd=ROOT, capture_output=True, text=True, timeout=3600)
    line = next((l for l in p.stdout.splitlines() if l.startswith(("PASS", "FAIL"))), p.stdout[-500:])
    print(line, flush=True); return line

def main():
    res = {}
    cases = [("640x480 blanking (VESA 160 clk/line, 45 lines)", 640, 480, 3, 160, 45 * 800, "1", IMGS),
             ("64x48 blanking", 64, 48, 3, 16, 1000, "1", IMGS),
             ("64x48 no blanking (result waits a frame)", 64, 48, 5, 0, 0, "2", IMGS[:3]),
             ("16x12 no blanking (frame shorter than a sweep)", 16, 12, 6, 0, 0, None, IMGS[:1])]
    for title, w, h, fr, hb, vb, exp, imgs in cases:
        exe = build(w, h, fr, hb, vb)
        res[title] = {n: run(exe, img_hex(n, w, h), *( [f"+EXPECT_APPLY={exp}"] if exp else ["+EXPECT_NONE"])) for n in imgs}
    (OUT / "otsu_stream_results.json").write_text(json.dumps(res, indent=1) + "\n")
    bad = [l for c in res.values() for l in c.values() if not l.startswith("PASS")]
    print("ALL PASS" if not bad else f"{len(bad)} FAILED"); sys.exit(1 if bad else 0)

if __name__ == "__main__": main()
