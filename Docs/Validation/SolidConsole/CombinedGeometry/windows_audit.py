from pathlib import Path
exec(Path('/private/tmp/lm-solid-console-combined/audit.py').read_text().split("R={'inputs':")[0])
p=Path('/Users/zac/Projects/personal/lm/LMKit/Sources/LMKit/Resources/WindowsLPD')
g=load(p/'WindowsLPD.usdz');r={'inputs':{f.name:hashlib.sha256(f.read_bytes()).hexdigest() for f in [p/'WindowsLPD.usdz',p/'interface-v1.json']},'crossings':{}}
own=[]
for k,folder in SOURCES.items():
 a=load(folder/(k+'.usdz'));own+=a;r['crossings'][k]=crosses(a,g)
tree=combined(own);w=json.loads((p/'interface-v1.json').read_text());blocked=[];count=0
for side,eye in w['eyes'].items():
 eye=Vector(eye);a,b,c=map(Vector,w['forward'][side+'_Window_Inner']['corners'])
 for i in range(1,41):
  for j in range(1,41-i):
   count+=1;target=a*(1-i/41-j/41)+b*i/41+c*j/41;d=target-eye;hit=tree.ray_cast(eye,d.normalized(),d.length-.001)
   if hit[0] is not None:blocked.append({'side':side,'target':list(target),'hit':list(hit[0])})
r['rays']={'tested':count,'blocked':blocked};(OUT/'packaged-windows-report.json').write_text(json.dumps(r,indent=2)+'\n');print(json.dumps({'crossings':{k:len(v) for k,v in r['crossings'].items()},'rays':count,'blocked':len(blocked),'inputs':r['inputs']}))
