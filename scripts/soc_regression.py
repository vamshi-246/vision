#!/usr/bin/env python3
"""Build firmware, generate model vectors, run the PicoRV32 SoC acceptance test, and prove it can fail (corrupted expectation)."""
import shutil, subprocess, sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import soc_vectors
SRC = ["rtl/linebuf.sv", "rtl/gauss.sv", "rtl/dir_decide.sv", "rtl/sobel.sv", "rtl/dirnms.sv", "rtl/classify_hist.sv", "rtl/top.sv",
       "rtl/apb_regs.sv", "rtl/vga_timing.sv", "rtl/video/video_delay.sv", "rtl/video/edge_video.sv", "rtl/soc/soc_ram.sv",
       "rtl/soc/cpu_subsys.sv", "third_party/picorv32/picorv32.v", "rtl/video/video_soc.sv"]

def sh(cmd, **k):
    return subprocess.run([str(c) for c in cmd], cwd=k.pop("cwd", ROOT), capture_output=True, text=True, **k)

def main():
    r = sh(["make", "-C", "fw"]); print(r.stdout.splitlines()[-2] if r.returncode == 0 else r.stderr); assert r.returncode == 0
    good = ROOT / "build/soc_test"; soc_vectors.main(good); shutil.copy2(ROOT / "fw/build/fw.hex", good / "fw.hex")
    exe = ROOT / "build/tb_soc.vvp"
    c = sh(["iverilog", "-g2012", "-s", "tb_soc", "-o", exe, *SRC, "tb/soc/tb_soc.sv"]); assert c.returncode == 0, c.stderr
    out = sh(["vvp", "-n", exe, f"+BASE={good}"]).stdout; print(out)
    assert "PASS soc" in out
    bad = ROOT / "build/soc_test_corrupt"; shutil.copytree(good, bad, dirs_exist_ok=True)
    lines = (bad / "exp.txt").read_text().split("\n"); lo, hi, n = lines[2].split(); lines[2] = f"{lo} {hi} {int(n)+1}"
    (bad / "exp.txt").write_text("\n".join(lines))
    outb = sh(["vvp", "-n", exe, f"+BASE={bad}"]).stdout
    assert "FAIL soc" in outb, "test did not detect a corrupted expectation"
    print("non-vacuity: corrupted expected edge count -> test FAILs as required")
if __name__ == "__main__": main()
