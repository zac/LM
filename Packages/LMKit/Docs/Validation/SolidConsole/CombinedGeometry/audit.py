import json,hashlib,itertools,math
from pathlib import Path
from pxr import Usd,UsdGeom,Gf
from mathutils import Vector,Matrix,Quaternion
from mathutils.bvhtree import BVHTree
from mathutils.geometry import intersect_ray_tri
OUT=Path('/private/tmp/lm-solid-console-combined')
BASE=Path('/Users/zac/Projects/personal/lm/LMKit/Assets/Cockpit/Components')
SOURCES={k:Path('/private/tmp')/d/'Assets/Cockpit/Components'/k for k,d in [('InstrumentConsole','lmkit-instrument-console'),('LowerConsole','lmkit-lower-console'),('WindowSurrounds','lmkit-window-surrounds')]}
def load(path,overrides=None):
 s=Usd.Stage.Open(str(path));cache=UsdGeom.XformCache();out=[]
 memo={}
 def world(p):
  if not overrides:return Matrix([[cache.GetLocalToWorldTransform(p)[j][i] for j in range(4)] for i in range(4)])
  key=str(p.GetPath())
  if key in memo:return memo[key]
  if p.IsPseudoRoot():return Matrix.Identity(4)
  xf=UsdGeom.Xformable(p);u=xf.GetLocalTransformation() if xf else Gf.Matrix4d(1);m=Matrix([[u[j][i] for j in range(4)] for i in range(4)])
  if p.GetName() in overrides:m=Matrix.Translation(m.translation)@overrides[p.GetName()].to_4x4()
  memo[key]=m if xf and xf.GetResetXformStack() else world(p.GetParent())@m
  return memo[key]
 for p in s.Traverse():
  if not p.IsA(UsdGeom.Mesh):continue
  g=UsdGeom.Mesh(p);m=world(p);v=[m@Vector(q) for q in g.GetPointsAttr().Get()];idx=g.GetFaceVertexIndicesAttr().Get();tri=[];i=0
  for n in g.GetFaceVertexCountsAttr().Get():
   tri += [(idx[i],idx[i+j],idx[i+j+1]) for j in range(1,n-1)];i+=n
  out.append({'path':str(p.GetPath()),'v':v,'t':tri,'lo':Vector([min(q[j] for q in v) for j in range(3)]),'hi':Vector([max(q[j] for q in v) for j in range(3)]),'bvh':BVHTree.FromPolygons(v,tri,all_triangles=True)})
 return out
def combined(meshes):
 v=[];t=[]
 for m in meshes:
  off=len(v);v+=m['v'];t += [tuple(off+i for i in f) for f in m['t']]
 return BVHTree.FromPolygons(v,t,all_triangles=True)
def crosses(a,b):
 out=[]
 for x in a:
  for y in b:
   if any(x['lo'][i]>y['hi'][i] or y['lo'][i]>x['hi'][i] for i in range(3)):continue
   pairs=x['bvh'].overlap(y['bvh'])
   if pairs:
    points=[]
    for ai,bi in pairs:
     at=[x['v'][i] for i in x['t'][ai]];bt=[y['v'][i] for i in y['t'][bi]]
     for edges,face in [(at,bt),(bt,at)]:
      for u,v in zip(edges,edges[1:]+edges[:1]):
       d=v-u
       if d.length<1e-9:continue
       h=intersect_ray_tri(*face,d.normalized(),u,True)
       if h is not None and (h-u).length<=d.length+1e-6:points.append(h)
    out.append({'a':x['path'],'b':y['path'],'triangle_pairs':len(pairs),'aabb_overlap_m':[min(x['hi'][i],y['hi'][i])-max(x['lo'][i],y['lo'][i]) for i in range(3)],'intersection_min':[min(p[i] for p in points) for i in range(3)] if points else None,'intersection_max':[max(p[i] for p in points) for i in range(3)] if points else None})
 return out
R={'inputs':{},'crossings':{},'rays':{},'limits':['Surface crossings include intentional contact; containment and all seams are not decided by BVH alone.','Finite rays are not continuous head/reach clearance or native visual acceptance.']};geo={}
for k,d in SOURCES.items():
 R['inputs'][k]={f.name:hashlib.sha256(f.read_bytes()).hexdigest() for f in [d/(k+'.usdz'),d/'interface.json',d/'build.py']};geo[k]=load(d/(k+'.usdz'))
for a,b in itertools.combinations(geo,2):R['crossings'][a+'__'+b]=crosses(geo[a],geo[b])
tree=combined(sum(geo.values(),[]))
windows=json.loads((BASE/'WindowsLPD/interface-v1.json').read_text());rays=[]
for side,e in windows['eyes'].items():
 eye=Vector(e);a,b,c=map(Vector,windows['forward'][side+'_Window_Inner']['corners'])
 for i in range(1,41):
  for j in range(1,41-i):
   p=a*(1-i/41-j/41)+b*i/41+c*j/41;d=p-eye;hit=tree.ray_cast(eye,d.normalized(),d.length-.001)
   if hit[0] is not None:rays.append({'side':side,'target':list(p),'hit':list(hit[0])})
R['rays']['windows']={'tested':1560,'blocked':rays}
instrument=json.loads((SOURCES['InstrumentConsole']/'validation.json').read_text())['face_rays'];blocked=[]
for r in instrument:
 p=Vector(r['target_cabin_m']);pilot=r['component'] in ['LMP_FDAI','PilotLunarContact'] or p.x>0 and r['component']=='CautionWarning';e=Vector((.5588 if pilot else -.5588,1.78,-.38));d=p-e;hit=tree.ray_cast(e,d.normalized(),d.length-.0005)
 if hit[0] is not None:blocked.append(dict(r,hit=list(hit[0])))
R['rays']['instruments']={'tested':len(instrument),'blocked':blocked}
inv=json.loads((SOURCES['LowerConsole']/'evidence/inventory.json').read_text());panel=next(p for p in inv['panels'] if p['id']=='Panel4');pose=panel['pose'];q=pose['quaternion_xyzw'];m=Matrix.Translation(Vector(pose['translation_m']))@Quaternion((q[3],*q[:3])).to_matrix().to_4x4();rays=[]
for x,y in itertools.product([-.1,-.05,0,.05,.1],[-.085,-.04,.015,.07,.115]):
 a=m@Vector((x,y,.03));d=m.to_3x3()@Vector((0,0,-1));hit=tree.ray_cast(a,d,.05)
 if hit[0] is not None:rays.append({'xy':[x,y],'hit':list(hit[0])})
R['rays']['dsky_front_aperture']={'tested':25,'blocked':rays}
peerreport=json.loads((SOURCES['WindowSurrounds']/'assembly-validation.json').read_text())
R['peer_checks']={}
for k in ['ACA','MissionTimer']:
 info=peerreport['inputs'][k];pg=load(Path(info['path']));m=Matrix(info['matrix_cabin_row_major'])
 for mesh in pg:
  mesh['v']=[m@p for p in mesh['v']];mesh['lo']=Vector([min(p[j] for p in mesh['v']) for j in range(3)]);mesh['hi']=Vector([max(p[j] for p in mesh['v']) for j in range(3)]);mesh['bvh']=BVHTree.FromPolygons(mesh['v'],mesh['t'],all_triangles=True)
 R['peer_checks'][k]={'input':info,'actual_bounds':[[min(mesh['lo'][j] for mesh in pg) for j in range(3)],[max(mesh['hi'][j] for mesh in pg) for j in range(3)]],'crossings':{name:crosses(g,pg) for name,g in geo.items()}}
aca=peerreport['inputs']['ACA'];mount=Matrix(aca['matrix_cabin_row_major']);motionhits=[]
for roll,yaw,pitch in itertools.product([-11,-5.5,0,5.5,11],repeat=3):
 pg=load(Path(aca['path']),{'ACA_Roll':Matrix.Rotation(math.radians(-roll),3,'Z'),'ACA_Yaw':Matrix.Rotation(math.radians(yaw),3,'Y'),'ACA_Pitch':Matrix.Rotation(math.radians(pitch),3,'X')})
 for mesh in pg:
  mesh['v']=[mount@p for p in mesh['v']];mesh['lo']=Vector([min(p[j] for p in mesh['v']) for j in range(3)]);mesh['hi']=Vector([max(p[j] for p in mesh['v']) for j in range(3)]);mesh['bvh']=BVHTree.FromPolygons(mesh['v'],mesh['t'],all_triangles=True)
 for name,g in geo.items():
  hits=crosses(g,pg)
  if hits:motionhits.append({'pose_degrees':[roll,yaw,pitch],'component':name,'crossings':hits})
R['aca_sampled_motion']={'poses':125,'hits':motionhits}
R['inputs_stable_during_audit']=all(hashlib.sha256((SOURCES[k]/f).read_bytes()).hexdigest()==h for k,files in R['inputs'].items() for f,h in files.items())
R['suppression_conflicts']=[];owned={}
for k,p in SOURCES.items():
 for r in json.loads((p/'interface.json').read_text())['suppressions']:
  key=(r['component'],r['path'])
  if key in owned:R['suppression_conflicts'].append({'source':list(key),'owners':[owned[key],k]})
  owned[key]=k
(OUT/'report.json').write_text(json.dumps(R,indent=2)+'\n')
print(json.dumps({'crossing_counts':{k:len(v) for k,v in R['crossings'].items()},'rays':{k:{'tested':v['tested'],'blocked':len(v['blocked'])} for k,v in R['rays'].items()}}))
