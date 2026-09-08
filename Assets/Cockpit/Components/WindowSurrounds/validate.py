"""Actual USD mesh and protected optical-ray validation, no simulation."""
import bpy,json,math,hashlib,sys
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from pxr import Usd,UsdGeom,UsdShade,UsdUtils
P=Path(__file__).resolve().parent;sys.path.insert(0,str(P));from build import C
bpy.ops.wm.open_mainfile(filepath=str(P/'WindowSurrounds.blend'));c=json.loads((P/'interface.json').read_text());w=json.loads((P.parent/'WindowsLPD/interface-v1.json').read_text());s=Usd.Stage.Open(str(P/'WindowSurrounds.usdz'));checks=0;meshcount=triangles=0;rayhits=[];allverts=[];allfaces=[]
def check(ok,msg):
 global checks
 assert ok,msg;checks+=1
check(UsdGeom.GetStageUpAxis(s)=='Y','Y up');check(UsdGeom.GetStageMetersPerUnit(s)==1,'meters');check(s.GetDefaultPrim().GetName()=='WindowSurrounds','root');check(not any(o.type in ['LIGHT','CAMERA'] for o in bpy.data.objects),'no preview nodes');names=set()
for p in s.Traverse():
 if p.IsA(UsdGeom.Xformable):check(abs(UsdGeom.Xformable(p).GetLocalTransformation().GetDeterminant()-1)<1e-6,'right-handed unit transform')
 if p.IsA(UsdGeom.Imageable):check(UsdGeom.Imageable(p).GetVisibilityAttr().Get()=='inherited','visibility inherited')
 if not p.IsA(UsdGeom.Mesh):continue
 meshcount+=1;m=UsdGeom.Mesh(p);points=m.GetPointsAttr().Get();counts=m.GetFaceVertexCountsAttr().Get();indices=m.GetFaceVertexIndicesAttr().Get();triangles+=len(counts);check(sum(counts)==len(indices),'topology');check(min(indices)>=0 and max(indices)<len(points),'valid indices');check(all(math.isfinite(x) for q in points for x in q),'finite');check(bool(UsdShade.MaterialBindingAPI(p).ComputeBoundMaterial()[0]),'bound material');check(p.GetName() not in names,'globally unique meshes');names.add(p.GetName())
 for i in range(0,len(indices),3):a,b,d=[points[k] for k in indices[i:i+3]];check((b-a).GetCross(d-a).GetLength()>1e-13,'nonzero triangle')
for o in bpy.data.objects:
 if o.type!='MESH':continue
 import bmesh
 bm=bmesh.new();bm.from_mesh(o.data);check(all(e.is_manifold for e in bm.edges),'closed metal section '+o.name);check(bm.calc_volume(signed=True)>1e-12,'outward solid '+o.name);bm.free()
 o.data.calc_loop_triangles();offset=len(allverts);allverts.extend(C.inverted().to_3x3()@(o.matrix_world@v.co) for v in o.data.vertices);allfaces.extend(tuple(offset+i for i in t.vertices) for t in o.data.loop_triangles)
bvh=BVHTree.FromPolygons(allverts,allfaces,all_triangles=True);rays=0
for side,eye in w['eyes'].items():
 eye=Vector(eye);a,b,d=[Vector(p) for p in w['forward'][side+'_Window_Inner']['corners']]
 for i in range(1,41):
  for j in range(1,41-i):
   u=i/41;v=j/41;target=a*(1-u-v)+b*u+d*v;delta=target-eye;rays+=1;hit=bvh.ray_cast(eye,delta.normalized(),delta.length-.001)
   if hit[0] is not None:rayhits.append({'side':side,'target':list(target),'hit':list(hit[0])})
cc=UsdUtils.ComplianceChecker(arkit=True,skipVariants=False,rootPackageOnly=False);cc.CheckCompliance(str(P/'WindowSurrounds.usdz'));check(not cc.GetErrors()+cc.GetFailedChecks(),str(cc.GetErrors()+cc.GetFailedChecks()))
for sub in c['suppressions']:check(sub['component']=='Cabin' and '/Cutaway_Forward/' in sub['path'] and '_Front_' in sub['path'],'only replaced leaf cheek meshes')
report={'status':'PASS' if not rayhits else 'FAIL optical obstruction','checks':checks,'meshes':meshcount,'triangles':triangles,'aperture_grid_rays':rays,'blocked_rays':rayhits,'compliance_warnings':cc.GetWarnings(),'hashes':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in P.iterdir() if p.name in ['build.py','interface.json','WindowSurrounds.blend','WindowSurrounds.usda','WindowSurrounds.usdc','WindowSurrounds.usdz']},'protected_source_hashes':{component:hashlib.sha256((P.parent/component/(component+'.usdz')).read_bytes()).hexdigest() for component in ['Cabin','WindowsLPD']},'limitations':['Crew rays use accepted provisional eye and triangular aperture datums','Does not certify optical survey, full movement clearance or headset appearance']};(P/'validation.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({k:v for k,v in report.items() if k!='blocked_rays'},indent=2));print('BLOCKED_RAYS',len(rayhits));check(not rayhits,'aperture occlusion')
