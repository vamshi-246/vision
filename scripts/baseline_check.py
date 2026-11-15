#!/usr/bin/env python3
"""Check rtl/study/baseline_top.sv (plain Sobel >= 192 on raw gray) against the model, 2 frames."""
import subprocess, sys
from pathlib import Path
import numpy as np
ROOT = Path(__file__).resolve().parents[1]; sys.path.insert(0, str(ROOT))
from model.golden import Config, sobel_frame, write_hex
W, H = 40, 30
rng = np.random.default_rng(5)
yy, xx = np.mgrid[:H, :W]
img = np.clip(((xx * 6) ^ (yy * 9)) % 256 + rng.integers(0, 40, (H, W)), 0, 255).astype(np.uint8)
d = ROOT / "build/baseline_check"; d.mkdir(parents=True, exist_ok=True); write_hex(d / "img.hex", img, 2)
gx, gy, _ = sobel_frame(img, 0, Config())
mag = np.abs(gx.astype(np.int32)) + np.abs(gy.astype(np.int32))
exp = (mag[1:-1, 1:-1] >= 192).astype(int).ravel()
srcs = ["rtl/linebuf.sv", "rtl/dir_decide.sv", "rtl/sobel.sv", "rtl/study/baseline_top.sv", "tb/study/tb_baseline.sv"]
subprocess.run(["iverilog", "-g2012", "-s", "tb_baseline", f"-Ptb_baseline.BASE=\"{d}\"", f"-Ptb_baseline.W={W}", f"-Ptb_baseline.H={H}", "-o", str(d / "t.vvp"), *srcs], cwd=ROOT, check=True)
subprocess.run(["vvp", "-n", str(d / "t.vvp")], cwd=ROOT, capture_output=True, text=True, check=True)
got = np.array([int(x) for x in (d / "out.txt").read_text().split()])
n = exp.size
assert got.size == 2 * n, (got.size, n)
ok = np.array_equal(got[:n], exp) and np.array_equal(got[n:], exp)
print(f"baseline_top vs model: {2*n} output pixels over 2 frames, {int(exp.sum())} edges/frame -> {'PASS' if ok else 'FAIL'}")
sys.exit(0 if ok else 1)
