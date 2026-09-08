"""Independent USD contract, solid-face coverage and unchanged assembled instrument rays."""
from pathlib import Path
import json,math,hashlib
import bpy
from mathutils import Vector,Matrix,Quaternion
from mathutils.bvhtree import BVHTree
from pxr import Usd,UsdGeom,UsdUtils,Gf
O=Path(__file__).resolve().parent;D=O.parent;m=json.loads((O/'interface.json').read_text());checks=[];failures=[]
def check(n,v,detail=None):
 r={'name':n,'pass':bool(v)}
 if detail is not None:r['detail']=detail
 checks.append(r)
 if not v:failures.append(n)
s=Usd.Stage.Open(str(O/'InstrumentConsole.usdz'));cache=UsdGeom.XformCache();root=s.GetDefaultPrim();check('root identity',str(root.GetPath())==m['root'] and cache.GetLocalToWorldTransform(root)==Gf.Matrix4d(1));check('units meters Y up',UsdGeom.GetStageMetersPerUnit(s)==1 and UsdGeom.GetStageUpAxis(s)=='Y')
verts=[];tris=[];paths=[];meshcount=0
for p in s.Traverse():
 check('no instrument or camera geometry '+str(p.GetPath()),not p.IsA(UsdGeom.Camera) and not any(t in p.GetName() for t in ['Needle','Ball','Digit','Pivot']))
 if not p.IsA(UsdGeom.Mesh):continue
 meshcount+=1;paths.append(str(p.GetPath()));g=UsdGeom.Mesh(p);a=cache.GetLocalToWorldTransform(p);pts=[Vector(a.Transform(Gf.Vec3d(*v))) for v in g.GetPointsAttr().Get()];ids=g.GetFaceVertexIndicesAttr().Get();counts=g.GetFaceVertexCountsAttr().Get();check(str(p.GetPath())+' triangulated finite',all(n==3 for n in counts) and all(math.isfinite(c) for v in pts for c in v));start=len(verts);verts+=pts;tris += [tuple(start+ids[i+j] for j in range(3)) for i in range(0,len(ids),3)]
 check(str(p.GetPath())+' explicit face normals',g.GetNormalsInterpolation()=='faceVarying' and len(g.GetNormalsAttr().Get())==len(ids))
 check(str(p.GetPath())+' exactly one shadow group',sum(str(p.GetPath()).startswith(g['path']+'/') for g in m['groups'])==1)
tree=BVHTree.FromPolygons(verts,tris,all_triangles=True)
for group in m['groups']:check('declared group '+group['path'],bool(s.GetPrimAtPath(group['path'])))
seen=set()
for r in m['suppressions']+m['protected_mounts']:
 st=Usd.Stage.Open(str(D/r['component']/(r['component']+'.usdz')));p=st.GetPrimAtPath(r['path']);check('source path '+r['path'],bool(p));xf=UsdGeom.XformCache().GetLocalToWorldTransform(p);t=r['pose'];q=xf.ExtractRotationQuat();check('exact source pose '+r['path'],max(abs(a-b) for a,b in zip(xf.ExtractTranslation(),t['position_m']))<1e-7 and max(abs(a-b) for a,b in zip(list(q.GetImaginary())+[q.GetReal()],t['rotation_quaternion_xyzw']))<1e-7)
for r in m['suppressions']:
 check('unique suppression '+r['path'],r['path'] not in seen);seen.add(r['path']);check('protected datum not suppressed '+r['path'],not any(p['component']==r['component'] and (p['path']==r['path'] or p['path'].startswith(r['path']+'/')) for p in m['protected_mounts']))
for f,sha in m['accepted_input_sha256'].items():check('accepted source bytes '+f,hashlib.sha256((D/f).read_bytes()).hexdigest()==sha)
inv=json.loads((O/'evidence/accepted-inventory.json').read_text())
def pose(p):
 x,y,z,w=p.get('quaternion_xyzw',[0,0,0,1]);return Matrix.Translation(Vector(p['translation_m']))@Quaternion((w,x,y,z)).to_matrix().to_4x4()
panels={p['id']:p for p in inv['panels'] if p['id'] in ['Panel1','Panel2','Panel3']}
# Independent frontal rays across region gaps prove physical backing instead of disjoint placeholder islands.
for pid,p in panels.items():
 xf=pose(p['pose']);xoff=p['pose']['translation_m'][0];xmin,xmax=(-.399-xoff,.399-xoff) if pid!='Panel3' else(-.484,.484)
 if pid=='Panel1':xmax=-.001-xoff
 if pid=='Panel2':xmin=.001-xoff
 ymin,ymax=(-.249,.249) if pid!='Panel3' else(-.089,.089)
 cx,cy=(-.055,-.015) if pid=='Panel1' else(.06,-.115)
 for ix in range(21):
  for iy in range(21):
   x=xmin+(xmax-xmin)*ix/20;y=ymin+(ymax-ymin)*iy/20
   if pid!='Panel3' and abs(x-cx)<.0651 and abs(y-cy)<.0651:continue
   start=xf@Vector((x,y,.08));end=xf@Vector((x,y,-.02));hit=tree.ray_cast(start,(end-start).normalized(),(end-start).length)[0]
   check(f'{pid} solid face sample {ix},{iy}',hit is not None)
# Asset and accepted Blender authored poses agree, without interpreting imported coordinate correction.
bpy.ops.wm.open_mainfile(filepath=str(O/'InstrumentConsole.blend'));bpy.context.view_layer.update()
for o in bpy.data.objects:
 names=[];a=o
 while a:names.append(a.name);a=a.parent
 path='/'+'/'.join(reversed(names));p=s.GetPrimAtPath(path);check('authored path '+path,bool(p));xf=cache.GetLocalToWorldTransform(p);check('authored transform '+path,max(abs(xf[j][i]-o.matrix_world[i][j]) for i in range(4) for j in range(4))<1e-6)
# Crew rays to actual accepted mounted faces and housings. Review assembly has source paths and input hashes.
bpy.ops.wm.open_mainfile(filepath='/private/tmp/instrument-console-review.blend');bpy.context.view_layer.update();rayresults=[]
for ob in bpy.data.objects:
 if ob.type!='MESH' or not ob.get('source_component') or ob.hide_viewport:continue
 comp=ob['source_component'];path=ob['source_path'];target=None
 if comp in ['CDR_FDAI','LMP_FDAI']:
  if 'FDAI_Glass' not in path:continue
  target=sum((ob.matrix_world@v.co for v in ob.data.vertices),Vector())/len(ob.data.vertices)
 elif comp in ['AltitudeRate','CrossPointer','PropulsionInstruments','CommanderLunarContact','PilotLunarContact','CautionWarning','MissionTimer','EventTimer','EventTimerControls','AttitudeMode']:
  if not any(t.lower() in path.lower() for t in ['DialFace','DisplayFace','LightFace','CrossPointer_Face','FacePlate','Grip','ButtonTop']):continue
  target=sum((ob.matrix_world@v.co for v in ob.data.vertices),Vector())/len(ob.data.vertices)
 if target is None:continue
 pilot=comp in ['LMP_FDAI','PilotLunarContact'] or target.x>0 and comp=='CautionWarning';eye=Vector((.5588 if pilot else -.5588,1.78,-.38));d=target-eye;hit=tree.ray_cast(eye,d.normalized(),d.length-.0005);check('console does not occlude '+comp+path,hit[0] is None);rayresults.append({'component':comp,'surface':path,'target_cabin_m':list(target),'console_hit':list(hit[0]) if hit[0] is not None else None})
check('both FDAI actual glass targets probed',all(any(r['component']==n for r in rayresults) for n in ['CDR_FDAI','LMP_FDAI']))
check('multiple actual instrument faces probed',len(rayresults)>=12,len(rayresults))
# Rear housings disappear behind console plus unchanged mounting plates/bezels.
# Opposite housing side rays can legitimately pass the bore and hit the instrument front itself.
fv=list(verts);ft=list(tris)
fdai=Usd.Stage.Open(str(D/'FDAI/FDAI.usdz'));fc=UsdGeom.XformCache()
for pid in ['Panel1','Panel2']:
 instrument=next(q for q in panels[pid]['slots'] if q['id']==pid+'__FDAI');mount=pose(panels[pid]['pose'])@pose(instrument['pose'])
 for prim in fdai.Traverse():
  if not prim.IsA(UsdGeom.Mesh) or not any(t in str(prim.GetPath()) for t in ['FDAI_MountingPlate/','FDAI_FaceBezel/']):continue
  geom=UsdGeom.Mesh(prim);xf=fc.GetLocalToWorldTransform(prim);offset=len(fv);fv += [mount@Vector(xf.Transform(Gf.Vec3d(*v))) for v in geom.GetPointsAttr().Get()];ids=geom.GetFaceVertexIndicesAttr().Get();ns=geom.GetFaceVertexCountsAttr().Get();cursor=0
  for n in ns:
   for j in range(1,n-1):ft.append((offset+ids[cursor],offset+ids[cursor+j],offset+ids[cursor+j+1]))
   cursor+=n
housing_tree=BVHTree.FromPolygons(fv,ft,all_triangles=True)
# Rear housings disappear behind fixed assembly from own-station viewpoints.
for pid,cx,cy,mountz,eye in [('Panel1',-.055,-.015,.016,(-.5588,1.78,-.38)),('Panel2',.06,-.115,0,(.5588,1.78,-.38))]:
 xf=pose(panels[pid]['pose']);e=Vector(eye)
 for side in [-1,1]:
  for depth in [-.05,-.12,-.19]:
   target=xf@Vector((cx+side*.0635,cy,mountz+depth));d=target-e;hit=housing_tree.ray_cast(e,d.normalized(),d.length-.0005)[0];check(f'{pid} housing hidden side{side} depth{depth}',hit is not None)
checker=UsdUtils.ComplianceChecker(arkit=True);checker.CheckCompliance(str(O/'InstrumentConsole.usdz'));check('ARKit USDZ compliance',not checker.GetErrors() and not checker.GetFailedChecks())
report={'passed':sum(c['pass'] for c in checks),'failed':len(failures),'failures':failures,'meshes':meshcount,'triangles':len(tris),'checks':checks,'face_rays':rayresults,'compliance_errors':checker.GetErrors(),'compliance_failed':checker.GetFailedChecks(),'compliance_warnings':checker.GetWarnings(),'limitations':['Finite sampled front and housing rays, not continuous sweep or headset acceptance','Accepted rear instrument housings and enclosure penetrate existing forward pressure-shell volume; hidden overlap is not mechanical fit','Workbench review omits transparent glass only visually; ray targets use unchanged glass geometry','Coordinator owns package/runtime fallback checks']}
(O/'validation.json').write_text(json.dumps(report,indent=2)+'\n');print('VALIDATION',report['passed'],'passed',report['failed'],'failed',failures)
if failures:raise SystemExit(1)
