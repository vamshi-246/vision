#!/usr/bin/env python3
"""Expected values for tb_soc: stored half-size image, edge counts for 4 presets + one override, 64-bin NMS histogram."""
import sys
from pathlib import Path
import numpy as np
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from model.golden import Config, edge_frame, histogram64, natural_images, write_hex

def main(out: Path, w=64, h=48):
    out.mkdir(parents=True, exist_ok=True)
    half = natural_images(w // 2, h // 2)[0][1]
    full = np.repeat(np.repeat(half, 2, 0), 2, 1)
    write_hex(out / "half.hex", half, 2)
    presets = [(80, 200), (20, 40), (160, 400), (300, 700), (30, 90)]
    lines = []
    for lo, hi in presets:
        r = edge_frame(full, Config(thr_lo=lo, thr_hi=hi))
        lines.append(f"{lo} {hi} {int((r['cls'] == 2).sum())}")
    (out / "exp.txt").write_text("\n".join(lines) + "\n")
    hist, nnz = histogram64(r["nms"])
    write_hex(out / "exp.hex", hist, 8)
    print("expected edges:", lines)

if __name__ == "__main__":
    main(Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "build/soc_test")
