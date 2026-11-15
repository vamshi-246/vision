#!/usr/bin/env python3
"""Independent check of the paper engine: exact (float) Otsu on the same 8-bit-saturated NMS histogram vs the RTL's log-domain threshold."""
import json, re, sys
from pathlib import Path
import numpy as np
ROOT = Path(__file__).resolve().parents[1]; sys.path.insert(0, str(ROOT))
from model.golden import Config, edge_frame

def otsu_exact(hist):
    p = hist.astype(np.float64); N = p.sum(); S = (np.arange(256) * p).sum()
    w0 = np.cumsum(p); s0 = np.cumsum(np.arange(256) * p)
    best, bk = -1.0, 0
    for k in range(255):                         # threshold between k and k+1 (class 0 = <= k)
        a, b = w0[k], N - w0[k]
        if a == 0 or b == 0: continue
        score = a * b * (s0[k] / a - (S - s0[k]) / b) ** 2
        if score > best: best, bk = score, k
    return bk, best

d = json.loads((ROOT / "build/paper/quality_detail.json").read_text())
out = {}
print("image      RTL t_hi   exact-Otsu k  exact+1   (RTL T_lo = T_hi/2)")
for name, v in d.items():
    t_hi = int(re.search(r"t_hi=(\d+)", v["paper_line"]).group(1))
    g = np.load(ROOT / f"model/corpus/{name}.npz")["gray"]
    nms = edge_frame(g, Config(thr_lo=64, thr_hi=192))["nms"].astype(np.int64)
    h = np.bincount(np.minimum(nms, 255).ravel(), minlength=256)
    k, _ = otsu_exact(h)
    out[name] = dict(rtl_t_hi=t_hi, exact_k=int(k), abs_diff=int(min(abs(t_hi-k), abs(t_hi-k-1))))
    print(f"{name:10s} {t_hi:6d} {k:12d} {k+1:8d}   {'EXACT' if t_hi in (k, k+1) else 'differs by %d' % min(abs(t_hi-k), abs(t_hi-k-1))}")

(ROOT / "build/paper/otsu_check.json").write_text(json.dumps(out, indent=1) + "\n")
