import bpy,bmesh,json,math,time,hashlib
from pathlib import Path
from mathutils import Vector
from pxr import Usd,UsdGeom,UsdUtils,Gf,Tf
P=Path(__file__).resolve().parent; out={'checks':[],'assets':{}}
def ck(n,v):
 out['checks'].append({'name':n,'passed':bool(v)})
 if not v: print('FAIL',n)
t=time.perf_counter(); bpy.ops.wm.open_mainfile(filepath=str(P/'HandControllers.blend')); out['reopen_seconds']=time.perf_counter()-t
ck('meters',bpy.context.scene.unit_settings.scale_length==1)
ck('portable materials',not bpy.data.libraries and not any(i.source=='FILE' for i in bpy.data.images))
ck('neutral unanimated',all(not o.animation_data for o in bpy.data.objects))
meta=json.loads((P/'interface.json').read_text()); bpy.context.view_layer.update()
for e in meta['entities']:
 o=bpy.data.objects[e['name']]; ck(e['name']+' parent',o.parent.name==e['parent']); ck(e['name']+' neutral',(o.location-Vector(e['neutral_origin_m'])).length<1e-6 and o.rotation_euler.to_quaternion().angle<1e-6)
 base=o.matrix_basis.copy(); subtree={o,*o.children_recursive}; others={x.name:x.matrix_world.copy() for x in bpy.data.objects if x not in subtree}; children={x.name:x.matrix_world.copy() for x in o.children_recursive}
 for sign in [-1,1]:
  o.matrix_basis=base; axis='XYZ'.index(e['axis'])
  if e['motion']=='rotation': o.rotation_euler[axis]=sign*math.radians(e['demonstration_offset'])
  else: o.location[axis]+=sign*e['demonstration_offset']
  bpy.context.view_layer.update(); ck(e['name']+f' independent {sign}',all(bpy.data.objects[n].matrix_world==m for n,m in others.items())); ck(e['name']+f' moves {sign}',any(bpy.data.objects[n].matrix_world!=m for n,m in children.items()))
 o.matrix_basis=base; bpy.context.view_layer.update()
for name in ['ACA','TTCA']:
 root=bpy.data.objects[name+'_Mount']; ck(name+' identity',all(abs(root.matrix_world[i][j]-(i==j))<1e-7 for i in range(4) for j in range(4)))
 meshes=[o for o in root.children_recursive if o.type=='MESH']; triangles=0; pts=[]
 for o in meshes:
  o.data.calc_loop_triangles(); triangles+=len(o.data.loop_triangles); pts.extend(o.matrix_world@Vector(v) for v in o.bound_box)
  bm=bmesh.new(); bm.from_mesh(o.data); ck(o.name+' closed manifold',all(e.is_manifold for e in bm.edges)); ck(o.name+' positive volume',bm.calc_volume(signed=True)>0); bm.free(); ck(o.name+' nonzero faces',all(f.area>1e-12 for f in o.data.polygons)); ck(o.name+' unit scale',all(abs(v-1)<1e-6 for v in o.scale))
 lo=[min(p[i] for p in pts) for i in range(3)]; hi=[max(p[i] for p in pts) for i in range(3)]
 st=Usd.Stage.Open(str(P/(name+'.usdz'))); ck(name+' USD opens',bool(st)); ck(name+' Y up',UsdGeom.GetStageUpAxis(st)=='Y'); ck(name+' meters',UsdGeom.GetStageMetersPerUnit(st)==1); ck(name+' USD root identity',UsdGeom.Xformable(st.GetDefaultPrim()).GetLocalTransformation()==Gf.Matrix4d(1)); ck(name+' no time samples',not any(a.GetNumTimeSamples() for p in st.Traverse() for a in p.GetAttributes()))
 # Compare transformed mesh vertices, verifying exported basis rather than metadata alone.
 cache=UsdGeom.XformCache(); usdmeshes=[p for p in st.Traverse() if p.IsA(UsdGeom.Mesh)]
 ck(name+' mesh count',len(usdmeshes)==len(meshes))
 for p in usdmeshes:
  o=next(o for o in meshes if Tf.MakeValidIdentifier(o.name)==p.GetParent().GetName() or Tf.MakeValidIdentifier(o.name)==p.GetName()); points=UsdGeom.Mesh(p).GetPointsAttr().Get(); xf=cache.GetLocalToWorldTransform(p)
  ck(p.GetName()+' basis vertices',len(points)==len(o.data.vertices) and all((Vector(xf.Transform(Gf.Vec3d(*v)))-(o.matrix_world@bv.co)).length<1e-5 for v,bv in zip(points,o.data.vertices)))
 for e in meta['entities']:
  if e['name'].startswith(name):
   p=next((p for p in st.Traverse() if p.GetName()==e['name']),None); ck(e['name']+' USD hierarchy',p is not None and p.GetParent().GetName()==e['parent'])
 checker=UsdUtils.ComplianceChecker(arkit=False); checker.CheckCompliance(str(P/(name+'.usdz'))); ck(name+' USD compliance',not checker.GetErrors() and not checker.GetFailedChecks())
 out['assets'][name]={'meshes':len(meshes),'triangles':triangles,'bounds_min_m':lo,'bounds_max_m':hi,'dimensions_m':[hi[i]-lo[i] for i in range(3)],'USD_errors':checker.GetErrors(),'USD_failed_checks':checker.GetFailedChecks(),'USD_warnings':checker.GetWarnings(),'usdz_bytes':(P/(name+'.usdz')).stat().st_size}
for name in ['ACA','TTCA']:
 bpy.ops.wm.read_factory_settings(use_empty=True); bpy.ops.wm.usd_import(filepath=str(P/(name+'.usdz')))
 ck(name+' reimport root',bpy.data.objects.get(name+'_Mount') is not None)
 ck(name+' reimport meshes',sum(o.type=='MESH' for o in bpy.data.objects)==out['assets'][name]['meshes'])
 for e in meta['entities']:
  if e['name'].startswith(name):
   o=bpy.data.objects.get(e['name']); ck(e['name']+' reimport hierarchy',o is not None and o.parent.name==e['parent'])
out['sha256']={n:hashlib.sha256((P/n).read_bytes()).hexdigest() for n in ['HandControllers.blend','ACA.usdz','TTCA.usdz']}; out['passed']=all(c['passed'] for c in out['checks']); out['check_count']=len(out['checks']); (P/'validation.json').write_text(json.dumps(out,indent=2)+'\n'); print('VALIDATION',out['passed'],out['check_count']); assert out['passed']
