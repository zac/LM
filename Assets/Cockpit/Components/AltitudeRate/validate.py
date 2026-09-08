"""Validate actual neutral Blender/USD asset and transform contract; no renders."""
import bpy,json,math,hashlib,sys
from pathlib import Path
from mathutils import Vector
from pxr import Usd,UsdGeom,UsdShade,UsdUtils
OUT=Path(__file__).resolve().parent;sys.path.insert(0,str(OUT));from build import C,q
bpy.ops.wm.open_mainfile(filepath=str(OUT/'AltitudeRate.blend'))
c=json.loads((OUT/'interface.json').read_text());s=Usd.Stage.Open(str(OUT/'AltitudeRate.usdz'));count=0
def check(ok,msg):
 global count
 assert ok,msg;count+=1
check(UsdGeom.GetStageMetersPerUnit(s)==1,'meters');check(UsdGeom.GetStageUpAxis(s)=='Y','Yup');check(str(s.GetDefaultPrim().GetPath())=='/AltitudeRate','root')
check(not any(o.type in ['LIGHT','CAMERA'] for o in bpy.data.objects),'no cameras/lights');check(not any(p.HasAuthoredReferences() or p.HasAuthoredPayloads() for p in s.Traverse()),'self contained')
mesh_count=triangles=0;bounds=[]
for p in s.Traverse():
 if p.IsA(UsdGeom.Xformable):
  m=UsdGeom.Xformable(p).GetLocalTransformation();check(abs(m.GetDeterminant()-1)<1e-6,'proper unit transform '+str(p.GetPath()))
 if p.IsA(UsdGeom.Imageable):check(UsdGeom.Imageable(p).GetVisibilityAttr().Get()=='inherited','re-enable-safe visibility')
 if not p.IsA(UsdGeom.Mesh):continue
 mesh_count+=1;m=UsdGeom.Mesh(p);pts=m.GetPointsAttr().Get();idx=m.GetFaceVertexIndicesAttr().Get();fc=m.GetFaceVertexCountsAttr().Get();triangles+=len(fc)
 check(sum(fc)==len(idx) and min(idx)>=0 and max(idx)<len(pts),'valid topology');check(all(math.isfinite(v) for p in pts for v in p),'finite');check(bool(UsdShade.MaterialBindingAPI(p).ComputeBoundMaterial()[0]),'material')
for key in ['altitude','altitude_rate']:
 d=c[key];check(len({r['name'] for r in d['rows']})==len(d['rows']),'unique rows');check(q(0,d)==0,'zero q')
 for row in d['rows']:
  o=bpy.data.objects[row['name']];check(o.parent.name==d['group'],'row parent')
  for child in o.children_recursive:
   for v in child.data.vertices:
    local=C.inverted().to_3x3()@(child.matrix_local@v.co);check(abs(local.y)<=.0035+1e-7,'row fits clipping margin')
  expected=d['neutral_rows'][row['name']]['position_m'];actual=C.inverted()@o.matrix_local@C
  check((actual.translation-Vector(expected)).length<1e-6,'neutral row pose')
for o in bpy.data.objects:
 if o.type=='MESH':bounds.extend(C.inverted().to_3x3()@(o.matrix_world@v.co) for v in o.data.vertices)
lo=[min(p[i] for p in bounds) for i in range(3)];hi=[max(p[i] for p in bounds) for i in range(3)]
check(lo[0]>=-.04101 and hi[0]<=.04101 and lo[1]>=-.07251 and hi[1]<=.07251,'within approved XY envelope')
cc=UsdUtils.ComplianceChecker(arkit=True,skipVariants=False,rootPackageOnly=False);cc.CheckCompliance(str(OUT/'AltitudeRate.usdz'));issues=cc.GetErrors()+cc.GetFailedChecks();check(not issues,str(issues))
report={'status':'PASS','checks':count,'meshes':mesh_count,'triangles':triangles,'bounds_min':lo,'bounds_max':hi,'usdz_compliance':'PASS','compliance_warnings':cc.GetWarnings(),'visibility':'all inherited; unused rows/shutters parked inside opaque housing','mesh_clip_margin_m':.0035,'source_and_interface_hashes':{f.name:hashlib.sha256(f.read_bytes()).hexdigest() for f in OUT.iterdir() if f.is_file() and f.name in ['build.py','interface.json','AltitudeRate.blend','AltitudeRate.usda','AltitudeRate.usdc','AltitudeRate.usdz']}}
(OUT/'validation.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
