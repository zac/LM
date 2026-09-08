"""blender -b --factory-startup --python build.py
Authoring: X right, Z overhead, +Y forward. USD: (x,z,-y), meters.
All dimensions below are provisional except explicitly sourced nominal travel.
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
P=json.loads((D/'parameters.json').read_text()); roots=[]; entries=[]
def base(f):
 r=empty(f['id']+'_Mount'); r['family']=f['id']; r['dimension_confidence']='provisional'; r['simulation_binding']='none'; roots.append(r)
 return r
for f in P['families']:
 id=f['id']; r=base(f); moving=[]
 if id in ('MaintainedToggle','MomentaryToggle','GuardedSwitch'):
  cylinder('Housing',r,(0,0,-.012),.008,.024); cylinder('MountingNut',r,(0,0,.002),.0085,.004,vertices=6)
  cylinder('Bushing',r,(0,0,.006),.0045,.01)
  pivot=empty('Actuator',r,(0,0,.009)); moving.append('Actuator')
  cylinder('Stem',pivot,(0,0,.006),.0023,.014)
  polygon('WedgeHandle',pivot,[(-.0035,-.0025),(.0035,-.0025),(.0055,.0025),(-.0055,.0025)],.011,f['handle_tip_z_m'],'Aluminum')
  box('PositionTip',pivot,(0,0,f['handle_tip_z_m']+.0002),(.008,.003,.0006),'Tip',.0002)
  if id=='GuardedSwitch':
   # Generic hinged protective cage; configuration and hinge travel are provisional.
   for x in (-.012,.012): box('GuardBracket_'+('L' if x<0 else 'R'),r,(x,.020,.003),(.005,.007,.006),'Aluminum')
   g=empty('Guard',r,(0,.021,.006)); moving.append('Guard')
   for x in (-.011,.011): box('GuardRail_'+('L' if x<0 else 'R'),g,(x,-.022,.023),(.003,.047,.003),'Guard')
   box('GuardCrossbar',g,(0,-.044,.023),(.025,.003,.003),'Guard')
   for x in (-.011,.011): box('GuardRiser_'+('L' if x<0 else 'R'),g,(x,0,.011),(.003,.003,.025),'Guard')
   hinge=cylinder('HingePin',r,(0,.021,.006),.002,.029); hinge.rotation_euler.z=math.pi/2
 elif id=='RotarySelector':
  cylinder('Housing',r,(0,0,-.015),.013,.03); cylinder('MountingNut',r,(0,0,.0015),.008,.003,vertices=6)
  pivot=empty('Actuator',r,(0,0,.003)); moving.append('Actuator')
  cylinder('CircularSkirt',pivot,(0,0,.002),f['skirt_radius_m'],.004,'Aluminum',64)
  polygon('PointerGrip',pivot,[(-.006,-.014),(.006,-.014),(.008,.002),(0,.016),(-.008,.002)],.004,.016,'Charcoal')
  polygon('PointerIndicium',pivot,[(-.0007,.008),(.0007,.008),(0,.014)],.016,.0163,'Legend')
 elif id=='CircuitBreaker':
  cylinder('Housing',r,(0,0,-.014),.0065,.028); cylinder('MountingNut',r,(0,0,.0015),.008,.003,vertices=6)
  # Sleeve occludes aluminum band until plunger moves outward.
  cylinder('Sleeve',r,(0,0,.004),.005,.005,'Charcoal')
  pivot=empty('Actuator',r,(0,0,.0065)); moving.append('Actuator')
  cylinder('OpenBand',pivot,(0,0,-.0025),.004,.005,'Aluminum'); cylinder('BlackKnob',pivot,(0,0,.0035),f['knob_radius_m'],.007,'Charcoal')
 elif id=='Talkback':
  box('Housing',r,(0,0,-.008),(.026,.019,.016),'Charcoal')
  for x in (-.012,.012): box('BezelSide_'+('L' if x<0 else 'R'),r,(x,0,.002),(.003,.019,.004),'Aluminum')
  for y in (-.008,.008): box('BezelEnd_'+('L' if y<0 else 'U'),r,(0,y,.002),(.021,.003,.004),'Aluminum')
  face=empty('Indication',r); moving.append('Indication')
  box('GrayFlag',face,(0,0,.0008),(.021,.013,.001),'Flag',0)
  pole=empty('BarberPole',face,(0,0,-.002))
  box('FlagBacking',pole,(0,0,0),(.021,.013,.0005),'Legend',0)
  # Clipped diagonal polygons stay inside the aperture.
  for i in range(-4,5):
   poly=[(-.0105,-.0065),(.0105,-.0065),(.0105,.0065),(-.0105,.0065)]
   def clip(poly,k,greater):
    result=[]
    for a,b in zip(poly,poly[1:]+poly[:1]):
     fa=a[0]-a[1]-k; fb=b[0]-b[1]-k; ia=fa>=0 if greater else fa<=0; ib=fb>=0 if greater else fb<=0
     if ia: result.append(a)
     if ia!=ib:
      t=fa/(fa-fb); result.append((a[0]+t*(b[0]-a[0]),a[1]+t*(b[1]-a[1])))
    return result
   poly=clip(clip(poly,i*.006,True),i*.006+.003,False)
   if len(poly)>2: polygon('Stripe_'+str(i+4),pole,poly,.0003,.0005,'Charcoal')
 if 'neutral_actuator_deg' in f:
  pivot.rotation_euler.x=math.radians(f['neutral_actuator_deg']) if id=='GuardedSwitch' else 0
  if id=='RotarySelector': pivot.rotation_euler.y=-math.radians(f['neutral_actuator_deg'])
 for child in r.children_recursive: child.name=id+'__'+child.name.split('.')[0]
 moving=[id+'__'+n for n in moving]
 entries.append({'id':id,'mount':r.name,'moving':moving,'parameters':f})
# Export directly with an explicit basis conversion on points, normals and every local transform.
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
for r in roots: usd_export(r)
(D/'components.json').write_text(json.dumps({'coordinate_convention':'+X right, +Y overhead, -Z forward; meters','author_to_usd':'(x,y,z) -> (x,z,-y)','components':entries},indent=2)+'\n')
# Inspection-board-only objects: never exported to family files.
board=empty('INSPECTION_BOARD_PREVIEW_ONLY')
for i,r in enumerate(roots):
 x=(i%3-1)*.115; y=(.055 if i<3 else -.065); r.location=B((x,y,0))
 box('PreviewTile_'+str(i),board,(x,y,-.003),(.102,.102,.003),'Panel')
 label('PreviewTitle_'+str(i),board,r['family'].upper(),(x,y+.038,.0002),.005)
 label('PreviewQualifier_'+str(i),board,'PROVISIONAL SIZE',(x,y-.041,.0002),.003)
 # Abstract inspection positions, never spacecraft placards.
 if i in (0,1):
  for j,t in enumerate(['A','CENTER','B']): label('PreviewPosition_'+str(i)+'_'+str(j),board,t,(x+.030,y+.022-j*.019,.001),.003)
 if i==3:
  for j,a in enumerate([-45,-15,15,45]):
   rad=math.radians(a); label('PreviewDetent_'+str(j),board,str(j+1),(x+math.sin(rad)*.03,y+math.cos(rad)*.03,.001),.003)
label('InspectionHeading',board,'LM CONTROL FAMILIES / INSPECTION ONLY',(0,.132,0),.007)
label('InspectionSubheading',board,'NOT A FLIGHT PANEL   -   NO SIMULATION BINDINGS',(0,.119,0),.0035)
# Fast workbench render only, no bake or ray-traced render.
s.render.engine='BLENDER_WORKBENCH'; s.render.resolution_x=1200; s.render.resolution_y=900; s.render.resolution_percentage=100
s.display.shading.light='STUDIO'; s.display.shading.color_type='MATERIAL'; s.display.shading.show_shadows=True; s.display.shading.show_cavity=True; s.display.shading.cavity_type='BOTH'; s.display.shading.background_type='WORLD'; s.world.color=(.028,.028,.028)
s.view_settings.view_transform='Standard'
bpy.ops.object.camera_add(); camera=bpy.context.object; camera.name='InspectionCamera'; camera.data.type='ORTHO'; camera.data.ortho_scale=.39; s.camera=camera
camera.location=B((.08,.065,.65)); direction=Vector(B((0,.005,0)))-camera.location; camera.rotation_euler=direction.to_track_quat('-Z','Y').to_euler(); camera.data.clip_start=.001
bpy.ops.wm.save_as_mainfile(filepath=str(D/'ControlLibrary.blend'))
s.render.filepath=str(D/'review'/'inspection.png'); bpy.ops.render.render(write_still=True)
# Separate motion demonstration, discarded after rendering; neutral blend remains saved.
for r in roots:
 act=next((c for c in r.children if c.name.endswith('__Actuator')),None)
 if r['family'] in ('MaintainedToggle','MomentaryToggle','GuardedSwitch'): act.rotation_euler.x=math.radians(-17)
 if r['family']=='GuardedSwitch': next(c for c in r.children if c.name.endswith('__Guard')).rotation_euler.x=math.radians(-100)
 if r['family']=='RotarySelector': act.rotation_euler.y=math.radians(-45)
 if r['family']=='CircuitBreaker': act.location.y-=.005
 if r['family']=='Talkback': next(o for o in r.children_recursive if o.name.endswith('__BarberPole')).location.y=-.002
s.render.filepath=str(D/'review'/'motion-examples.png'); bpy.ops.render.render(write_still=True)
print('CONTROL_LIBRARY_BUILD_COMPLETE')
