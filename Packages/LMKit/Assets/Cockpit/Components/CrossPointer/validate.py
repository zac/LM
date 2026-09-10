"""Targeted saved-artifact validation; no runtime/source-frame claims. Writes owned reports."""
import bpy,json,hashlib,math
from pathlib import Path
from pxr import Usd,UsdGeom,UsdUtils,Gf
OUT=Path(__file__).resolve().parent
m=json.loads((OUT/'interface.json').read_text()); stage=Usd.Stage.Open(str(OUT/'CrossPointer.usdz'));cache=UsdGeom.XformCache();checks=[]
def check(name,value):
 checks.append({'check':name,'pass':bool(value)})
 if not value:raise AssertionError(name)
def close(a,b,tol=1e-6):return max(abs(x-y) for x,y in zip(a,b))<tol
check('metric Y up',UsdGeom.GetStageMetersPerUnit(stage)==1 and UsdGeom.GetStageUpAxis(stage)=='Y')
root=stage.GetDefaultPrim();check('default root',str(root.GetPath())==m['root']);check('identity root',cache.GetLocalToWorldTransform(root)==Gf.Matrix4d(1))
check('no cameras lights in neutral asset',not any('Light' in p.GetTypeName() or p.IsA(UsdGeom.Camera) for p in stage.Traverse()))
check('no external composition or textures',not any(p.HasAuthoredReferences() or p.HasAuthoredPayloads() for p in stage.Traverse()))
mesh_count=0;triangles=0;allpoints=[]
for prim in stage.Traverse():
 if prim.IsA(UsdGeom.Mesh):
  mesh_count+=1;g=UsdGeom.Mesh(prim);pts=g.GetPointsAttr().Get();xf=cache.GetLocalToWorldTransform(prim);allpoints.extend(xf.Transform(Gf.Vec3d(*p)) for p in pts);counts=g.GetFaceVertexCountsAttr().Get();triangles+=sum(n-2 for n in counts)
  check(str(prim.GetPath())+' finite points',all(math.isfinite(c) for p in pts for c in p));check(str(prim.GetPath())+' triangulated',all(n==3 for n in counts))
bounds=[[min(p[i] for p in allpoints) for i in range(3)],[max(p[i] for p in allpoints) for i in range(3)]]
check('face fits declared slot at unit scale',bounds[1][0]-bounds[0][0]<.140 and bounds[1][1]-bounds[0][1]<.065)
check('declared 61mm square preserved',close([bounds[1][i]-bounds[0][i] for i in (0,1)],[.061,.061]))
check('LO velocity range SI conversion',abs(m['supported_mode']['full_scale_abs_fps']*.3048-m['supported_mode']['full_scale_abs_mps'])<1e-10)
fixed=stage.GetPrimAtPath('/CrossPointer/Fixed');before=cache.GetLocalToWorldTransform(fixed)
for key in ('lateral','forward'):
 row=m['needles'][key];prim=stage.GetPrimAtPath(row['node']);check(key+' explicit node is Xform',prim.IsA(UsdGeom.Xform));check(key+' neutral datum',close(cache.GetLocalToWorldTransform(prim).ExtractTranslation(),row['neutral_translation_m']))
 mesh=UsdGeom.Mesh(stage.GetPrimAtPath(row['mesh']));pts=mesh.GetPointsAttr().Get();op=UsdGeom.Xformable(prim).GetOrderedXformOps()[0];orig=op.Get();axis=row['travel_axis']
 for delta in row['travel_m']+[0]:
  pos=[v+delta*a for v,a in zip(row['neutral_translation_m'],axis)];mat=Gf.Matrix4d(1);mat.SetTranslate(Gf.Vec3d(*pos));op.Set(mat);cache.Clear();actual=cache.GetLocalToWorldTransform(prim);check(key+f' at {delta} preserves fixed frame',cache.GetLocalToWorldTransform(fixed)==before)
  ps=[cache.GetLocalToWorldTransform(mesh.GetPrim()).Transform(Gf.Vec3d(*p)) for p in pts];check(key+f' at {delta} inside aperture',all(abs(p[0])<.0245 and abs(p[1])<.0245 for p in ps));check(key+f' at {delta} numeric displacement',close(actual.ExtractTranslation(),pos))
 op.Set(orig);cache.Clear()
# Hide group without deleting fixed scale (native test complements this).
check('two separate moving children',len(list(stage.GetPrimAtPath(m['needles']['group']).GetChildren()))==2)
checker=UsdUtils.ComplianceChecker(arkit=True);checker.CheckCompliance(str(OUT/'CrossPointer.usdz'));check('ARKit USDZ compliance',not checker.GetErrors() and not checker.GetFailedChecks())
bpy.ops.wm.open_mainfile(filepath=str(OUT/'CrossPointer.blend'));bpy.context.view_layer.update()
check('Blender metric',bpy.context.scene.unit_settings.scale_length==1)
check('Blender no external libraries',not bpy.data.libraries)
for o in bpy.data.objects:
 names=[];p=o
 while p is not None:names.append(p.name);p=p.parent
 path='/'+'/'.join(reversed(names));prim=stage.GetPrimAtPath(path);check(path+' source node exported',bool(prim))
 actual=cache.GetLocalToWorldTransform(prim);check(path+' source physical transform',max(abs(actual[j][i]-o.matrix_world[i][j]) for i in range(4) for j in range(4))<1e-6)
report={'checks':checks,'passed':len(checks),'failed':0,'meshes':mesh_count,'triangles':triangles,'bounds_m':bounds,'compliance_errors':checker.GetErrors(),'compliance_failed':checker.GetFailedChecks(),'compliance_warnings':checker.GetWarnings(),'limitations':['geometry validation only','simulation frame/polarity tests owned by LM','mechanical panel cutout and rear seating not qualified','no headset acceptance']}
(OUT/'validation.json').write_text(json.dumps(report,indent=2)+'\n');print('PASS',len(checks),'checks',mesh_count,'meshes',triangles,'triangles')
