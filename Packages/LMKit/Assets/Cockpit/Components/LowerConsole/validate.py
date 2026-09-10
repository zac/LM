"""Independent USD triangle clearance, cavity aperture and runtime sampled articulation checks."""
import sys,itertools,hashlib
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
from geometry import *
from mathutils.bvhtree import BVHTree
D=Path(__file__).resolve().parent;I=json.loads((D/'interface.json').read_text());P={p['id']:p for p in json.loads((D/'evidence/inventory.json').read_text())['panels']};R={'checks':[],'peers':{},'limits':['Mesh intersection and sampled articulation are not fabrication or human-reach qualification.','Peer peer collisions are outside this overlay test.','No electrical/input/motion implementation is supplied.']}
def check(ok,label):
 R['checks'].append({'check':label,'passed':bool(ok)})
 return bool(ok)
def geometry(stage,transform=None,omit=(),overrides=None):
 out=[];transform=transform or Matrix.Identity(4);cache={}
 def world(p):
  name=str(p.GetPath())
  if name in cache:return cache[name]
  if p.IsPseudoRoot():return Matrix.Identity(4)
  u=UsdGeom.Xformable(p).GetLocalTransformation() if p.IsA(UsdGeom.Xformable) else Gf.Matrix4d(1);m=Matrix([[u[j][i] for j in range(4)] for i in range(4)])
  if overrides and p.GetName() in overrides:m=Matrix.Translation(m.translation)@overrides[p.GetName()].to_4x4()
  cache[name]=world(p.GetParent())@m;return cache[name]
 for p in stage.Traverse():
  n=str(p.GetPath())
  if not p.IsA(UsdGeom.Mesh) or any(n==s or n.startswith(s+'/') for s in omit):continue
  m=transform@world(p);mesh=UsdGeom.Mesh(p);pts=[m@Vector(v) for v in mesh.GetPointsAttr().Get()];cs=mesh.GetFaceVertexCountsAttr().Get();ids=mesh.GetFaceVertexIndicesAttr().Get();faces=[];at=0
  for size in cs:faces.append(tuple(ids[at:at+size]));at+=size
  out.append({'path':n,'points':pts,'faces':faces,'min':[min(p[i] for p in pts) for i in range(3)],'max':[max(p[i] for p in pts) for i in range(3)],'bvh':BVHTree.FromPolygons(pts,faces)})
 return out
def crossings(a,b):
 hits=[]
 for x in a:
  for y in b:
   if any(x['min'][i]>y['max'][i] or y['min'][i]>x['max'][i] for i in range(3)):continue
   pairs=x['bvh'].overlap(y['bvh'])
   if pairs:hits.append({'own':x['path'],'peer':y['path'],'triangle_pairs':len(pairs)})
 return hits
own=Usd.Stage.Open(str(D/'LowerConsole.usdz'));owngeo=geometry(own);check(own.GetDefaultPrim().GetPath()=='/LowerConsole','Default root');check(UsdGeom.GetStageMetersPerUnit(own)==1 and UsdGeom.GetStageUpAxis(own)=='Y','Meters and Y-up');check(usdpose(own.GetDefaultPrim())==Matrix.Identity(4),'Identity Cabin root');check(len(owngeo)==I['budget']['meshes'],'Mesh budget matches')
for p in own.Traverse():
 if p.IsA(UsdGeom.Mesh):
  m=UsdGeom.Mesh(p);check(m.GetNormalsInterpolation()=='uniform' and len(m.GetNormalsAttr().Get())==len(m.GetFaceVertexCountsAttr().Get()),'Explicit flat face normals '+str(p.GetPath()))
 check(not any('physics' in a.GetName().lower() for a in p.GetAttributes()),'No physics '+str(p.GetPath()))
for g in owngeo:
 edgecounts={}
 for f in g['faces']:
  for a,b in zip(f,f[1:]+f[:1]):edgecounts[tuple(sorted([a,b]))]=edgecounts.get(tuple(sorted([a,b])),0)+1
 check(all(v==2 for v in edgecounts.values()),'Closed manifold '+g['path'])
for group in I['groups']:check(bool(own.GetPrimAtPath(group['path'])),'Shadow group exists '+group['path'])
for g in owngeo:check(sum(g['path']==r['path'] or g['path'].startswith(r['path']+'/') for r in I['groups'])==1,'Disjoint complete shadow group '+g['path'])
for entry in I['suppressions']+I['protected_mounts']:
 st=Usd.Stage.Open(str(C/entry['component']/(entry['component']+'.usdz')));prim=st.GetPrimAtPath(entry['path']);check(bool(prim),'Referenced node exists '+entry['path']);actual=pose_dict(usdpose(prim));check(all(abs(a-b)<1e-6 for key in actual for a,b in zip(actual[key],entry['pose'][key])),'Full component-relative pose '+entry['path'])
# USDZ checker checks archive structure, materials, valid attributes and ARKit rules.
c=UsdUtils.ComplianceChecker(arkit=True);c.CheckCompliance(str(D/'LowerConsole.usdz'));R['compliance']={'errors':c.GetErrors(),'failed':c.GetFailedChecks(),'warnings':c.GetWarnings()};check(not c.GetErrors() and not c.GetFailedChecks(),'ARKit compliance')
# Mounts retained exactly: import actual peer geometry in their existing runtime frames.
p4=panelpose(P['Panel4']['pose']);p5=panelpose(P['Panel5']['pose']);slot=next(s for s in P['Panel5']['slots'] if s['id']=='Panel5__Engine');engine=p5@Matrix.Translation(Vector(slot['pose']['translation_m']));dsky=p4@Matrix.Translation(Vector((0,.015,.009)))
configs=[('Cabin','Cabin/Cabin.usdz',None),('WindowsLPD','WindowsLPD/WindowsLPD.usdz',None),('PanelInventory','PanelInventory/PanelInventory.usdz',None),('CommanderPanels','CommanderPanels/CommanderPanels.usdz',None),('DSKY','DSKY/DSKY.usdz',dsky),('ACA','HandControllers/ACA.usdz',Matrix.Translation(Vector((-.49,.9075,-.37)))),('DescentRate','DescentControls/DescentRate.usdz',engine),('EngineButtons','EngineControls/EngineButtons.usdz',engine),('InteriorDetails','InteriorDetails/InteriorDetails.usdz',None),('BreakerBanks','BreakerBanks/BreakerBanks.usdz',None),('CautionWarning','CautionWarning/CautionWarning.usdz',None)]
for key,rel,tr in configs:
 path=C/rel
 if key=='PanelInventory':path=D.parents[3]/'Sources/LMKit/Resources/PanelInventory/PanelInventory.usdz'
 if not path.exists():continue
 omit=[r['path'] for r in I['suppressions'] if r['component']==key]
 if key=='PanelInventory':omit+=['/PanelInventory/PlanningLabels','/PanelInventory/Panels/Panel4/Panel4__DSKY/Placeholder','/PanelInventory/Panels/Panel5/Panel5__Engine/Placeholder']
 if key=='CommanderPanels':omit+=['/CommanderPanels/Panel_1/Panel_1_RemovableBacking']
 geo=geometry(Usd.Stage.Open(str(path)),tr,omit);hits=crossings(owngeo,geo);R['peers'][key]={'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'crossings':hits,'mesh_count':len(geo)};check(not hits,'No surface crossings '+key)
# Every DSKY front grid ray must remain open through the face sheet; cavity closed at back.
combined=BVHTree.FromPolygons([p for g in owngeo for p in g['points']],[tuple(sum(len(a['points']) for a in owngeo[:i])+v for v in f) for i,g in enumerate(owngeo) for f in g['faces']])
# Concatenate vertex indices eagerly; no deferred face-index generators.
for x,y in itertools.product([-.10,-.05,0,.05,.10],[-.085,-.04,.015,.07,.115]):
 origin=p4@Vector((x,y,.03));direction=p4.to_3x3()@Vector((0,0,-1));hit=combined.ray_cast(origin,direction,.05);check(hit[0] is None,'DSKY opening ray '+str((x,y)))
# Rear enclosure ray proves covered housing from crewward through open aperture.
origin=p4@Vector((0,.015,.03));direction=p4.to_3x3()@Vector((0,0,-1));hit=combined.ray_cast(origin,direction,.3);check(hit[0] is not None and .19<hit[3]<.205,'Cavity rear closure covers provisional housing')
# Actual signed DES RATE actuator states retain fixed Ry(-90) baseline.
rod=Usd.Stage.Open(str(C/'DescentControls/DescentRate.usdz'))
for angle in [-17,0,17]:
 mat=Matrix.Rotation(math.radians(-90),3,'Y')@Matrix.Rotation(math.radians(angle),3,'X');hits=crossings(owngeo,geometry(rod,engine,overrides={'DescentRate__Actuator':mat}));check(not hits,'DES RATE clearance state '+str(angle))
# 125 presentation poses spanning same +/-11deg runtime angles; no new mechanical assertion.
aca=Usd.Stage.Open(str(C/'HandControllers/ACA.usdz'));tr=Matrix.Translation(Vector((-.49,.9075,-.37)));posehits=[]
for roll,yaw,pitch in itertools.product([-11,-5.5,0,5.5,11],repeat=3):
 overrides={'ACA_Roll':Matrix.Rotation(math.radians(-roll),3,'Z'),'ACA_Yaw':Matrix.Rotation(math.radians(yaw),3,'Y'),'ACA_Pitch':Matrix.Rotation(math.radians(pitch),3,'X')};hits=crossings(owngeo,geometry(aca,tr,overrides=overrides))
 if hits:posehits.append({'pose':[roll,yaw,pitch],'crossings':hits})
R['aca_sampled_sweep']={'degrees':[-11,-5.5,0,5.5,11],'pose_count':125,'intersections':posehits};check(not posehits,'No ACA intersections in125 articulation samples')
R['counts']={'passed':sum(c['passed'] for c in R['checks']),'total':len(R['checks'])};(D/'validation.json').write_text(json.dumps(R,indent=2)+'\n');print('VALIDATION',R['counts'],'CROSSINGS',{k:len(v['crossings']) for k,v in R['peers'].items()},'ACA',len(posehits));assert all(c['passed'] for c in R['checks']),[c for c in R['checks'] if not c['passed']]
