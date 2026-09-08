"""Reuses pinned ControlLibrary mesh families; no simulation or shared writes.
Run Blender -b --factory-startup --python-exit-code 1 --python this file.
"""
import bpy, math, json, sys
from pathlib import Path
from mathutils import Vector, Matrix
from pxr import Usd, UsdGeom, UsdShade, UsdUtils, Sdf, Gf, Vt
D=Path(__file__).resolve().parent
C=Matrix(((1,0,0,0),(0,0,1,0),(0,-1,0,0),(0,0,0,1)))
def B(v): return (v[0],-v[2],v[1])
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
s=bpy.context.scene; bpy.context.preferences.filepaths.save_version=0; s.unit_settings.system='METRIC'; s.unit_settings.scale_length=1
mats={}
def mat(name,c,metal=0):
 m=bpy.data.materials.new(name); m.diffuse_color=(*c,1); m.use_nodes=True
 bs=m.node_tree.nodes.get('Principled BSDF'); bs.inputs['Base Color'].default_value=(*c,1); bs.inputs['Metallic'].default_value=metal; bs.inputs['Roughness'].default_value=.46
 mats[name]=m; return m
mat('Charcoal',(.035,.043,.05)); mat('Panel',(.16,.18,.19)); mat('Aluminum',(.52,.56,.58),.75); mat('Legend',(.86,.88,.79)); mat('Guard',(.26,.28,.27),.5); mat('Flag',(.36,.38,.35)); mat('Tip',(.64,.69,.55))
def empty(name,parent=None,at=(0,0,0)):
 o=bpy.data.objects.new(name,None); s.collection.objects.link(o); o.parent=parent; o.location=B(at); o.empty_display_size=.006; return o
def finish(o,name,parent,at,material):
 o.name=name; o.parent=parent; o.location=B(at); o.data.materials.append(mats[material]); return o
def box(name,parent,at,size,material='Charcoal',bevel=.0005):
 bpy.ops.mesh.primitive_cube_add(); o=bpy.context.object
 o.dimensions=(size[0],size[2],size[1]); bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 if bevel:
  mod=o.modifiers.new('Machined_edges','BEVEL'); mod.width=bevel; mod.segments=2
  bpy.ops.object.modifier_apply(modifier=mod.name)
 return finish(o,name,parent,at,material)
def cylinder(name,parent,at,r,depth,material='Aluminum',vertices=48):
 bpy.ops.mesh.primitive_cylinder_add(vertices=vertices,radius=r,depth=depth,rotation=(math.pi/2,0,0)); o=bpy.context.object
 bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
 return finish(o,name,parent,at,material)
def polygon(name,parent,outline,z0,z1,material):
 # CCW outline in target XY; outward wound closed prism.
 n=len(outline); v=[B((x,y,z)) for z in (z0,z1) for x,y in outline]
 f=[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
 mesh=bpy.data.meshes.new(name); mesh.from_pydata(v,[],f); mesh.update(); o=bpy.data.objects.new(name,mesh); s.collection.objects.link(o); o.parent=parent; o.data.materials.append(mats[material]); return o
def label(name,parent,text,at,size=.004):
 curve=bpy.data.curves.new(name,'FONT'); curve.body=text; curve.align_x='CENTER'; curve.size=size; curve.extrude=.000015
 o=bpy.data.objects.new(name,curve); s.collection.objects.link(o); o.parent=parent; o.location=B(at); o.rotation_euler=(math.pi/2,0,0); curve.materials.append(mats['Legend'])
 bpy.ops.object.select_all(action='DESELECT'); o.select_set(True); bpy.context.view_layer.objects.active=o; bpy.ops.object.convert(target='MESH'); return bpy.context.object

import hashlib
LIB=D.parent/'ControlLibrary'/'ControlLibrary.blend'
assert hashlib.sha256(LIB.read_bytes()).hexdigest()=='4e9e0322b446c6a0532c12523a9ba2e9a4395dc214e27ff47da5cb2ec152b5a2','ControlLibrary changed; review geometry before rebuild'
def family(name,id,offset,neutral):
 with bpy.data.libraries.load(str(LIB),link=False) as (a,b):
  b.objects=[n for n in a.objects if n==name+'_Mount' or n.startswith(name+'__')]
 for o in b.objects:
  if o: s.collection.objects.link(o)
 root=bpy.data.objects[name+'_Mount']; root.name=id+'_Mount'; root.location=(0,0,0); root.rotation_euler=(0,0,0); root.scale=(1,1,1); root['family']=id
 for child in root.children_recursive: child.name=child.name.replace(name+'__',id+'__')
 for child in root.children: child.location+=Vector(B(offset))
 act=bpy.data.objects[id+'__Actuator']; act.rotation_euler.x=math.radians(neutral)
 for o in root.children_recursive:
  if o.type=='MESH':
   for i,m in enumerate(o.data.materials):
    key=m.name.split('.')[0]
    if key in mats: o.data.materials[i]=mats[key]
 return root
mode=family('MaintainedToggle','AttitudeMode',(-.072,-.037,0),-17)
box('AttitudeMode__NeutralBacking',mode,(0,0,-.0015),(.225,.145,.003),'Panel',0)
# Only the documented PGNS mode control is filled. Adjacent controls remain neutral.
label('AttitudeMode__Heading',mode,'MODE CONTROL',(-.043,.013,.00025),.004)
label('AttitudeMode__PGNS',mode,'PGNS',(-.072,-.004,.00025),.004)
label('AttitudeMode__AUTO',mode,'AUTO',(-.072,-.015,.00025),.0035)
label('AttitudeMode__ATTHOLD',mode,'ATT HOLD',(-.037,-.038,.00025),.0035)
label('AttitudeMode__OFF',mode,'OFF',(-.072,-.061,.00025),.0035)
rate=family('MomentaryToggle','DescentRate',(0,0,0),0)
# Side-mounted unplacarded toggle: source ad013 arrow to engine guard side.
# A minimal provisional upright mounting plate retains the future engine package space.
bpy.context.view_layer.update()
side=Matrix.Translation(Vector(B((-.025,.018,.027)))) @ Matrix.Rotation(-math.pi/2,4,'Z')
for child in rate.children: child.matrix_local=side @ child.matrix_local
box('DescentRate__NeutralBacking',rate,(0,0,-.0015),(.125,.11,.003),'Panel',0)
box('DescentRate__ProvisionalUpright',rate,(-.024,.018,.025),(.003,.043,.050),'Charcoal',.0005)
box('DescentRate__ProvisionalFoot',rate,(-.008,.018,.002),(.035,.043,.004),'Charcoal',.0005)
roots=[mode,rate]
def usd_export(root):
 path=D/(root['family']+'.usdc'); stage=Usd.Stage.CreateNew(str(path)); UsdGeom.SetStageUpAxis(stage,'Y'); UsdGeom.SetStageMetersPerUnit(stage,1)
 scope=UsdGeom.Scope.Define(stage,'/Materials')
 for name,m in mats.items():
  material=UsdShade.Material.Define(stage,'/Materials/'+name); shader=UsdShade.Shader.Define(stage,'/Materials/'+name+'/Surface'); shader.CreateIdAttr('UsdPreviewSurface')
  shader.CreateInput('diffuseColor',Sdf.ValueTypeNames.Color3f).Set(Gf.Vec3f(*m.diffuse_color[:3])); shader.CreateInput('roughness',Sdf.ValueTypeNames.Float).Set(.46); shader.CreateInput('metallic',Sdf.ValueTypeNames.Float).Set(m.node_tree.nodes.get('Principled BSDF').inputs['Metallic'].default_value)
  material.CreateSurfaceOutput().ConnectToSource(shader.ConnectableAPI(),'surface')
 def emit(o,parent):
  path=parent+'/'+o.name.replace('.','_'); local=C@o.matrix_local@C.inverted(); xf=UsdGeom.Xform.Define(stage,path) if o.type!='MESH' else UsdGeom.Mesh.Define(stage,path)
  xf.AddTransformOp().Set(Gf.Matrix4d(*[float(local[j][i]) for i in range(4) for j in range(4)]))
  if o.type=='MESH':
   pts=[Gf.Vec3f(*(C.to_3x3()@v.co)) for v in o.data.vertices]; xf.CreatePointsAttr(pts); xf.CreateFaceVertexCountsAttr([len(p.vertices) for p in o.data.polygons]); xf.CreateFaceVertexIndicesAttr([v for p in o.data.polygons for v in p.vertices]); xf.CreateSubdivisionSchemeAttr('none'); xf.CreateOrientationAttr('rightHanded'); xf.CreateDoubleSidedAttr(False)
   xf.CreateNormalsAttr([Gf.Vec3f(*(C.to_3x3()@p.normal)) for p in o.data.polygons]); xf.SetNormalsInterpolation('uniform'); xf.CreateExtentAttr(UsdGeom.PointBased.ComputeExtent(pts))
   UsdShade.MaterialBindingAPI.Apply(xf.GetPrim()).Bind(UsdShade.Material(stage.GetPrimAtPath('/Materials/'+o.data.materials[0].name)))
  for child in sorted(o.children,key=lambda o:o.name): emit(child,path)
  return xf
 rootprim=emit(root,''); stage.SetDefaultPrim(rootprim.GetPrim()); stage.GetRootLayer().Save()
 zipfile=D/(root['family']+'.usdz')
 if zipfile.exists(): zipfile.unlink()
 assert UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(str(path)),str(zipfile))

bpy.context.view_layer.update()
for root in roots: usd_export(root)
# Keep all delivered roots neutral and identity in editable source.
s.render.engine='BLENDER_WORKBENCH'; s.render.resolution_x=1400; s.render.resolution_y=900; s.render.resolution_percentage=100
s.display.shading.light='STUDIO'; s.display.shading.color_type='MATERIAL'; s.display.shading.show_shadows=True; s.display.shading.show_cavity=True; s.display.shading.cavity_type='BOTH'; s.display.shading.background_type='WORLD'; s.world.color=(.025,.025,.025)
s.view_settings.view_transform='Standard'
bpy.ops.object.camera_add(); camera=bpy.context.object; camera.name='ReviewCamera'; camera.data.type='ORTHO'; camera.data.ortho_scale=.26; s.camera=camera
camera.location=B((.015,.02,.6)); camera.rotation_euler=(Vector(B((0,0,0)))-camera.location).to_track_quat('-Z','Y').to_euler(); camera.data.clip_start=.001
bpy.ops.wm.save_as_mainfile(filepath=str(D/'DescentControls.blend'))
for root in roots:
 for other in roots: other.hide_render=(other!=root)
 for other in roots:
  for ob in other.children_recursive: ob.hide_render=(other!=root)
 camera.data.ortho_scale=.26 if root==mode else .18
 camera.location=B((.015,.02,.6)) if root==mode else B((-.25,.18,.35))
 camera.rotation_euler=(Vector(B((0,0,.01)))-camera.location).to_track_quat('-Z','Y').to_euler()
 s.render.filepath=str(D/'review'/(root['family']+'-neutral.png')); bpy.ops.render.render(write_still=True)
for root in roots:
 root.hide_render=False
 for ob in root.children_recursive: ob.hide_render=False
bpy.ops.wm.save_as_mainfile(filepath=str(D/'DescentControls.blend'))
print('DESCENT_CONTROLS_BUILD_PASS')
