"""Actual USD mesh/contract checks; run with Blender Python to use its USD SDK."""
import bpy,json,math,hashlib,sys
from pathlib import Path
from mathutils import Vector
from pxr import Usd,UsdGeom,UsdShade,UsdUtils
P=Path(__file__).resolve().parent;sys.path.insert(0,str(P));from build import C
c=json.loads((P/'interface.json').read_text());count=0;reports=[]
def check(ok,msg):
 global count
 assert ok,msg;count+=1
for a in c['assets']:
 bpy.ops.wm.open_mainfile(filepath=str(P/(a['root']+'.blend')));s=Usd.Stage.Open(str(P/a['filename']));root=s.GetDefaultPrim();names={p.GetName():p for p in s.Traverse()};ptsall=[];meshcount=triangles=0
 check(UsdGeom.GetStageMetersPerUnit(s)==1,'meters');check(UsdGeom.GetStageUpAxis(s)=='Y','Yup');check(root.GetName()==a['root'],'root');check(not any(o.type in ['LIGHT','CAMERA'] for o in bpy.data.objects),'neutral cameras');check(not any(p.HasAuthoredReferences() or p.HasAuthoredPayloads() for p in s.Traverse()),'self-contained')
 for p in s.Traverse():
  if p.IsA(UsdGeom.Xformable):check(abs(UsdGeom.Xformable(p).GetLocalTransformation().GetDeterminant()-1)<1e-6,'right-handed unit transform')
  if p.IsA(UsdGeom.Imageable):check(UsdGeom.Imageable(p).GetVisibilityAttr().Get()=='inherited','inherited visibility')
  if not p.IsA(UsdGeom.Mesh):continue
  meshcount+=1;m=UsdGeom.Mesh(p);pts=m.GetPointsAttr().Get();idx=m.GetFaceVertexIndicesAttr().Get();fc=m.GetFaceVertexCountsAttr().Get();triangles+=len(fc)
  check(sum(fc)==len(idx) and min(idx)>=0 and max(idx)<len(pts),'valid topology');check(all(math.isfinite(v) for point in pts for v in point),'finite');check(bool(UsdShade.MaterialBindingAPI(p).ComputeBoundMaterial()[0]),'material')
  for i in range(0,len(idx),3):
   x,y,z=[pts[k] for k in idx[i:i+3]];check((y-x).GetCross(z-x).GetLength()>1e-13,'nondegenerate triangles')
 for d in a.get('digits',[]):
  check(names[d['name']].GetParent().GetName()==a['root']+'_Readout','digit direct parent')
  m=UsdGeom.Xformable(names[d['name']]).GetLocalTransformation();check((m.ExtractTranslation()-__import__('pxr').Gf.Vec3d(*d['position_m'])).GetLength()<1e-6,'digit pose')
  for name in d['segments'].values():check(names[name].GetParent().GetName()==d['name'],'independent segments');check(UsdShade.MaterialBindingAPI(names[name]).ComputeBoundMaterial()[0].GetPrim().GetName()=='Timer_EL_Off','neutral blank')
 for control in a.get('controls',[]):
  check(names[control['pivot']].GetParent()==root,'pivot root parent');check(names[control['stem']].GetParent().GetName()==control['pivot'],'stem moving child')
 for o in bpy.data.objects:
  if o.type=='MESH':ptsall.extend(C.inverted().to_3x3()@(o.matrix_world@v.co) for v in o.data.vertices)
 lo=[min(p[i] for p in ptsall) for i in range(3)];hi=[max(p[i] for p in ptsall) for i in range(3)];check(lo[0]>=-a['size_m'][0]/2-1e-6 and hi[0]<=a['size_m'][0]/2+1e-6,'width');check(lo[1]>=-a['size_m'][1]/2-1e-6 and hi[1]<=a['size_m'][1]/2+1e-6,'height')
 cc=UsdUtils.ComplianceChecker(arkit=True,skipVariants=False,rootPackageOnly=False);cc.CheckCompliance(str(P/a['filename']));check(not cc.GetErrors()+cc.GetFailedChecks(),str(cc.GetErrors()+cc.GetFailedChecks()))
 reports.append({'asset':a['filename'],'meshes':meshcount,'triangles':triangles,'bounds_min_m':lo,'bounds_max_m':hi,'compliance':'PASS','warnings':cc.GetWarnings()})
report={'status':'PASS','checks':count,'assets':reports,'hashes':{f.name:hashlib.sha256(f.read_bytes()).hexdigest() for f in P.iterdir() if f.suffix in ['.blend','.usdz','.usdc','.usda'] or f.name in ['build.py','interface.json']},'limits':['No actual time source tested','No Vision Pro assessment','No physical-survey claim']};(P/'validation.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
