#!/usr/bin/env python3
"""Standalone arithmetic, NMS, histogram, reset, CRC and protocol checks."""
from pathlib import Path
import json
import sys
import zlib
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from scripts.core_regression import ROOT, SOURCES, run
from model.golden import write_hex

def main():
    out=ROOT/"build/stress";out.mkdir(parents=True,exist_ok=True)
    rng=np.random.default_rng(71326)
    lengths=[1,2,3,4,7,8,16,31,640,307200]+rng.integers(1,400,100).tolist()
    words=[];expected=[]
    for length in lengths:
        edges=rng.integers(0,2,length,dtype=np.uint8)
        encoded=edges.copy();encoded[0]|=2;encoded[-1]|=4
        words.extend(encoded.tolist());expected.append(zlib.crc32((edges*255).tobytes()))
    write_hex(out/"crc_pixels.hex",np.array(words),2)
    write_hex(out/"crc_expected.hex",np.array(expected),8)
    cases=[("arithmetic_stress",["rtl/gauss.sv","rtl/dir_decide.sv","rtl/sobel.sv"]),
           ("direction_exhaustive",["rtl/dir_decide.sv","rtl/sobel.sv"]),
           ("nms_stress",["rtl/dirnms.sv"]),("hist_stress",["rtl/classify_hist.sv"]),
           ("linebuf_recovery",["rtl/linebuf.sv"]),
           ("core_reset",SOURCES),("apb_regs",["rtl/apb_regs.sv"]),
           ("ctrl_sync",["rtl/ctrl_sync.sv"]),("crc_stress",["rtl/crc32.sv"])]
    summary=[]
    for name,src in cases:
        top="tb_"+name
        tb=f"tb/{'system' if name=='core_reset' else 'unit'}/{top}.sv"
        exe=out/f"{top}.vvp"
        run(["iverilog","-g2012","-s",top,"-o",exe,*src,tb],out/f"{top}_compile.log")
        args=["vvp",exe]
        if name=="crc_stress":args += [f"+BASE={out}",f"+COUNT={len(words)}",f"+FRAMES={len(lengths)}"]
        output,seconds=run(args,out/f"{top}.log")
        if "PASS" not in output:raise RuntimeError(output)
        print(output.splitlines()[0],flush=True)
        summary.append({"test":top,"seconds":seconds,"output":output})
    (out/"summary.json").write_text(json.dumps(summary,indent=2)+"\n")

if __name__=="__main__":main()
