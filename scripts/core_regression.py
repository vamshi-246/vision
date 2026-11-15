#!/usr/bin/env python3
"""Reproducible core RTL regression; run using the project Python environment."""
from __future__ import annotations
import argparse
import json
import subprocess
from pathlib import Path
import sys
import time
import shutil
import tempfile

import numpy as np
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from model.golden import Config, edge_frame, histogram64, synthetic_images, write_hex

ROOT = Path(__file__).resolve().parents[1]
SOURCES = [f"rtl/{s}.sv" for s in ("linebuf", "gauss", "dir_decide", "sobel", "dirnms", "classify_hist", "top")]

def run(cmd, log, cwd=ROOT):
    start=time.monotonic()
    with log.open("w") as stream:
        p=subprocess.run([str(x) for x in cmd],cwd=cwd,stdout=stream,stderr=subprocess.STDOUT,timeout=900)
    output=log.read_text()
    if p.returncode:
        raise RuntimeError(f"{' '.join(map(str,cmd))}\n{output[-6000:]}")
    return output, round(time.monotonic()-start,3)

def corpus(w,h,full):
    rng=np.random.default_rng(0x7132026+w+h)
    y,x=np.mgrid[:h,:w]
    images=synthetic_images(w,h)
    images += [("black",np.zeros((h,w),np.uint8)),("white",np.full((h,w),255,np.uint8)),
               ("checker1",((x+y)%2*255).astype(np.uint8)),
               ("ramp",((x*7+y*13)%256).astype(np.uint8)),
               ("hstep",np.where(y>=h//2,255,0).astype(np.uint8)),
               ("diagonal",np.where(x*h>=y*w,255,0).astype(np.uint8))]
    for i in range(5 if full else 25):
        images.append((f"random{i}",rng.integers(0,256,(h,w),dtype=np.uint8)))
    if full:
        from PIL import Image
        photo=ROOT/"Demon-Slayer-Anime-3.jpg"
        if photo.exists():
            images.append(("supplied_photo",np.asarray(Image.open(photo).convert("RGB").resize((w,h)))))
    # Group-mate corpus (6 natural + 4 synthetic 640x480 images, model/corpus/*.npz): run at his 64/192 defaults.
    pairs=[(80,200)]*len(images)
    if full and (w,h)==(640,480):
        for f in sorted((ROOT/"model/corpus").glob("*.npz")):
            images.append(("corpus_"+f.stem,np.load(f)["gray"])); pairs.append((64,192))
    # Equality, very low, and above-Sobel-range threshold pairs.
    for lo,hi in [(0,1),(1,1),(80,80),(1020,1530),(2047,2047),(0,0)]:
        images.append((f"threshold_{lo}_{hi}",rng.integers(0,256,(h,w),dtype=np.uint8)))
        pairs.append((lo,hi))
    return images,pairs

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--quick",action="store_true")
    ap.add_argument("--simulator",choices=["iverilog","verilator"],default="verilator")
    ap.add_argument("--outdir",type=Path,default=ROOT/"build/core_regression")
    args=ap.parse_args(); args.outdir.mkdir(parents=True,exist_ok=True)
    summary=[]
    sizes=[(7,7),(8,8),(13,9),(31,23)]
    if not args.quick: sizes += [(320,240),(640,480)]
    for w,h in sizes:
        case=args.outdir/f"{w}x{h}"; case.mkdir(parents=True,exist_ok=True)
        images,pairs=corpus(w,h,w>=320)
        results=[edge_frame(a,Config(thr_lo=lo,thr_hi=hi)) for (_,a),(lo,hi) in zip(images,pairs)]
        for field,digits in [("gray",2),("smooth",2),("mag",3),("dir",1),("nms",3),("cls",1)]:
            write_hex(case/f"{field}.hex",np.stack([r[field] for r in results]),digits)
        hist=[histogram64(r["nms"]) for r in results]
        write_hex(case/"hist.hex",np.stack([v[0] for v in hist]),5)
        write_hex(case/"nnz.hex",np.array([v[1] for v in hist]),5)
        write_hex(case/"lo.hex",np.array([lo for lo,_ in pairs]),3)
        write_hex(case/"hi.hex",np.array([hi for _,hi in pairs]),3)
        (case/"manifest.json").write_text(json.dumps({"size":[w,h],"seed":0x7132026+w+h,"frames":[{"name":name,"lo":lo,"hi":hi} for (name,_),(lo,hi) in zip(images,pairs)]},indent=2)+"\n")
        n=len(images)
        if args.simulator=="iverilog":
            exe=case/"sim.vvp"
            cmd=["iverilog","-g2012","-s","tb_core_regression",f"-Ptb_core_regression.W={w}",f"-Ptb_core_regression.H={h}",f"-Ptb_core_regression.FRAMES={n}","-o",exe,*SOURCES,"tb/system/tb_core_regression.sv"]
            launch=["vvp",exe]
        else:
            # GNU Make/Verilator reject source/build directories with spaces.
            # Compile an exact source copy in a private temporary directory.
            exe=case/"rtl_sim"
            with tempfile.TemporaryDirectory(prefix="p7-core-") as temp:
                temp=Path(temp)
                for src in [*SOURCES,"tb/system/tb_core_regression.sv"]:
                    dest=temp/src; dest.parent.mkdir(parents=True,exist_ok=True)
                    shutil.copy2(ROOT/src,dest)
                cmd=["verilator","--binary","--timing","-j","2","-Wno-fatal","--top-module","tb_core_regression",f"-GW={w}",f"-GH={h}",f"-GFRAMES={n}","--Mdir","obj",*SOURCES,"tb/system/tb_core_regression.sv"]
                run(cmd,case/"compile.log",temp)
                shutil.copy2(temp/"obj/Vtb_core_regression",exe)
            launch=[exe]
        if args.simulator=="iverilog": run(cmd,case/"compile.log")
        for mode in [0,1,2]:
            output,seconds=run([*launch,f"+BASE={case}",f"+MODE={mode}"],case/f"mode{mode}.log")
            line=next((s for s in output.splitlines() if s.startswith("PASS core")),None)
            if not line: raise RuntimeError(output)
            print(line,flush=True)
            summary.append({"width":w,"height":h,"frames":n,"mode":mode,"seconds":seconds,"result":line})
        (args.outdir/"summary.json").write_text(json.dumps(summary,indent=2)+"\n")

if __name__=="__main__": main()
