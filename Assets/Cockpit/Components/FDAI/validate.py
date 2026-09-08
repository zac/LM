"""Run in a fresh host Blender process; writes measured facts, exits nonzero on failure."""
import bpy,json,math,time,hashlib,zipfile
from pathlib import Path
from mathutils import Vector
from pxr import Usd,UsdGeom,UsdShade,UsdUtils,Gf
P=Path(__file__).resolve().parent
out={'checks':[],'measurements':{},'limitations':['No RealityKit renderer, RCP or Vision Pro hardware test','No controlled LM-5 dimensional drawing','No flight-state bindings tested']}
def check(name,value):
 out['checks'].append({'name':name,'passed':bool(value)})
 if not value: print('FAIL',name)
t=time.perf_counter(); bpy.ops.wm.open_mainfile(filepath=str(P/'FDAI.blend')); out['measurements']['reopen_seconds']=time.perf_counter()-t
root=bpy.data.objects['FDAI_Mount']; fixed=bpy.data.objects['FDAI_Fixed']
check('root identity',all(abs(root.matrix_world[i][j]-(1 if i==j else 0))<1e-7 for i in range(4) for j in range(4)))
check('meters',bpy.context.scene.unit_settings.scale_length==1)
check('no linked libraries',len(bpy.data.libraries)==0)
check('packed portable texture',all(i.packed_file or Path(bpy.path.abspath(i.filepath)).exists() for i in bpy.data.images if i.source=='FILE'))
check('no animation or drivers',all(not o.animation_data for o in bpy.data.objects))
meshes=[o for o in bpy.data.objects if o.type=='MESH']; tri=0; allpoints=[]
for o in meshes:
 o.data.calc_loop_triangles();tri+=len(o.data.loop_triangles)
 check(o.name+' scale',all(abs(v-1)<1e-6 for v in o.scale))
 check(o.name+' material',bool(o.data.materials))
 check(o.name+' nonzero faces',all(poly.area>1e-13 for poly in o.data.polygons))
 allpoints.extend(o.matrix_world@Vector(v) for v in o.bound_box)
lo=[min(p[i] for p in allpoints) for i in range(3)];hi=[max(p[i] for p in allpoints) for i in range(3)]
out['measurements'].update({'triangles':tri,'mesh_objects':len(meshes),'used_materials':len({m.name for o in meshes for m in o.data.materials}),'bounds_min_m':lo,'bounds_max_m':hi,'dimensions_m':[hi[i]-lo[i] for i in range(3)]})
check('provisional envelope within 150x150x280 mm',all(hi[i]-lo[i]<[.15,.15,.28][i] for i in range(3)))
ball=bpy.data.objects['FDAI_Ball']; check('ball radius 50mm',all(abs(v.co.length-.05)<1e-6 for v in ball.data.vertices))
check('ball UV complete',len(ball.data.uv_layers)==1)
contract=json.loads((P/'interface.json').read_text())
for entry in contract['entities']:
 o=bpy.data.objects[entry['name']]
 check('contract origin '+o.name,(o.location-Vector(entry['neutral_origin_m'])).length<1e-6)
 check('contract neutral rotation '+o.name,o.rotation_euler.to_quaternion().angle<1e-6)
# Each motion is tested individually; every other object must retain its world matrix.
mov=['FDAI_Ball_Pivot','FDAI_RollBug_Pivot']+[f'FDAI_{kind}_{a}_Pivot' for kind in ['Rate','Error'] for a in ['Roll','Pitch','Yaw']]
for name in mov:
 o=bpy.data.objects[name]; check(name+' direct parent',o.parent==root); base=o.matrix_basis.copy()
 subtree={o,*o.children_recursive}; others={x.name:x.matrix_world.copy() for x in bpy.data.objects if x not in subtree}; before={x.name:x.matrix_world.copy() for x in o.children_recursive}
 for sign in [-1,1]:
  o.matrix_basis=base
  o.rotation_euler.z=math.radians((27 if 'Rate' in name else 25)*sign)
  bpy.context.view_layer.update()
  check(name+f' independent {sign}',all(bpy.data.objects[n].matrix_world==m for n,m in others.items()))
  check(name+f' geometry moves {sign}',any(bpy.data.objects[n].matrix_world!=m for n,m in before.items()))
 o.matrix_basis=base; bpy.context.view_layer.update()
# Representative local geometric rotations, not GASTA or a simulation test.
p=bpy.data.objects['FDAI_Ball_Pivot'];base=p.matrix_basis.copy()
for axis in range(3):
 for degrees in [-90,-30,30,90,180]:
  p.matrix_basis=base;p.rotation_euler[axis]=math.radians(degrees);bpy.context.view_layer.update()
  check(f'ball pivot invariant axis {axis} deg {degrees}',(p.matrix_world.translation-Vector((0,0,-.008))).length<1e-6)
  check(f'ball rigid radius axis {axis} deg {degrees}',all(abs((ball.matrix_world@v.co-p.matrix_world.translation).length-.05)<1e-6 for v in list(ball.data.vertices)[::97]))
p.matrix_basis=base
stage=Usd.Stage.Open(str(P/'FDAI.usdz'))
check('USD opens',bool(stage));check('USD Y up',UsdGeom.GetStageUpAxis(stage)=='Y');check('USD meters',UsdGeom.GetStageMetersPerUnit(stage)==1)
check('USD root identity',UsdGeom.Xformable(stage.GetDefaultPrim()).GetLocalTransformation()==Gf.Matrix4d(1))
for name in mov:check('USD '+name, bool(stage.GetPrimAtPath('/FDAI_Mount/'+name)))
check('USD no animation',not any(a.GetNumTimeSamples()>0 for p in stage.Traverse() for a in p.GetAttributes()))
check('USD no camera/light',not any(p.GetTypeName() in ['Camera','DiskLight','DistantLight','RectLight','DomeLight'] for p in stage.Traverse()))
for prim in stage.Traverse():
 if prim.IsA(UsdGeom.Mesh):check('USD bound '+str(prim.GetPath()),bool(UsdShade.MaterialBindingAPI(prim).ComputeBoundMaterial()[0]))
checker=UsdUtils.ComplianceChecker(arkit=False);checker.CheckCompliance(str(P/'FDAI.usdz'));out['usd_compliance']={'errors':checker.GetErrors(),'failed_checks':checker.GetFailedChecks(),'warnings':checker.GetWarnings()};check('USD compliance',not checker.GetErrors() and not checker.GetFailedChecks())
with zipfile.ZipFile(P/'FDAI.usdz') as z:
 out['usd_members']=z.namelist();check('USD packed texture',any(n.endswith('.png') for n in z.namelist()))
# Fresh scene import exercises actual mesh/texture importer, not just ZIP syntax.
bpy.ops.wm.read_factory_settings(use_empty=True);t=time.perf_counter();bpy.ops.wm.usd_import(filepath=str(P/'FDAI.usdz'));out['measurements']['usdz_reimport_seconds']=time.perf_counter()-t
for name in mov:
 o=bpy.data.objects.get(name);check('reimport '+name,o is not None and o.parent is not None and o.parent.name=='FDAI_Mount')
gm=bpy.data.materials['FDAI_Glass'].node_tree.nodes
pbs=next(n for n in gm if n.type=='BSDF_PRINCIPLED')
out['measurements']['reimport_glass']={'alpha':pbs.inputs['Alpha'].default_value,'transmission':pbs.inputs['Transmission Weight'].default_value}
check('reimport glass opacity represented',abs(pbs.inputs['Alpha'].default_value-.055)<1e-5 or abs(pbs.inputs['Transmission Weight'].default_value-.945)<1e-5)
check('reimport texture',any(i.size[0]==4096 and i.has_data for i in bpy.data.images))
out['hashes']={n:hashlib.sha256((P/n).read_bytes()).hexdigest() for n in ['FDAI.blend','FDAI.usdc','FDAI.usdz','textures/fdai_8ball_albedo.png']}
out['passed']=all(c['passed'] for c in out['checks']);out['check_count']=len(out['checks']);(P/'validation.json').write_text(json.dumps(out,indent=2)+'\n');print('VALIDATION',out['passed'],out['check_count'],out['measurements']);assert out['passed']
