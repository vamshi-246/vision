#!/usr/bin/env python3
"""Quality of OURS / PAPER / BASELINE, every number measured here.

  OURS     : model/golden.py (bit-identical to the RTL, see core_regression) at the stated thresholds.
  PAPER    : the paper RTL (rtl/study/paper) simulated in Icarus on the same NMS stream; its REAL class output is scored.
  BASELINE : plain Sobel |Gx|+|Gy| >= T on the unsmoothed gray image (no Gaussian, no NMS).
Reference maps: (a) the project golden model's own edge map (strong+weak, thresholds 64/192) and
(b) scikit-image Canny(sigma=1, 0.1/0.2) as an independent external reference.
Metrics: PSNR of binary maps (peak 1), exact F1, and F1 with 1-pixel tolerance.
"""
import json, subprocess, sys
from pathlib import Path
import numpy as np
from scipy.ndimage import binary_dilation
from skimage.feature import canny
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from model.golden import Config, edge_frame, write_hex
IMGS = ["camera", "astronaut", "coins", "coffee", "chelsea", "rocket"]
S3 = np.ones((3, 3), bool)
OUT = ROOT / "build/paper"; OUT.mkdir(parents=True, exist_ok=True)

def metrics(det, gt):
    det = det.astype(bool); gt = gt.astype(bool)
    mse = np.mean(det != gt); psnr = 10*np.log10(1/mse) if mse > 0 else float("inf")
    tp = (det & gt).sum(); p = tp/max(det.sum(), 1); r = tp/max(gt.sum(), 1); f1 = 2*p*r/max(p+r, 1e-12)
    pt = (det & binary_dilation(gt, S3)).sum()/max(det.sum(), 1); rt = (gt & binary_dilation(det, S3)).sum()/max(gt.sum(), 1)
    return dict(psnr=float(psnr), f1=float(f1), f1_tol1=float(2*pt*rt/max(pt+rt, 1e-12)), edges=int(det.sum()))

def run_paper(name):
    cls_file = OUT / f"{name}_cls.txt"
    exe = OUT / f"paper_{name}.vvp"
    srcs = [f"rtl/study/paper/{f}.sv" for f in ("paper_frame_buffer", "paper_histogram", "paper_otsu_logunit", "paper_classify", "paper_top")]
    subprocess.run(["iverilog", "-g2012", "-Wno-timescale", f"-Ptb_paper_quality.IMG=\"{name}\"", "-o", str(exe), *srcs, "tb/study/tb_paper_quality.sv"], cwd=ROOT, check=True)
    p = subprocess.run(["vvp", "-n", str(exe)], cwd=ROOT, capture_output=True, text=True)
    line = next(l for l in p.stdout.splitlines() if l.startswith("PAPER_RESULT"))
    if "TIMEOUT" in line: raise RuntimeError(line)
    cls = np.array([int(x) for x in cls_file.read_text().split()], np.uint8)
    assert cls.size == 640*480, cls.size
    return cls.reshape(480, 640), line

def main():
    detail = {}
    for name in IMGS:
        g = np.load(ROOT / "model/corpus" / f"{name}.npz")["gray"]
        r = edge_frame(g, Config(thr_lo=64, thr_hi=192))
        write_hex(OUT / f"{name}_nms.hex", r["nms"], 3)
        pc, line = run_paper(name); print(line, flush=True)
        gt_canny = canny(g.astype(float)/255, sigma=1.0, low_threshold=0.1, high_threshold=0.2)
        gt_gold = r["cls"] >= 1
        # baseline: plain Sobel on raw gray
        gm = edge_frame(g, Config(thr_lo=0, thr_hi=0))   # only used for the shared sobel helper below
        from model.golden import sobel_frame
        gx, gy, _ = sobel_frame(g, 0, Config())
        bmag = np.abs(gx.astype(np.int32)) + np.abs(gy.astype(np.int32)); base = bmag >= 192
        maps = {"ours_strong_192": r["cls"] == 2, "ours_strong_weak_64_192": r["cls"] >= 1,
                "paper_strong": pc == 2, "paper_strong_weak": pc >= 1, "baseline_sobel_192": base}
        detail[name] = {"paper_line": line, "canny_edges": int(gt_canny.sum()), "golden_edges_sw": int(gt_gold.sum()),
                        "vs_canny": {k: metrics(v, gt_canny) for k, v in maps.items()},
                        "vs_golden": {k: metrics(v, gt_gold) for k, v in maps.items()}}
    (OUT / "quality_detail.json").write_text(json.dumps(detail, indent=1) + "\n")
    for ref in ("vs_canny", "vs_golden"):
        print(f"\n## mean over {len(IMGS)} images, reference = {ref}")
        print("| design/map | mean PSNR dB | mean F1 | mean F1 (1px tol) | mean edge px |\n|---|---|---|---|---|")
        for k in detail[IMGS[0]][ref]:
            m = lambda f: np.mean([detail[i][ref][k][f] for i in IMGS])
            print(f"| {k} | {m('psnr'):.2f} | {m('f1'):.3f} | {m('f1_tol1'):.3f} | {m('edges'):.0f} |")
if __name__ == "__main__": main()
