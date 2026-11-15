#!/usr/bin/env python3
"""Verify all four complete video views against the software model."""
from pathlib import Path
import sys,tempfile,shutil,json
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from scripts.core_regression import ROOT,SOURCES,run
from model.golden import Config,edge_frame,write_hex,natural_images

def main():
 out=ROOT/'build/video_regression';out.mkdir(parents=True,exist_ok=True)
 summary=[]
 for w,h in [(64,48),(640,480)]:
  case=out/f'{w}x{h}';case.mkdir(exist_ok=True)
  y,x=np.mgrid[:h,:w]
  gray=np.where((x>=w//4)&(x<w*3//4)&(y>=h//4)&(y<h*3//4),220,np.where(((x>>5)^(y>>5))&1,160,24)).astype(np.uint8)
  for preset,(lo,hi) in enumerate([(80,200),(20,40),(160,400),(300,700)]):
   vec=case/f'preset{preset}';vec.mkdir(exist_ok=True)
   result=edge_frame(gray,Config(thr_lo=lo,thr_hi=hi))
   for k,d in [('gray',2),('smooth',2),('cls',1)]:write_hex(vec/(k+'.hex'),result[k],d)
  # Stored-image source: a (w/2)x(h/2) image replicated 2x; expected vectors from the same model.
  half=natural_images(w//2,h//2)[0][1]
  full=np.repeat(np.repeat(half,2,axis=0),2,axis=1)
  img=case/'image';img.mkdir(exist_ok=True)
  write_hex(img/'half.hex',half,2)
  for preset,(lo,hi) in enumerate([(80,200),(20,40),(160,400),(300,700)]):
   vec=img/f'preset{preset}';vec.mkdir(exist_ok=True);write_hex(vec/'half.hex',half,2)
   result=edge_frame(full,Config(thr_lo=lo,thr_hi=hi))
   for k,d in [('gray',2),('smooth',2),('cls',1)]:write_hex(vec/(k+'.hex'),result[k],d)
  srcs=[*SOURCES,'rtl/vga_timing.sv','rtl/video/video_delay.sv','rtl/video/edge_video.sv','tb/video/tb_edge_video.sv']
  with tempfile.TemporaryDirectory(prefix='p7-video-') as td:
   td=Path(td)
   for src in srcs:
    dest=td/src;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/src,dest)
   run(['verilator','--binary','--timing','-j','2','-Wno-fatal','--top-module','tb_edge_video',f'-GW={w}',f'-GH={h}',*srcs],case/'compile.txt',td)
   shutil.copy2(td/'obj_dir/Vtb_edge_video',case/'sim')
  for mode,preset in [(0,0),(1,0),(2,0),(3,0),(2,1),(2,2),(2,3)]:
   output,seconds=run([case/'sim',f'+BASE={case / ("preset"+str(preset))}',f'+MODE={mode}',f'+PRESET={preset}'],case/f'mode{mode}_preset{preset}.txt')
   if 'PASS video' not in output:raise RuntimeError(output)
   print(output.splitlines()[0],flush=True)
   summary.append({'width':w,'height':h,'mode':mode,'preset':preset,'img':0,'seconds':seconds,'result':output})
  for mode,preset in [(0,0),(1,0),(2,0),(3,0),(2,1),(2,2),(2,3)]:
   output,seconds=run([case/'sim',f'+BASE={case / "image" / ("preset"+str(preset))}',f'+MODE={mode}',f'+PRESET={preset}','+IMG=1'],case/f'img_mode{mode}_preset{preset}.txt')
   if 'PASS video' not in output:raise RuntimeError(output)
   print(output.splitlines()[0],flush=True)
   summary.append({'width':w,'height':h,'mode':mode,'preset':preset,'img':1,'seconds':seconds,'result':output})
 (out/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
if __name__=='__main__':main()
