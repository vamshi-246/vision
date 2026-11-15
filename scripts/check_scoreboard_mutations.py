#!/usr/bin/env python3
"""Prove the scoreboard rejects representative arithmetic/alignment faults.

Only temporary source copies are mutated; repository RTL is never modified.
Run core_regression.py --quick first to create the 13x9 vectors.
"""
from pathlib import Path
import json
import shutil
import subprocess
import sys
import tempfile
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from scripts.core_regression import ROOT,SOURCES

def main():
    out=ROOT/"build/mutation_checks";out.mkdir(parents=True,exist_ok=True)
    mutations=[
        ("gaussian_rounding","rtl/gauss.sv","+ SUM_W'(8)","+ SUM_W'(0)"),
        ("sobel_magnitude","rtl/sobel.sv","magnitude <= ax_2 + ay_2","magnitude <= ax_2"),
        ("nms_tie","rtl/dirnms.sv","magnitude > later","magnitude >= later"),
        ("coordinate_alignment","rtl/top.sv","out_x <= n_win_x + 2","out_x <= n_win_x + 1"),
        ("hist_final_pixel","rtl/classify_hist.sv","COUNT_W'(nms_valid &&","COUNT_W'(1'b0 && nms_valid &&"),
        ("espresso_dir_block","rtl/dir_decide.sv","assign dir[0] = (~c0 & ~c2);","assign dir[0] = (~c0 & ~c2) | c0;"),
        ("row_order","rtl/linebuf.sv","sample_y[0] ? odd_q : even_q","sample_y[0] ? even_q : odd_q"),
    ]
    summary=[]
    for name,filename,old,new in mutations:
        with tempfile.TemporaryDirectory(prefix="p7-mutant-") as temp:
            temp=Path(temp)
            for src in [*SOURCES,"tb/system/tb_core_regression.sv"]:
                target=temp/src;target.parent.mkdir(parents=True,exist_ok=True)
                shutil.copy2(ROOT/src,target)
            path=temp/filename;source=path.read_text()
            if old not in source:raise RuntimeError(f"mutation no longer applicable: {name}")
            path.write_text(source.replace(old,new))
            compile=subprocess.run(["iverilog","-g2012","-s","tb_core_regression","-Ptb_core_regression.W=13","-Ptb_core_regression.H=9","-Ptb_core_regression.FRAMES=42","-o","sim.vvp",*SOURCES,"tb/system/tb_core_regression.sv"],cwd=temp,capture_output=True,text=True)
            if compile.returncode:raise RuntimeError(compile.stderr)
            sim=subprocess.run(["vvp","sim.vvp",f"+BASE={ROOT/'build/core_regression/13x9'}","+MODE=1"],cwd=temp,capture_output=True,text=True,timeout=30)
            (out/f"{name}.txt").write_text(sim.stdout+sim.stderr)
            if sim.returncode==0 or "FATAL" not in sim.stdout:raise RuntimeError(f"scoreboard missed mutant {name}: {sim.stdout}")
            detail=next(s for s in sim.stdout.splitlines() if "FATAL" in s)
            print(f"PASS mutation detected: {name}: {detail}",flush=True)
            summary.append({"mutation":name,"detected":True,"detail":detail})
    (out/"summary.json").write_text(json.dumps(summary,indent=2)+"\n")

if __name__=="__main__":main()
