#!/usr/bin/env python3
"""Preserve reports after every routed TMDS simulation has passed."""
from pathlib import Path
import sys,json,hashlib,shutil
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from scripts.core_regression import ROOT

def main():
 dst=ROOT/'doc/evidence/hdmi';dst.mkdir(parents=True,exist_ok=True)
 results={}
 for corner in ['functional','max','min']:
  src=ROOT/f'build/hdmi_sim_{corner}'
  result=json.loads((src/'summary.json').read_text())
  if not result['pass'] or result['operational_timing_warnings']:raise RuntimeError(f'{corner} did not pass')
  results[corner]=result
  for file in ['summary.json','simulate.txt','elaborate.txt']:shutil.copy2(src/file,dst/f'{corner}_{file}')
 for file in ['timing.rpt','utilization.rpt','drc.rpt','cdc.rpt','methodology.rpt','clocks.rpt','checks.txt']:
  shutil.copy2(ROOT/'build/hdmi'/file,dst/file)
 shutil.copy2(ROOT/'build/video_regression/summary.json',dst/'video_regression.json')
 shutil.copy2(ROOT/'build/core_after_video.txt',dst/'core_regression.txt')
 shutil.copy2(ROOT/'build/unit_after_video.txt',dst/'unit_tests.txt')
 for source,name in [('build/hdmi_hardware_console.txt','jtag_discovery.txt'),('build/hdmi_program_console.txt','programming.txt')]:
  if (ROOT/source).exists():shutil.copy2(ROOT/source,dst/name)
 paths=[p for folder in ['rtl','tb/video','third_party/rgb2dvi','scripts'] for p in (ROOT/folder).rglob('*') if p.is_file() and p.suffix in ['.sv','.vhd','.tcl','.py','.xml']]
 paths += [ROOT/'fpga/zybo_hdmi.xdc',ROOT/'model/golden.py',ROOT/'build/hdmi/zybo_edge_hdmi.bit',ROOT/'build/hdmi/routed_timesim.v',ROOT/'build/hdmi/routed_slow.sdf',ROOT/'build/hdmi/routed_fast.sdf']
 manifest={'part':'xc7z010clg400-1','tool':'Vivado/XSim 2024.2','ip_commit':'0362ce72d39eebc400fdabacff706ee7fa8ad564','simulations':results,
 'sha256':{str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(paths)}}
 (dst/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
 print('Saved HDMI evidence and source/bitstream hashes to',dst)
if __name__=='__main__':main()
