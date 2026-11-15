#!/usr/bin/env python3
"""Post-route XSim simulation with SDF and serial TMDS decoding."""
from pathlib import Path
import sys,shutil,tempfile,argparse,re,json,hashlib
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from scripts.core_regression import ROOT,run

def score(out,corner,output):
 if 'PASS routed TMDS timing' not in output:raise RuntimeError(output[-6000:])
 violations=[line for line in output.splitlines() if 'Timing violation' in line]
 # The vendor glbl model holds configuration GSR active for the first 100 ns.
 operational=[]
 for line in violations:
  when=re.search(r'at time ([0-9.]+) ps',line)
  if when is None or float(when.group(1))>=100000:operational.append(line)
 if operational:raise RuntimeError('Operational timing violations: inspect '+str(out/'simulate.txt'))
 passed=next(s for s in output.splitlines() if 'PASS routed TMDS timing' in s)
 result={'corner':corner,'pass':True,'configuration_startup_warnings':len(violations),'operational_timing_warnings':0,'result':passed}
 (out/'summary.json').write_text(json.dumps(result,indent=2)+'\n')
 print(f'{corner}: configuration-startup warnings (<100 ns): {len(violations)}; operational timing warnings: 0')
 print(passed)

def main():
 ap=argparse.ArgumentParser(description=__doc__)
 ap.add_argument('--corner',choices=['max','min','functional'],default='max')
 ap.add_argument('--design-dir',type=Path,default=ROOT/'build/hdmi')
 ap.add_argument('--ideal-clocks',action='store_true',help='Diagnostic: substitute co-phased MMCM output clocks while preserving the routed clock tree')
 ap.add_argument('--score-only',action='store_true',help='Rescore the saved simulation log without rerunning XSim')
 args=ap.parse_args()
 label='' if args.design_dir.name=='hdmi' else '_'+args.design_dir.name
 out=ROOT/('build/hdmi_sim_'+args.corner+label+('_ideal' if args.ideal_clocks else ''));out.mkdir(parents=True,exist_ok=True)
 if args.score_only:
  score(out,args.corner,(out/'simulate.txt').read_text());return
 bin=Path('/tools/Xilinx/Vivado/2024.2/bin')
 with tempfile.TemporaryDirectory(prefix='p7-hdmi-timing-') as td:
  td=Path(td)
  netlist='routed_funcsim.v' if args.corner=='functional' else 'routed_timesim.v'
  sdf='routed_fast.sdf' if args.corner=='min' else 'routed_slow.sdf'
  for source,name in [(args.design_dir/netlist,'netlist.v'),(args.design_dir/sdf,'routed.sdf'),('tb/video/tb_hdmi_timing.sv','tb.sv')]:shutil.copy2(ROOT/source,td/name)
  shutil.copy2(bin.parent/'data/verilog/src/glbl.v',td/'glbl.v')
  defines=['--define','HDMI_IDEAL_CLOCKS'] if args.ideal_clocks else []
  run([bin/'xvlog','--sv',*defines,'netlist.v','tb.sv','glbl.v'],out/'compile.txt',td)
  annotate=[] if args.corner=='functional' else ['--'+('mindelay' if args.corner=='min' else 'maxdelay'),'--sdf'+args.corner,'/tb_hdmi_timing/dut=routed.sdf','--transport_int_delays','--pulse_r','0','--pulse_int_r','0']
  run([bin/'xelab','tb_hdmi_timing','glbl','-L','simprims_ver','-L','unisims_ver','-L','secureip','-mt','2','-s','hdmi_timing',*annotate],out/'elaborate.txt',td)
  output,seconds=run([bin/'xsim','hdmi_timing','-R'],out/'simulate.txt',td)
  score(out,args.corner,output)
  print(f'Wall seconds: {seconds}')
if __name__=='__main__':main()
