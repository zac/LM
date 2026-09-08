"""blender -b --factory-startup --python validate.py"""
import bpy,bmesh,json,math,hashlib,zipfile
from pathlib import Path
from mathutils import Matrix, Vector
from pxr import Usd,UsdGeom,UsdUtils,Gf
D=Path(__file__).resolve().parent
C=Matrix(((1,0,0,0),(0,0,1,0),(0,-1,0,0),(0,0,0,1)))
report={'checks':[],'assets':[]}
def check(ok,msg):
 assert ok,msg
 report['checks'].append(msg)
bpy.ops.wm.open_mainfile(filepath=str(D/'ControlLibrary.blend'))
check(bpy.context.scene.unit_settings.scale_length==1,'Blend uses meters')
check(not [i for i in bpy.data.images if i.source=='FILE' and not i.packed_file] and not bpy.data.libraries,'No external images or linked libraries')
check(not [f for f in bpy.data.fonts if f.filepath and f.filepath!='<builtin>'],'No external fonts')
metadata=json.loads((D/'components.json').read_text())
for entry in metadata['components']:
 id=entry['id']; root=bpy.data.objects[entry['mount']]; root.location=(0,0,0); bpy.context.view_layer.update()
 stage=Usd.Stage.Open(str(D/(id+'.usdz'))); check(bool(stage),id+' USDZ reopen')
 check(UsdGeom.GetStageUpAxis(stage)=='Y' and UsdGeom.GetStageMetersPerUnit(stage)==1,id+' units and up axis')
 check(stage.GetDefaultPrim().GetName()==root.name,id+' default mounting root')
 check(UsdGeom.Xformable(stage.GetDefaultPrim()).GetLocalTransformation()==Gf.Matrix4d(1),id+' mount identity')
 for o in root.children_recursive:
  prim=next((p for p in stage.Traverse() if p.GetName()==o.name),None); check(prim is not None,id+' addressing '+o.name)
  local=C@o.matrix_local@C.inverted(); usd=UsdGeom.Xformable(prim).GetLocalTransformation()
  check(max(abs(usd[i][j]-local[j][i]) for i in range(4) for j in range(4))<1e-7,id+' converted pivot '+o.name)
  if o.type=='MESH':
   mesh=bmesh.new(); mesh.from_mesh(o.data)
   check(all(e.is_manifold for e in mesh.edges),o.name+' closed manifold')
   check(mesh.calc_volume(signed=True)>0,o.name+' outward winding')
   mesh.free()
   um=UsdGeom.Mesh(prim); pts=um.GetPointsAttr().Get()
   check(len(pts)==len(o.data.vertices),o.name+' point count')
   check(max((Vector(p)-(C.to_3x3()@v.co)).length for p,v in zip(pts,o.data.vertices))<1e-7,o.name+' physical basis conversion')
   check(all(abs(Vector(n).length-1)<1e-4 for n in um.GetNormalsAttr().Get()),o.name+' normalized normals')
 for n in entry['moving']: check(bpy.data.objects[n].parent==root,id+' independently addressable '+n)
 # Ensure real geometry projects toward the viewer (+Z) and housing behind panel (-Z).
 bbox=UsdGeom.BBoxCache(Usd.TimeCode.Default(),['default']).ComputeWorldBound(stage.GetDefaultPrim()).ComputeAlignedRange()
 check(bbox.GetMin()[2]<0 and bbox.GetMax()[2]>0,id+' panel-facing geometry orientation')
 deps=UsdUtils.ComputeAllDependencies(str(D/(id+'.usdz')))
 check(len(deps[2])==0,id+' no unresolved USD dependencies')
 report['assets'].append({'id':id,'bounds_usd_m':[list(bbox.GetMin()),list(bbox.GetMax())],'sha256':hashlib.sha256((D/(id+'.usdz')).read_bytes()).hexdigest(),'mesh_count':sum(p.IsA(UsdGeom.Mesh) for p in stage.Traverse())})
# Verify nominal motion moves only the intended descendants and restores exactly.
for entry in metadata['components']:
 id=entry['id']; root=bpy.data.objects[entry['mount']]
 for name in entry['moving']:
  o=bpy.data.objects[name]; before=o.matrix_basis.copy(); housing=bpy.data.objects[id+'__Housing'].matrix_world.copy()
  if name.endswith('__Actuator'):
   if id=='CircuitBreaker': o.location.y-=.005
   elif id=='RotarySelector': o.rotation_euler.y+=math.radians(30)
   else: o.rotation_euler.x+=math.radians(17)
  elif name.endswith('__Guard'): o.rotation_euler.x=math.radians(-100)
  else: o.location.y-=.001
  bpy.context.view_layer.update(); check(o.matrix_basis!=before,name+' movable'); check(bpy.data.objects[id+'__Housing'].matrix_world==housing,name+' housing stationary'); o.matrix_basis=before
# Native Blender USD importer round trip in fresh scenes: full hierarchy and bounds count.
for asset in report['assets']:
 id=asset['id']; bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
 bpy.ops.wm.usd_import(filepath=str(D/(id+'.usdz')))
 check(any(o.name==id+'_Mount' for o in bpy.context.scene.objects),id+' Blender USDZ reimport mount')
 check(sum(o.type=='MESH' for o in bpy.context.scene.objects)==asset['mesh_count'],id+' Blender USDZ reimport mesh count')
report['result']='PASS'; report['check_count']=len(report['checks']); report['limits']=['No Vision Pro interaction or historical fit certification','Guard envelope and interlock proposal require coordinator review','No package resources refreshed; coordinator owns Sources/Tests/Tools']
(D/'validation.json').write_text(json.dumps(report,indent=2)+'\n'); print('VALIDATION_PASS',report['check_count'])
