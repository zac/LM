#!/usr/bin/env python3
"""Inspect arrival frames in a completed CaptureLunarTerrainTransitions run.

Resamples lossy video at 1280x720 and 60 fps. Reports adjacent-frame changes
around logged arrivals and retains sampled frames plus each peak pair.
Host/video time alignment is approximate. This is a diagnostic supplement to
visual inspection, not a replacement for the fixed-band PNG radiance protocol.
Requires ffmpeg, numpy and Pillow. Older atomic-arrival recordings are supported.
"""
import argparse, datetime as dt, json, subprocess
from pathlib import Path
import numpy as np
from PIL import Image

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('root', type=Path)
p.add_argument('--pid', type=int)
args = p.parse_args()
root = args.root
pid = args.pid or int((root/'run.tsv').read_text().splitlines()[1].split('\t')[0])
start = float((root/'recording-start.txt').read_text())
events = []
for line in (root/'performance.log').read_text().splitlines():
    fields = line.split()
    if len(fields)<6 or fields[5]!=str(pid): continue
    if not any(s in line for s in ['Global morph begin', 'Global morph complete', 'Global terrain ready', 'Transition probe begin']): continue
    seconds = dt.datetime.strptime(fields[0]+'T'+fields[1], '%Y-%m-%dT%H:%M:%S.%f%z').timestamp()-start
    events.append(dict(seconds=seconds, log=line))
arrivals = []
begins = [e for e in events if 'Global morph begin' in e['log']]
if begins:
    ends = [e for e in events if 'Global morph complete' in e['log']]
    arrivals = [(a['seconds'], b['seconds']) for a,b in zip(begins,ends)]
else:
    arrivals = [(e['seconds'], e['seconds']) for e in events if 'Global terrain ready' in e['log'] and e['seconds']>0]
frames = root/'arrival-frames'; frames.mkdir(exist_ok=True)
results=[]
width,height,fps = 1280,720,60
for i,(begin,end) in enumerate(arrivals,1):
    first=max(0,begin-1.5); duration=end-begin+3
    command=['ffmpeg','-v','error','-threads','1','-ss',str(first),'-i',str(root/'transitions.mov'),'-t',str(duration),'-vf',f'scale={width}:{height},fps={fps}','-threads','1','-f','rawvideo','-pix_fmt','rgb24','pipe:1']
    proc=subprocess.Popen(command,stdout=subprocess.PIPE)
    prior=None; measurements=[]; peak=0
    index=0
    while True:
        raw=proc.stdout.read(width*height*3)
        if not raw: break
        if len(raw)!=width*height*3: raise RuntimeError('partial frame')
        value=np.frombuffer(raw,dtype=np.uint8).reshape(height,width,3)
        if index%12==0:
            Image.fromarray(value).save(frames/f'arrival-{i}-{index:03d}.png')
        if prior is not None:
            diff=(value.astype(np.float32)-prior)/255
            rmse=float(np.sqrt(np.mean(diff*diff)))
            measurements.append(dict(seconds=first+index/fps,rmse=rmse,changedPixels=int(np.any(value!=prior,axis=2).sum())))
            if rmse>peak:
                peak=rmse
                Image.fromarray(prior).save(frames/f'arrival-{i}-peak-before.png')
                Image.fromarray(value).save(frames/f'arrival-{i}-peak-after.png')
        prior=value.copy();index+=1
    if proc.wait(): raise RuntimeError('ffmpeg failed')
    ordered=sorted(measurements,key=lambda x:x['rmse'],reverse=True)
    results.append(dict(arrival=i,begin=begin,end=end,frames=index,peak=ordered[:5],samples=measurements))
(root/'arrival-temporal-metrics.json').write_text(json.dumps(dict(note='Lossy H264 1280x720 60 fps diagnostic. Host-time alignment is approximate; not a PNG radiance acceptance metric.',events=events,arrivals=results),indent=2))
print(json.dumps([{k:v for k,v in r.items() if k!='samples'} for r in results],indent=2))
