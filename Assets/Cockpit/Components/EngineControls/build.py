"""Source-qualified inert engine hardware and separate lunar-contact lens. No simulation."""
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


mat('ContactOff',(.008,.035,.11));mat('ButtonOff',(.065,.012,.012));mat('Stripe',(.65,.65,.58))
r=empty('EngineButtons_Mount');r['family']='EngineButtons'
# Hollow stepped guard; accepted DES RATE left support is preserved, not duplicated.
box('EngineButtons__RearBridge',r,(.011,-.003,.010),(.061,.086,.006),'Charcoal')
box('EngineButtons__RightWall',r,(.044,.012,.029),(.004,.061,.050),'Charcoal')
box('EngineButtons__UpperRail',r,(.011,.044,.051),(.062,.006,.006),'Charcoal')
box('EngineButtons__StopShelf',r,(.012,.018,.041),(.057,.043,.005),'Charcoal')
box('EngineButtons__StartStep',r,(.012,-.026,.015),(.057,.038,.018),'Charcoal')
# Diagonal face stripes restricted to the flat facade, not projected on moving button faces.
def striped_rect(name,c,w,h,z):
 for k in range(-12,13):
  poly=[(-w/2,-h/2),(w/2,-h/2),(w/2,h/2),(-w/2,h/2)]
  def clip(poly,b,ge):
   out=[]
   for a,q in zip(poly,poly[1:]+poly[:1]):
    fa=a[0]-a[1]-b;fq=q[0]-q[1]-b;ia=fa>=0 if ge else fa<=0;iq=fq>=0 if ge else fq<=0
    if ia:out.append(a)
    if ia!=iq:
     t=fa/(fa-fq);out.append((a[0]+t*(q[0]-a[0]),a[1]+t*(q[1]-a[1])))
   return out
  poly=clip(clip(poly,k*.010,True),k*.010+.0038,False)
  if len(poly)>2:polygon(name+str(k+12),r,[(x+c[0],y+c[1]) for x,y in poly],z,z+.00012,'Stripe')
striped_rect('EngineButtons__TopStripe',(.011,.044),.062,.006,.0541)
striped_rect('EngineButtons__LowerStripe',(.012,-.026),.057,.038,.0241)
# Start is circular, stop upper protected square. Both independently movable; neutral only.
start=empty('EngineButtons__StartActuator',r,(.018,-.025,.027))
cylinder('EngineButtons__StartRim',start,(0,0,0),.014,.004,'Aluminum',64)
cylinder('EngineButtons__StartLightFace',start,(0,0,.0022),.0118,.0006,'ButtonOff',64)
box('EngineButtons__StartLegendBand',start,(0,0,.00265),(.022,.006,.0002),'Charcoal',0)
label('EngineButtons__StartLegend',start,'START',(0,-.0014,.00285),.0039)
stop=empty('EngineButtons__StopActuator',r,(.018,.018,.047))
box('EngineButtons__StopRim',stop,(0,0,0),(.029,.026,.006),'Aluminum',.001)
box('EngineButtons__StopLightFace',stop,(0,0,.0033),(.025,.022,.0006),'ButtonOff',.001)
label('EngineButtons__StopLegend',stop,'STOP',(0,-.0015,.0037),.004)
latch=empty('EngineButtons__StopResetLatch',r,(.018,.030,.055))
box('EngineButtons__LatchBridge',latch,(0,-.003,0),(.035,.003,.003),'Aluminum')
for x in [-.016,.016]:box('EngineButtons__LatchEar'+('Left' if x<0 else 'Right'),latch,(x,-.007,-.003),(.003,.012,.008),'Aluminum')
# Separate contact asset is instanced at two documented stations by the host.
c=empty('LunarContact_Mount');c['family']='LunarContact'
cylinder('LunarContact__Housing',c,(0,0,-.003),.013,.006,'Charcoal',64)
cylinder('LunarContact__Bezel',c,(0,0,.001),.013,.003,'Aluminum',64)
cylinder('LunarContact__Lens',c,(0,0,.0028),.0115,.001,'ContactOff',64)
cylinder('LunarContact__LightFace',c,(0,0,.0034),.0113,.0002,'ContactOff',64)
box('LunarContact__IndexTab',c,(0,.013,.0008),(.006,.003,.003),'Aluminum')
label('LunarContact__Legend',c,'LUNAR CONTACT',(0,.020,.00025),.0035)
roots=[r,c]
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
for root in roots:usd_export(root)
s.render.engine='BLENDER_WORKBENCH';s.render.resolution_x=1200;s.render.resolution_y=1000;s.render.resolution_percentage=100
s.display.shading.light='STUDIO';s.display.shading.color_type='MATERIAL';s.display.shading.show_shadows=True;s.display.shading.show_cavity=True;s.display.shading.cavity_type='BOTH';s.world.color=(.025,.025,.025);s.view_settings.view_transform='Standard'
bpy.ops.object.camera_add();cam=bpy.context.object;cam.name='ReviewCamera';cam.data.type='ORTHO';cam.data.clip_start=.001;s.camera=cam
for root in roots:
 for other in roots:
  other.hide_render=(other!=root)
  for ob in other.children_recursive:ob.hide_render=(other!=root)
 cam.data.ortho_scale=.13 if root==r else .072;cam.location=B((-.10,.12,.45)) if root==r else B((0,.035,.35));cam.rotation_euler=(Vector(B((.009,0,.02) if root==r else (0,.005,0)))-cam.location).to_track_quat('-Z','Y').to_euler()
 s.render.filepath=str(D/'review'/(root['family']+'-neutral.png'));bpy.ops.render.render(write_still=True)
for root in roots:
 root.hide_render=False
 for ob in root.children_recursive:ob.hide_render=False
bpy.ops.wm.save_as_mainfile(filepath=str(D/'EngineControls.blend'))
print('ENGINE_CONTROLS_BUILD_PASS')
