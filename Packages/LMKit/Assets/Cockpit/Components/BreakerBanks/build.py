"""Reproducible static cockpit breaker-bank overlay. Blender scene and USD Y-up.
blender -b --factory-startup --python-exit-code 1 --python build.py
All package/API/application installation is coordinator-owned.
"""
import bpy, json, math, hashlib
from pathlib import Path
from mathutils import Matrix,Vector,Quaternion
from pxr import Usd,UsdGeom,UsdShade,UsdUtils,Sdf,Gf
D=Path(__file__).resolve().parent
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
bpy.context.preferences.filepaths.save_version=0
sc=bpy.context.scene;sc.unit_settings.system='METRIC';sc.unit_settings.scale_length=1
mats={}
def material(n,c,metal=0):
 m=bpy.data.materials.new(n);m.diffuse_color=(*c,1);m.use_nodes=True;m.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=(*c,1);m.node_tree.nodes['Principled BSDF'].inputs['Metallic'].default_value=metal;m.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value=.65;mats[n]=m;return m
material('WarmPanel',(.58,.585,.54));material('DarkLegend',(.025,.031,.028));material('EdgeMetal',(.22,.235,.23),.5);material('Charcoal',(.035,.043,.05));material('Aluminum',(.52,.56,.58),.75)
def node(n,p=None,pos=(0,0,0),rot=None):
 o=bpy.data.objects.new(n,None);sc.collection.objects.link(o);o.parent=p;o.location=pos
 if rot is not None:o.rotation_mode='QUATERNION';o.rotation_quaternion=rot
 return o
def box(n,p,pos,dim,mat):
 bpy.ops.mesh.primitive_cube_add();o=bpy.context.object;o.name=n;o.dimensions=dim;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);o.parent=p;o.location=pos;o.data.materials.append(mats[mat]);return o
def text(n,p,body,pos,size):
 c=bpy.data.curves.new(n,'FONT');c.body=body;c.size=size;c.align_x='CENTER';c.align_y='CENTER';c.space_line=.95;c.resolution_u=2;c.extrude=0;c.materials.append(mats['DarkLegend']);o=bpy.data.objects.new(n,c);sc.collection.objects.link(o);o.parent=p;o.location=pos
 bpy.ops.object.select_all(action='DESELECT');o.select_set(True);bpy.context.view_layer.objects.active=o;bpy.ops.object.convert(target='MESH');return bpy.context.object
# Read original USD mesh data. Do not reconstruct/rewrite control-library geometry.
src=Usd.Stage.Open(str(D/'evidence/CircuitBreaker.usdz'));cache=UsdGeom.XformCache();templates=[]
for prim in src.Traverse():
 if not prim.IsA(UsdGeom.Mesh):continue
 mesh=UsdGeom.Mesh(prim);pts=mesh.GetPointsAttr().Get();counts=mesh.GetFaceVertexCountsAttr().Get();idx=mesh.GetFaceVertexIndicesAttr().Get();faces=[];at=0
 for k in counts:faces.append(tuple(idx[at:at+k]));at+=k
 data=bpy.data.meshes.new(prim.GetName());data.from_pydata([tuple(v) for v in pts],[],faces);data.update()
 bound=UsdShade.MaterialBindingAPI(prim).ComputeBoundMaterial()[0].GetPrim().GetName();data.materials.append(mats[bound])
 mat=cache.GetLocalToWorldTransform(prim);trans=Matrix([[mat[j][i] for j in range(4)] for i in range(4)])
 templates.append((prim.GetName(),data,trans))
root=node('BreakerBanks');root['qualification']='Optional static visual overlay; no electrical state, input, lights or collisions.'
inv=json.loads((D/'evidence/inventory.json').read_text());labels=json.loads((D/'labels.json').read_text())['panels'];groups={'Panel11':['AC BUS B / AC BUS A','RCS SYS A / FLIGHT DISPLAYS / AC BUS A','PROPUL / HEATERS / INST / STAB-CONT / ED / LTG','HEATERS / ECS / COMM / PGNS','EPS'],'Panel16':['FLT DISP / RCS SYS B / PROPUL','LTG / ED / STAB-CONT / INST / ECS','COMM / ECS','HEATERS / CAMR / EPS']}
contract={'schema':'lmkit.breaker-banks.interface.v1','root':'/BreakerBanks','units':'meters','axes':'+X right +Y up -Z forward','root_pose':'identity Cabin-relative; do not apply panel transforms again','base_revision':'ee3a19f21e31d77645e7b6451db800d2b3d60f5e','panel_inventory_sha256':hashlib.sha256((D/'evidence/inventory.json').read_bytes()).hexdigest(),'runtime':'Static appearance only. No circuits, breaker state or collision/input targets.','slots':[],'qualification':'Provisional envelope, knob spacing and terrace/cant.15 degree relative cant is source-inspired, not surveyed line-of-sight reconstruction.'}
count=0
for panel in inv['panels']:
 if panel['id'] not in labels:continue
 name=panel['id'];q=panel['pose']['quaternion_xyzw'];bank=node(name,root,panel['pose']['translation_m'],Quaternion((q[3],*q[:3])))
 for ri,slot in enumerate(panel['slots']):
  sid=slot['id'];mount=node(sid,bank,slot['pose']['translation_m']);offset=.035+ri*.008;cant=math.radians(-15);face=node('Terrace',mount,(0,0,offset),Quaternion((1,0,0),cant));width=.735;height=.052
  box('Face',face,(0,0,-.0015),(width,height,.003),'WarmPanel')
  # Individual depths make separate stepped terraces; narrow side returns cover voids.
  for x in [-width/2+.001,width/2-.001]:box('Return',mount,(x,0,offset/2),(.002,.050,offset),'EdgeMetal')
  box('LowerLip',face,(0,-height/2,-.004),(width,.003,.008),'EdgeMetal')
  # Label and small divider lines are ordinary opaque mesh; no luminous/texture state.
  text('GroupLegend',face,groups[name][ri],(0,.022,.00025),.0032)
  row=labels[name][ri];n=len(row)
  # Last commander row retains the source's mostly empty right half.
  used=.39 if name=='Panel11' and ri==4 else .695
  left=-.3475
  for ci,legend in enumerate(row):
   x=left+ci*used/(n-1);breaker=node(f'CB_{ci+1:02}',face,(x,-.011,0));breaker['label']=legend.replace('\n',' ');breaker['neutral_visual_only']=True
   for source_name,data,tr in templates:
    o=bpy.data.objects.new(source_name,data);sc.collection.objects.link(o);o.parent=breaker;o.matrix_local=tr
   text(f'Legend_{ci+1:02}',face,legend,(x,.009,.00025),.00325)
   count+=1
  # Fasteners stay inside strip limits, slightly larger than line legend strokes.
  for x in [-.36,.36]:
   bpy.ops.mesh.primitive_cylinder_add(vertices=12,radius=.002,depth=.001);o=bpy.context.object;o.name='Fastener';o.parent=face;o.location=(x,.018,.0005);o.data.materials.append(mats['EdgeMetal'])
  contract['slots'].append({'id':sid,'overlay_path':f'/BreakerBanks/{name}/{sid}','panel_pose':panel['pose'],'slot_pose':slot['pose'],'default_placeholder_node':slot['default_placeholder_node'],'replacement_allowed':slot['replacement_allowed'],'suppression':'Coordinator may hide only this exact placeholder after successful whole-overlay load and interface validation; failure retains blank. Do not hide frame, label or parent.','terrace_offset_m':offset,'relative_cant_degrees':-15,'breaker_count':n,'dimension_status':'provisional; slot UV footprint retained, allowed forward depth explicitly expanded for hardware.'})
bpy.context.view_layer.update()
# Convert repeated static fixed part meshes into one material-preserving mesh per row;
# individual breaker parents remain addressable, knobs remain separate for future authoring.
# Kept source meshes shared in Blender for inexpensive reuse.
contract['breaker_count']=count
for face in [o for o in root.children_recursive if o.name.startswith('Terrace')]:
 candidates=[o for o in face.children_recursive if o.type=='MESH' and not any(t in o.name for t in ['BlackKnob','OpenBand'])]
 for material_name in mats:
  selected=[o for o in candidates if o.data.materials[0].name==material_name]
  if not selected:continue
  verts=[];polys=[]
  for o in selected:
   tr=face.matrix_world.inverted()@o.matrix_world;base=len(verts);verts.extend([tr@v.co for v in o.data.vertices]);polys.extend([tuple(base+i for i in p.vertices) for p in o.data.polygons])
  data=bpy.data.meshes.new('Static_'+material_name);data.from_pydata(verts,[],polys);data.update();data.materials.append(mats[material_name]);joined=bpy.data.objects.new('Static_'+material_name,data);sc.collection.objects.link(joined);joined.parent=face
  candidates=[o for o in candidates if o not in selected]
  for o in selected:bpy.data.objects.remove(o,do_unlink=True)
bpy.context.view_layer.update()
objects=[root]+list(root.children_recursive);meshes=[o for o in objects if o.type=='MESH']
for o in objects:o['scope']='BreakerBanks; visual only'
vs=[o.matrix_world@Vector(v) for o in meshes for v in o.bound_box];contract['bounds_m']={'min':[min(v[i] for v in vs) for i in range(3)],'max':[max(v[i] for v in vs) for i in range(3)]}
for o in meshes:o.data.calc_loop_triangles()
contract['budget']={'mesh_count':len(meshes),'triangles':sum(len(o.data.loop_triangles) for o in meshes),'materials':len(mats),'textures':0}
(D/'interface.json').write_text(json.dumps(contract,indent=2)+'\n')
# Export authored geometry with identity axes, no lights/cameras/physics.
stage=Usd.Stage.CreateNew(str(D/'BreakerBanks.usda'));UsdGeom.SetStageUpAxis(stage,'Y');UsdGeom.SetStageMetersPerUnit(stage,1)
for n,m in mats.items():
 u=UsdShade.Material.Define(stage,'/Materials/'+n);s=UsdShade.Shader.Define(stage,'/Materials/'+n+'/Surface');s.CreateIdAttr('UsdPreviewSurface');s.CreateInput('diffuseColor',Sdf.ValueTypeNames.Color3f).Set(Gf.Vec3f(*m.diffuse_color[:3]));s.CreateInput('roughness',Sdf.ValueTypeNames.Float).Set(.65);s.CreateInput('metallic',Sdf.ValueTypeNames.Float).Set(m.node_tree.nodes['Principled BSDF'].inputs['Metallic'].default_value);u.CreateSurfaceOutput().ConnectToSource(s.ConnectableAPI(),'surface')
def emit(o,parent):
 path=parent+'/'+o.name.replace('.','_');xf=UsdGeom.Mesh.Define(stage,path) if o.type=='MESH' else UsdGeom.Xform.Define(stage,path);m=o.matrix_local;xf.AddTransformOp().Set(Gf.Matrix4d(*[m[j][i] for i in range(4) for j in range(4)]))
 if o.type=='MESH':
  pts=[Gf.Vec3f(*v.co) for v in o.data.vertices];xf.CreatePointsAttr(pts);xf.CreateFaceVertexCountsAttr([len(p.vertices) for p in o.data.polygons]);xf.CreateFaceVertexIndicesAttr([i for p in o.data.polygons for i in p.vertices]);xf.CreateSubdivisionSchemeAttr('none');xf.CreateExtentAttr(UsdGeom.PointBased.ComputeExtent(pts));UsdShade.MaterialBindingAPI.Apply(xf.GetPrim()).Bind(UsdShade.Material(stage.GetPrimAtPath('/Materials/'+o.data.materials[0].name)))
 for c in o.children:emit(c,path)
 return xf
r=emit(root,'');stage.SetDefaultPrim(r.GetPrim());stage.GetRootLayer().Save();stage.GetRootLayer().Export(str(D/'BreakerBanks.usdc'));target=D/'BreakerBanks.usdz'
if target.exists():target.unlink()
assert UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(str(D/'BreakerBanks.usdc')),str(target))
# Neutral editable scene saved before review-only camera changes.
sc.render.engine='BLENDER_WORKBENCH';sc.render.resolution_x=1500;sc.render.resolution_y=900;sc.render.resolution_percentage=100;sc.display.shading.light='STUDIO';sc.display.shading.color_type='MATERIAL';sc.display.shading.show_shadows=True;sc.display.shading.show_cavity=True;sc.display.shading.cavity_type='BOTH';sc.world.color=(.06,.06,.06);sc.render.image_settings.file_format='PNG';sc.render.filepath='//review/commander.png'
camd=bpy.data.cameras.new('InspectionCamera');cam=bpy.data.objects.new('InspectionCamera',camd);sc.collection.objects.link(cam);sc.camera=cam;camd.type='ORTHO';camd.ortho_scale=.90
bpy.ops.wm.save_as_mainfile(filepath=str(D/'BreakerBanks.blend'))
for panel,pos,look in [('commander',(-.15,1.80,-.02),(-.90,1.5,-.10)),('pilot',(.13,1.83,-.02),(.90,1.52,-.10)),('profile',(-.3,1.73,.52),(-.89,1.5,-.10))]:
 cam.location=pos;forward=(Vector(look)-cam.location).normalized();right=forward.cross(Vector((0,1,0))).normalized();up=right.cross(forward);cam.rotation_euler=Matrix((right,up,-forward)).transposed().to_euler();sc.render.filepath=str(D/'review'/f'{panel}.png');bpy.ops.render.render(write_still=True)
print('PASS build',count,contract['budget'],contract['bounds_m'])
