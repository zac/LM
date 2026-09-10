"""Blender geometry validator; every exception/reported failure exits nonzero.
Standard Python --check-reports DIR / --check-aca FILE GIT_COMMON_DIR skip geometry.
"""
import hashlib,json,os,sys,traceback
from pathlib import Path

ACA_REVISION='750caea3dea7feeaf5ffea15eedcf2d031cca0be'
ACA_SHA256='df2b00baa607543deedc89ba3a2e87fb5862e5243e02dd104981bd34aef254c5'
ACA_BYTES=96068

def read_pinned_aca(path,git_common_dir):
 data=Path(path).read_bytes()
 if data.startswith(b'version https://git-lfs'):
  # Reject a changed pointer before using it to select any cache object.
  lines=data.decode('ascii').splitlines()
  if f'oid sha256:{ACA_SHA256}' not in lines or f'size {ACA_BYTES}' not in lines:
   raise ValueError(f'ACA pointer does not match reviewed revision {ACA_REVISION}')
  data=(Path(git_common_dir)/'lfs/objects'/ACA_SHA256[:2]/ACA_SHA256[2:4]/ACA_SHA256).read_bytes()
 if len(data)!=ACA_BYTES or hashlib.sha256(data).hexdigest()!=ACA_SHA256:
  raise ValueError(f'ACA bytes do not match reviewed revision {ACA_REVISION}: expected {ACA_SHA256}')
 return data

def require_passing_reports(directory):
 directory=Path(directory)
 validation=json.loads((directory/'validation.json').read_text())
 clearance=json.loads((directory/'clearance.json').read_text())
 windows=json.loads((directory/'windows-clearance.json').read_text())
 failures=[]
 if validation['failed']!=0 or any(c['pass'] is not True for c in validation['checks']):
  failures.append('manifest/USD checks failed')
 if validation['compliance_errors'] or validation['compliance_failed']:
  failures.append('USDZ compliance failed')
 if clearance['neutral_surface_intersections'] or clearance['sampled_surface_intersections'] or clearance['status']=='CONFLICT':
  failures.append('ACA surface intersections')
 if windows['surface_intersections']:
  failures.append('window surface intersections')
 if failures:raise RuntimeError('; '.join(failures))

def main():
 import bpy,json,math,itertools
 from pathlib import Path
 from mathutils import Vector,Matrix
 from mathutils.bvhtree import BVHTree
 from pxr import Usd,UsdGeom,UsdUtils,Gf
 OUT=Path(__file__).resolve().parent
 m=json.loads((OUT/'inventory.json').read_text()); stage=Usd.Stage.Open(str(OUT/'PanelInventory.usdz')); checks=[]
 def check(name,value):
  checks.append({'check':name,'pass':bool(value)})
  if not value: print('FAIL',name)
 check('meters and Y up',UsdGeom.GetStageMetersPerUnit(stage)==1 and UsdGeom.GetStageUpAxis(stage)=='Y')
 slots=[s for p in m['panels'] for s in p['slots']]; ids=[p['id'] for p in m['panels']]+[s['id'] for s in slots]; check('unique stable IDs',len(ids)==len(set(ids)))
 check('labels default hidden',UsdGeom.Imageable(stage.GetPrimAtPath(m['planning_label_layer'])).GetVisibilityAttr().Get()=='invisible')
 cache=UsdGeom.XformCache()
 for p in m['panels']:
  prim=stage.GetPrimAtPath(p['node']); check(p['id']+' panel path',prim)
  actual=cache.GetLocalToWorldTransform(prim).ExtractTranslation(); check(p['id']+' Cabin-relative pose',max(abs(actual[i]-p['pose']['translation_m'][i]) for i in range(3))<1e-6)
  for s in p['slots']:
   for field in ['node','default_placeholder_node','label_node']:check(s['id']+' '+field,stage.GetPrimAtPath(s[field]))
   expected=cache.GetLocalToWorldTransform(stage.GetPrimAtPath(s['node'])); label=cache.GetLocalToWorldTransform(stage.GetPrimAtPath(s['label_node'])); d=label.ExtractTranslation()-expected.ExtractTranslation(); check(s['id']+' separate aligned label',abs(d.GetLength()-.002)<1e-6)
  for a,b in itertools.combinations(p['slots'],2):
   # UV reservations must not overlap even if face depths differ.
   pa=a['pose']['translation_m'];pb=b['pose']['translation_m']; overlap=all(abs(pa[i]-pb[i])<(a['envelope_m'][i]+b['envelope_m'][i])/2-1e-6 for i in (0,1))
   check(a['id']+' disjoint '+b['id'],not overlap)
 checker=UsdUtils.ComplianceChecker(arkit=True);checker.CheckCompliance(str(OUT/'PanelInventory.usdz')); check('USDZ ARKit compliance',not checker.GetErrors() and not checker.GetFailedChecks())
 bpy.ops.wm.open_mainfile(filepath=str(OUT/'PanelInventory.blend'))
 for collection in bpy.data.collections:collection.hide_viewport=False
 bpy.context.view_layer.update()
 for o in bpy.data.objects:
  names=[]; obj=o
  while obj: names.append(obj.name.split('.')[0]);obj=obj.parent
  if names[-1]!='PanelInventory':continue
  path='/'+'/'.join(reversed(names)); prim=stage.GetPrimAtPath(path); check(path+' authored node',prim)
  if prim:
   actual=cache.GetLocalToWorldTransform(prim);check(path+' Blender/USD transform',max(abs(actual[j][i]-o.matrix_world[i][j]) for i in range(4) for j in range(4))<1e-6)
 # Sample actual ACA triangles at the pinned imported pose. This is surface overlap, not a hand-space certification.
 def meshes(s,prefix=None):
  c=UsdGeom.XformCache();result=[]
  for p in s.Traverse():
   if not p.IsA(UsdGeom.Mesh) or (prefix and not str(p.GetPath()).startswith(prefix)):continue
   g=UsdGeom.Mesh(p); mat=c.GetLocalToWorldTransform(p);pts=[Vector(mat.Transform(Gf.Vec3d(*v))) for v in g.GetPointsAttr().Get()];indices=g.GetFaceVertexIndicesAttr().Get();faces=[];j=0
   for n in g.GetFaceVertexCountsAttr().Get():faces.append(tuple(indices[j:j+n]));j+=n
   result.append((str(p.GetPath()),pts,faces))
  return result
 production=meshes(stage,'/PanelInventory/Panels/Panel5/')
 import subprocess,tempfile,shutil,hashlib
 aca_path=OUT.parent/'HandControllers/ACA.usdz'
 gitdir=Path(subprocess.check_output(['git','rev-parse','--git-common-dir'],cwd=OUT,text=True).strip())
 if not gitdir.is_absolute():gitdir=OUT/gitdir
 aca_bytes=read_pinned_aca(aca_path,gitdir)
 tmp=Path(tempfile.mkdtemp(prefix='panel-aca-reference-'));(tmp/'ACA.usdz').write_bytes(aca_bytes)
 aca=Usd.Stage.Open(str(tmp/'ACA.usdz')); overrides={}
 for p in aca.Traverse():
  if p.GetName() in ('ACA_Roll','ACA_Yaw','ACA_Pitch'):
   xf=UsdGeom.Xformable(p); original=xf.GetLocalTransformation();xf.ClearXformOpOrder();op=xf.AddTransformOp();overrides[p.GetName()]=(op,original)
 shift=Vector((-.49,.9075,-.37)); pairs={}; neutral=[]; bvhprod=[(n,BVHTree.FromPolygons(v,f)) for n,v,f in production]; sample_bounds=[]
 for angles in itertools.product(range(-11,12,11),repeat=3):
  for name,deg,axis in zip(('ACA_Roll','ACA_Yaw','ACA_Pitch'),angles,((0,0,-1),(0,1,0),(1,0,0))):
   op,orig=overrides[name];r=Gf.Matrix4d(1);r.SetRotate(Gf.Rotation(Gf.Vec3d(*axis),deg));op.Set(r*orig)
  parts=meshes(aca);allpts=[]
  for name,pts,faces in parts:
   pts=[p+shift for p in pts];allpts+=pts;bvh=BVHTree.FromPolygons(pts,faces)
   for pn,pbvh in bvhprod:
    hits=pbvh.overlap(bvh)
    if hits:
     key=pn+' | '+name;pairs[key]=pairs.get(key,0)+1
     if angles==(0,0,0):neutral.append({'panel_mesh':pn,'ACA_mesh':name,'intersecting_triangle_pairs':len(hits)})
  sample_bounds+=allpts
 bounds=[[min(v[i] for v in sample_bounds) for i in range(3)],[max(v[i] for v in sample_bounds) for i in range(3)]]
 clearance={'ACA_revision':ACA_REVISION,'ACA_sha256':ACA_SHA256,'method':'27 actual triangle meshes; roll/yaw/pitch grid -11,0,+11 degrees. BVH surface intersections; no containment, continuous sweep or hand clearance claim. Housing is fixed; moving pivots follow pinned interface.','ACA_root_cabin_m':list(shift),'panel5_face_pose':next(p for p in m['panels'] if p['id']=='Panel5')['pose'],'runtime_baseline':'LM11f7335 LMCommanderStationGeometry.swift center(-.5588,.88,-.30), rotX=-75, depth .038; face conversion agrees with Cabin mount within 1um','neutral_surface_intersections':neutral,'sampled_surface_intersections':pairs,'sampled_ACA_aabb_cabin_m':bounds,'status':'CONFLICT' if pairs else 'no sampled surface intersections; broad AABB remains only a warning'}
 (OUT/'clearance.json').write_text(json.dumps(clearance,indent=2)+'\n')
 (OUT/'validation.json').write_text(json.dumps({'checks':checks,'failed':sum(not c['pass'] for c in checks),'compliance_errors':checker.GetErrors(),'compliance_failed':checker.GetFailedChecks()},indent=2)+'\n')
 print('VALIDATION',len(checks),'checks',sum(not c['pass'] for c in checks),'failed; ACA',len(pairs),'mesh pairs')
 # Final Windows asset is a read-only pinned LFS reference from the shared object store.
 import hashlib,subprocess,shutil
 pointer=subprocess.check_output(['git','show','5699e64:Assets/Cockpit/Components/WindowsLPD/WindowsLPD.usdz'],cwd=OUT)
 if pointer.startswith(b'version https://git-lfs'):
  digest=pointer.decode().split('sha256:')[1].split()[0];source=gitdir/'lfs/objects'/digest[:2]/digest[2:4]/digest
  assert hashlib.sha256(source.read_bytes()).hexdigest()==digest
  shutil.copyfile(source,tmp/'WindowsLPD.usdz')
 else:(tmp/'WindowsLPD.usdz').write_bytes(pointer)
 windows=meshes(Usd.Stage.Open(str(tmp/'WindowsLPD.usdz')))
 def bb(pts):return ([min(p[i] for p in pts) for i in range(3)],[max(p[i] for p in pts) for i in range(3)])
 def broad(a,b):return all(a[0][i]<=b[1][i] and b[0][i]<=a[1][i] for i in range(3))
 wm=[(n,BVHTree.FromPolygons(v,f),bb(v)) for n,v,f in windows];hits=[]
 for n,v,f in meshes(stage,'/PanelInventory/Panels/'):
  b=bb(v);bvh=None
  for wn,wbvh,wb in wm:
   if not broad(b,wb):continue
   if bvh is None:bvh=BVHTree.FromPolygons(v,f)
   pairs=bvh.overlap(wbvh)
   if pairs:hits.append({'panel_mesh':n,'window_mesh':wn,'triangle_pairs':len(pairs)})
 (OUT/'windows-clearance.json').write_text(json.dumps({'reference_commit':'5699e64','interface_commit':'80c9b2d','method':'triangle surface crossing; labels excluded; containment and service clearances not tested','surface_intersections':hits},indent=2)+'\n');print('WINDOWS_CROSSINGS',len(hits))

 require_passing_reports(OUT)

if __name__=='__main__':
 try:
  if len(sys.argv)>1 and sys.argv[1]=='--check-reports':
   require_passing_reports(sys.argv[2])
  elif len(sys.argv)>1 and sys.argv[1]=='--check-aca':
   read_pinned_aca(Path(sys.argv[2]),Path(sys.argv[3]))
  else:main()
 except Exception:
  traceback.print_exc()
  # Blender can swallow script exceptions and return 0 without --python-exit-code.
  # Reports have already been written for ordinary check/collision failures.
  sys.stdout.flush();sys.stderr.flush();os._exit(1)
