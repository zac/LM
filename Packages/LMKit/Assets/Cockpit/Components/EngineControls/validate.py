"""Blender Python: native USD, geometry/transform, source hash and sampled ACA clearance."""
import bpy,json,math,hashlib,itertools,sys,traceback
from pathlib import Path
from pxr import Usd,UsdGeom,UsdUtils,Gf
from mathutils import Vector,Matrix,Quaternion
from mathutils.bvhtree import BVHTree
D=Path(__file__).resolve().parent
checks=[]
def ck(name,value):
 checks.append({'name':name,'pass':bool(value)})
def meshes(st):
 c=UsdGeom.XformCache();out=[]
 for p in st.Traverse():
  if not p.IsA(UsdGeom.Mesh):continue
  g=UsdGeom.Mesh(p);m=c.GetLocalToWorldTransform(p);v=[Vector(m.Transform(Gf.Vec3d(*a))) for a in g.GetPointsAttr().Get()]; idx=g.GetFaceVertexIndicesAttr().Get();f=[];j=0
  for n in g.GetFaceVertexCountsAttr().Get():f.append(tuple(idx[j:j+n]));j+=n
  out.append((str(p.GetPath()),v,f))
 return out
def main():
 config=json.loads((D/'interface.json').read_text()); inv=json.loads((D.parent/'PanelInventory/inventory.json').read_text()); report=[]
 for item in config['components']:
  st=Usd.Stage.Open(str(D/item['asset']));root=st.GetDefaultPrim();ck(item['id']+' root',root.GetName()==item['mount']);ck('meters',UsdGeom.GetStageMetersPerUnit(st)==1);ck('Y up',UsdGeom.GetStageUpAxis(st)=='Y');ck('identity root',UsdGeom.Xformable(root).GetLocalTransformation()==Gf.Matrix4d(1))
  ck('no invisible prims',not any(UsdGeom.Imageable(p).GetVisibilityAttr().Get()=='invisible' for p in st.Traverse() if p.IsA(UsdGeom.Imageable)))
  checker=UsdUtils.ComplianceChecker(arkit=True);checker.CheckCompliance(str(D/item['asset']));ck('ARKit compliance',not checker.GetErrors() and not checker.GetFailedChecks())
  geo=meshes(st);points=[v for _,vs,_ in geo for v in vs];bb=[[min(v[i] for v in points) for i in range(3)],[max(v[i] for v in points) for i in range(3)]]
  moving=[]
  for name in item.get('moving',[]):
   p=st.GetPrimAtPath('/'+item['mount']+'/'+name);ck(name+' independent direct root child',bool(p));m=UsdGeom.Xformable(p).GetLocalTransformation();moving.append({'name':name,'translation_m':list(m.ExtractTranslation())})
  for name in item.get('indicators',[item.get('light_face')]):ck(str(name)+' separate mesh',any(p.GetName()==name and p.IsA(UsdGeom.Mesh) for p in st.Traverse()))
  report.append({'id':item['id'],'bounds_m':bb,'moving':moving,'meshes':len(geo),'triangles':sum(sum(len(f)-2 for f in fs) for _,_,fs in geo)})
 engine=Usd.Stage.Open(str(D/'EngineButtons.usdz'));engineGeo=meshes(engine);ebv=[(n,BVHTree.FromPolygons(v,f)) for n,v,f in engineGeo]
 descent=Usd.Stage.Open(str(D.parent/'DescentControls/DescentRate.usdz'));part=descent.GetPrimAtPath('/DescentRate_Mount/DescentRate__Actuator');xf=UsdGeom.Xformable(part);base=xf.GetLocalTransformation();pos=base.ExtractTranslation();xf.ClearXformOpOrder();op=xf.AddTransformOp();hits=[]
 for angle in [-17,0,17]:
  rot=Gf.Matrix4d(1);rot.SetRotate(Gf.Rotation(Gf.Vec3d(1,0,0),angle));orient=Gf.Matrix4d(1);orient.SetRotate(Gf.Rotation(Gf.Vec3d(0,1,0),-90));m=rot*orient;m.SetTranslateOnly(pos);op.Set(m)
  for n,v,f in meshes(descent):
   if 'NeutralBacking' in n:continue
   tree=BVHTree.FromPolygons(v,f)
   for en,et in ebv:
    count=len(et.overlap(tree))
    if count:hits.append({'angle':angle,'engine':en,'descent':n,'triangle_pairs':count})
 ck('DES RATE 3 poses no surface crossing',not hits)
 p5=next(p for p in inv['panels'] if p['id']=='Panel5');slot=next(s for s in p5['slots'] if s['id']=='Panel5__Engine');p=p5['pose'];q=p['quaternion_xyzw'];M=Matrix.Translation(Vector(p['translation_m']))@Quaternion((q[3],*q[:3])).to_matrix().to_4x4()@Matrix.Translation(Vector(slot['pose']['translation_m']))
 bv=[(n,BVHTree.FromPolygons([M@v for v in vs],fs)) for n,vs,fs in engineGeo];acaPath=D.parent/'HandControllers/ACA.usdz';aca=Usd.Stage.Open(str(acaPath));pivots={}
 for p in aca.Traverse():
  if p.GetName() in ('ACA_Roll','ACA_Yaw','ACA_Pitch'):
   xf=UsdGeom.Xformable(p);orig=xf.GetLocalTransformation();xf.ClearXformOpOrder();pivots[p.GetName()]=(xf.AddTransformOp(),orig)
 ahits=[]
 for angles in itertools.product([-11,0,11],repeat=3):
  for name,deg,axis in zip(('ACA_Roll','ACA_Yaw','ACA_Pitch'),angles,((0,0,-1),(0,1,0),(1,0,0))):
   op,orig=pivots[name];r=Gf.Matrix4d(1);r.SetRotate(Gf.Rotation(Gf.Vec3d(*axis),deg));op.Set(r*orig)
  for n,vs,fs in meshes(aca):
   tree=BVHTree.FromPolygons([v+Vector((-.49,.9075,-.37)) for v in vs],fs)
   for pn,pb in bv:
    count=len(pb.overlap(tree))
    if count:ahits.append({'angles':angles,'engine':pn,'ACA':n,'triangle_pairs':count})
 ck('ACA 27 poses no surface crossing',not ahits)
 # Contact placement versus current reservation boxes; lens inserts through neutral panel intentionally.
 contact=report[1]['bounds_m'];placements=[]
 for instance in config['components'][1]['instances']:
  panel=next(p for p in inv['panels'] if p['node']==instance['parent'] or any(s['node']==instance['parent'] for s in p['slots']));local=Vector(instance['translation_m']);slot=next((s for s in panel['slots'] if s['node']==instance['parent']),None)
  if slot: local+=Vector(slot['pose']['translation_m'])
  q=panel['pose']['quaternion_xyzw'];mat=Matrix.Translation(Vector(panel['pose']['translation_m']))@Quaternion((q[3],*q[:3])).to_matrix().to_4x4()@Matrix.Translation(local)
  placements.append({'id':instance['id'],'Cabin_matrix_rows':[list(r) for r in mat]})
  for other in panel['slots']:
   if other==slot:continue
   t=other['pose']['translation_m'];size=other['envelope_m'];overlap=all(local[i]+contact[1][i]>t[i]-size[i]/2 and local[i]+contact[0][i]<t[i]+size[i]/2 for i in [0,1]);ck(instance['id']+' outside '+other['id']+' reservation',not overlap)
  if slot:ck(instance['id']+' fits partial reservation',all(abs(instance['translation_m'][i])+max(abs(contact[0][i]),abs(contact[1][i]))<slot['envelope_m'][i]/2 for i in [0,1]))
 (D/'mounting-matrices.json').write_text(json.dumps({'convention':'column-vector matrix rows, asset-local to Cabin; apply once','EngineButtons':[list(r) for r in M],'LunarContact':placements},indent=2)+'\n')
 (D/'validation.json').write_text(json.dumps({'checks':checks,'failed':sum(not c['pass'] for c in checks),'assets':report,'DES_RATE_surface_crossings':hits,'ACA_surface_crossings':ahits,'engine_to_Cabin_matrix_rows':[list(r) for r in M],'method':'Actual USD mesh surface crossings. DES RATE +/-17 and ACA 27 sampled +/-11deg. Not containment, hand clearance, or continuous sweep. Plane insertion behind slot backing is intentional.','VisionPro':'not tested'},indent=2)+'\n')
 print('VALIDATION',len(checks),'failed',sum(not c['pass'] for c in checks));assert all(c['pass'] for c in checks)
main()
