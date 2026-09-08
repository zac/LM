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
  st=Usd.Stage.Open(str(D/item['asset']));root=st.GetDefaultPrim();ck(item['id']+' root',root.GetName()==item['mount']);ck('units',UsdGeom.GetStageMetersPerUnit(st)==1);ck('up',UsdGeom.GetStageUpAxis(st)=='Y');ck('identity root',UsdGeom.Xformable(root).GetLocalTransformation()==Gf.Matrix4d(1))
  p=st.GetPrimAtPath('/'+item['mount']+'/'+item['actuator']);ck('direct actuator',bool(p));xf=UsdGeom.Xformable(p);base=xf.GetLocalTransformation();pos=base.ExtractTranslation();ck('pivot expected',all(abs(pos[i]-item['actuator_neutral_position_m'][i])<1e-6 for i in range(3)))
  q=base.ExtractRotationQuat();ck('independent backing',bool(st.GetPrimAtPath('/'+item['mount']+'/'+item['neutral_backing'])))
  ck('no external dependencies',all(str(a.resolvedPath).endswith(('.usdz','.usdc')) for a in UsdUtils.ComputeAllDependencies(str(D/item['asset']))[1]))
  checker=UsdUtils.ComplianceChecker(arkit=True,skipARKitRootLayerCheck=False);checker.CheckCompliance(str(D/item['asset']));ck('ARKit compliance',not checker.GetErrors() and not checker.GetFailedChecks())
  geo=meshes(st);points=[v for _,vs,_ in geo for v in vs];bb=[[min(v[i] for v in points) for i in range(3)],[max(v[i] for v in points) for i in range(3)]]
  ck('within slot width',bb[0][0]>=-item['backing_m'][0]/2-.00001 and bb[1][0]<=item['backing_m'][0]/2+.00001)
  ck('within slot height',bb[0][1]>=-item['backing_m'][1]/2-.00001 and bb[1][1]<=item['backing_m'][1]/2+.00001)
  fixed={str(m.GetPath()):UsdGeom.Xformable(m).GetLocalTransformation() for m in st.Traverse() if m.GetParent()==root and m!=p}
  xf.ClearXformOpOrder();op=xf.AddTransformOp()
  for state in item['states']:
   rot=Gf.Matrix4d(1);rot.SetRotate(Gf.Rotation(Gf.Vec3d(1,0,0),state['angle_degrees']))
   orient=Gf.Matrix4d(1)
   if item['id']=='DescentRate': orient.SetRotate(Gf.Rotation(Gf.Vec3d(0,1,0),-90))
   m=rot*orient;m.SetTranslateOnly(pos);op.Set(m)
   ck('fixed unaffected '+state.get('id',state.get('placard')),all(UsdGeom.Xformable(st.GetPrimAtPath(path)).GetLocalTransformation()==mat for path,mat in fixed.items()))
   tip=UsdGeom.XformCache().GetLocalToWorldTransform(p).Transform(Gf.Vec3d(0,0,.023))
   ck('upper/lower direction '+str(state['angle_degrees']),abs(state['angle_degrees'])<1 or ((tip[1]-pos[1])>0)==(state['angle_degrees']<0))
  op.Set(base)
  report.append({'id':item['id'],'bounds_m':bb,'actuator_translation_m':list(pos),'actuator_quaternion_xyzw':[float(q.GetImaginary()[i]) for i in range(3)]+[float(q.GetReal())],'meshes':len(geo),'triangles':sum(sum(len(f)-2 for f in fs) for _,_,fs in geo)})
 # Actual side control versus pinned ACA at 27 sampled attitudes; panel-local mounting applied once.
 item=config['components'][1];p5=next(p for p in inv['panels'] if p['id']=='Panel5');slot=next(s for s in p5['slots'] if s['id']==item['slot']);p=p5['pose'];q=p['quaternion_xyzw'];M=Matrix.Translation(Vector(p['translation_m']))@Quaternion((q[3],*q[:3])).to_matrix().to_4x4()@Matrix.Translation(Vector(slot['pose']['translation_m']))
 st=Usd.Stage.Open(str(D/item['asset']));prod=[(n,[M@v for v in vs],fs) for n,vs,fs in meshes(st)];bv=[(n,BVHTree.FromPolygons(v,f)) for n,v,f in prod]
 acaPath=D.parent/'HandControllers/ACA.usdz';aca=Usd.Stage.Open(str(acaPath));pivots={}
 for p in aca.Traverse():
  if p.GetName() in ('ACA_Roll','ACA_Yaw','ACA_Pitch'):
   xf=UsdGeom.Xformable(p);orig=xf.GetLocalTransformation();xf.ClearXformOpOrder();pivots[p.GetName()]=(xf.AddTransformOp(),orig)
 ck('ACA three pivots',len(pivots)==3);hits=[]
 for angles in itertools.product([-11,0,11],repeat=3):
  for name,deg,axis in zip(('ACA_Roll','ACA_Yaw','ACA_Pitch'),angles,((0,0,-1),(0,1,0),(1,0,0))):
   op,orig=pivots[name];r=Gf.Matrix4d(1);r.SetRotate(Gf.Rotation(Gf.Vec3d(*axis),deg));op.Set(r*orig)
  for n,vs,fs in meshes(aca):
   tree=BVHTree.FromPolygons([v+Vector((-.49,.9075,-.37)) for v in vs],fs)
   for pn,pb in bv:
    count=len(pb.overlap(tree))
    if count:hits.append({'angles':angles,'control':pn,'ACA':n,'triangle_pairs':count})
 ck('sampled ACA no crossing',not hits)
 (D/'validation.json').write_text(json.dumps({'checks':checks,'failed':sum(not c['pass'] for c in checks),'assets':report,'ACA_surface_crossings':hits,'method':'actual USD meshes, 27 ACA poses +/-11deg. Neutral DES RATE. Not containment/hand/continuous clearance.','ACA_sha256':hashlib.sha256(acaPath.read_bytes()).hexdigest(),'native':'separate report','VisionPro':'not tested'},indent=2)+'\n')
 print('VALIDATION',len(checks),'failed',sum(not c['pass'] for c in checks));assert all(c['pass'] for c in checks)
try:main()
except Exception:
 traceback.print_exc();sys.stdout.flush();sys.stderr.flush();raise
