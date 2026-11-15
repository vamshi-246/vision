#!/usr/bin/env python3
"""Run two VGA frames against the actual Vivado functional synthesis netlist."""
from pathlib import Path
import argparse
import shutil
import sys
import tempfile
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from scripts.core_regression import ROOT,run

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--vivado-bin",type=Path,default=Path("/tools/Xilinx/Vivado/2024.2/bin"))
    args=ap.parse_args()
    out=ROOT/"build/netlist_regression";out.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="p7-netlist-") as temp:
        temp=Path(temp);vectors=temp/"vectors";vectors.mkdir()
        for field,count in [("gray",2*640*480),("cls",2*640*480),("hist",128),("nnz",2)]:
            source=ROOT/f"build/core_regression/640x480/{field}.hex"
            with source.open() as src,(vectors/f"{field}.hex").open("w") as dst:
                for _ in range(count):dst.write(next(src))
        shutil.copy2(ROOT/"build/vivado_core/core_funcsim.v",temp/"netlist.v")
        shutil.copy2(ROOT/"tb/system/tb_core_netlist.sv",temp/"tb.sv")
        shutil.copy2(args.vivado_bin.parent/"data/verilog/src/glbl.v",temp/"glbl.v")
        run([args.vivado_bin/"xvlog","--sv","netlist.v","tb.sv","glbl.v"],out/"xvlog.log",temp)
        run([args.vivado_bin/"xelab","tb_core_netlist","glbl","-L","unisims_ver","-L","unimacro_ver","-s","core_netlist"],out/"xelab.log",temp)
        output,seconds=run([args.vivado_bin/"xsim","core_netlist","-R","-testplusarg",f"BASE={vectors}"],out/"xsim.log",temp)
        if "PASS synthesized netlist" not in output:raise RuntimeError(output[-6000:])
        print(next(s for s in output.splitlines() if s.startswith("PASS synthesized")))
        print(f"Simulation wall seconds: {seconds}")

if __name__=="__main__":main()
