"""Rebuild only CrossPointer. Blender Y-up meters; explicit USD export. No peer execution."""
import bpy, math, json, sys
from pathlib import Path
from mathutils import Matrix, Vector
from pxr import Usd, UsdGeom, UsdShade, UsdUtils, Sdf, Gf
OUT=Path(__file__).resolve().parent
bpy.context.preferences.filepaths.save_version=0
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
for m in list(bpy.data.materials): bpy.data.materials.remove(m)
bpy.context.scene.unit_settings.system='METRIC'; bpy.context.scene.unit_settings.scale_length=1

def material(name,rgb,emit=0):
 m=bpy.data.materials.new(name);m.diffuse_color=(*rgb,1);m['emission_strength']=emit;return m
case=material('CaseGray',(.16,.19,.19));black=material('FaceBlack',(.008,.009,.008));rim=material('BezelCharcoal',(.025,.032,.031));ivory=material('ScaleWarmWhite',(.90,.87,.71),.20);needle_mat=material('NeedleWhite',(.99,.96,.81),.28);metal=material('ScrewMetal',(.28,.31,.30));dim=material('MultiplierInactive',(.09,.095,.072));red=material('PowerFlagInactive',(.08,.012,.009));back=material('RearHousing',(.055,.068,.068))
def node(name,parent=None,loc=(0,0,0)):
 o=bpy.data.objects.new(name,None);bpy.context.collection.objects.link(o);o.parent=parent;o.location=loc;return o
def mesh(name,verts,faces,mat,parent,loc=(0,0,0)):
 d=bpy.data.meshes.new(name);d.from_pydata(verts,[],faces);d.update();o=bpy.data.objects.new(name,d);bpy.context.collection.objects.link(o);o.parent=parent;o.location=loc;o.data.materials.append(mat);return o
def box(name,size,loc,mat,parent):
 x,y,z=[v/2 for v in size];return mesh(name,[(-x,-y,-z),(-x,-y,z),(-x,y,-z),(-x,y,z),(x,-y,-z),(x,-y,z),(x,y,-z),(x,y,z)],[(2,6,4,0),(5,7,3,1),(4,5,1,0),(3,7,6,2),(1,3,2,0),(6,7,5,4)],mat,parent,loc)
def ring(name,w,h,innerw,innerh,z,depth,mat,parent):
 g=node(name,parent)
 box(name+'_Left',((w-innerw)/2,h,depth),(-(w+innerw)/4,0,z),mat,g);box(name+'_Right',((w-innerw)/2,h,depth),((w+innerw)/4,0,z),mat,g)
 box(name+'_Top',(innerw,(h-innerh)/2,depth),(0,(h+innerh)/4,z),mat,g);box(name+'_Bottom',(innerw,(h-innerh)/2,depth),(0,-(h+innerh)/4,z),mat,g);return g

def label(name,text,loc,size,parent,mat=ivory):
 c=bpy.data.curves.new(name,'FONT');c.body=text;c.size=size;c.align_x='CENTER';c.align_y='CENTER';c.extrude=.000015;c.resolution_u=3
 o=bpy.data.objects.new(name,c);bpy.context.collection.objects.link(o);o.parent=parent;o.location=loc;c.materials.append(mat)
 bpy.context.view_layer.objects.active=o;o.select_set(True);bpy.ops.object.convert(target='MESH');o.select_set(False);return bpy.context.view_layer.objects.active
root=node('CrossPointer');fixed=node('Fixed',root);moving=node('Needles',root);scales=node('Scales',fixed);legends=node('Legends',fixed)
# Deliberate 61mm square fits 140x65 provisional slot without anisotropic scaling.
box('RearHousing',(.055,.055,.020),(0,0,-.010),back,fixed)
ring('Bezel',.061,.061,.054,.054,.0009,.0018,case,fixed)
ring('InnerBezel',.054,.054,.049,.049,.0014,.0016,rim,fixed)
box('DialFace',(.049,.049,.001),(0,0,.0005),black,fixed)
# Square instrument remains source proportioned. Scale zero offset admits the left/bottom legends.
zero=(.003,.003);travel=.016
for n in range(-20,21):
 y=zero[1]+travel*n/20;x=zero[0]+travel*n/20
 major=n%5==0;length=.0017 if major else .0009
 box('ForwardTick_'+str(n+20).zfill(2),(length,.00015,.00009),(-.0175-length/2,y,.00112),ivory,scales)
 box('LateralTick_'+str(n+20).zfill(2),(.00015,length,.00009),(x,-.0175-length/2,.00112),ivory,scales)
 if major:
  label('ForwardNumber_'+str(n+20),str(abs(n)),(-.021,y,.00120),.00265,scales)
  label('LateralNumber_'+str(n+20),str(abs(n)),(x,-.021,.00120),.00265,scales)
box('ZeroLineVertical',(.00012,.037,.00008),(zero[0],zero[1],.0011),dim,scales)
box('ZeroLineHorizontal',(.037,.00012,.00008),(zero[0],zero[1],.0011),dim,scales)
# Curved slim blades are display proxies, not a claim about unobserved pivots/mechanism.
def blade(name,parent,vertical=False):
 length=.038;width=.00045;n=24;verts=[]
 for i in range(n+1):
  t=i/n;a=-length/2+t*length;bow=.00075*math.sin(math.pi*t)
  for z in [-.00008,.00008]:
   for side in [-1,1]:
    if vertical:verts.append((-bow+side*width/2,a,z))
    else:verts.append((a,bow+side*width/2,z))
 faces=[]
 for i in range(n):
  k=i*4;j=k+4;faces += [(k,j,j+1,k+1),(k+2,k+3,j+3,j+2),(k,k+2,j+2,j),(k+1,j+1,j+3,k+3)]
 faces += [(0,1,3,2),(n*4,n*4+2,n*4+3,n*4+1)]
 return mesh(name,verts,faces,needle_mat,parent)
lat=node('LateralNeedle',moving,(zero[0],zero[1],.0017));blade('LateralBlade',lat,True)
fwd=node('ForwardNeedle',moving,(zero[0],zero[1],.00215));blade('ForwardBlade',fwd)
# Source legends, with unsupported RR/HI multipliers retained as inactive geometry.
label('ForwardLegend','FWD VEL',(-.0229,.002,.0013),.0014,legends).rotation_euler.z=math.pi/2
label('LateralLegend','LAT VEL',(.011,-.0232,.0013),.00165,legends)
label('MultiplierX10','X10',(-.003,-.0232,.0013),.00165,legends,dim)
label('MultiplierXPoint1','X.1',(-.012,-.0232,.0013),.00165,legends,dim)
# Power failure lens is inactive: do not use this as an invalid-simulation-data annunciator.
flag=node('PowerFailureFlag',fixed,(0,.0283,.0020));box('PowerFailureLens',(.005,.0015,.0003),(0,0,0),red,flag)
for i,(x,y) in enumerate([(-.028,.028),(.028,.028),(-.028,-.028),(.028,-.028)]):
 bpy.ops.mesh.primitive_cylinder_add(vertices=12,radius=.0012,depth=.0005,location=(x,y,.002));o=bpy.context.object;o.name='BezelScrew_'+str(i);o.parent=fixed;o.data.materials.append(metal);box('ScrewSlot_'+str(i),(.0016,.00018,.00005),(x,y,.00228),black,fixed)
bpy.context.view_layer.update()
# Neutral production has no cameras, lights, texture dependencies or baked state.
def export():
 stage=Usd.Stage.CreateNew(str(OUT/'CrossPointer.usda'));UsdGeom.SetStageMetersPerUnit(stage,1);UsdGeom.SetStageUpAxis(stage,'Y');mats={}
 for m in bpy.data.materials:
  u=UsdShade.Material.Define(stage,'/Materials/'+m.name);s=UsdShade.Shader.Define(stage,'/Materials/'+m.name+'/Surface');s.CreateIdAttr('UsdPreviewSurface')
  s.CreateInput('diffuseColor',Sdf.ValueTypeNames.Color3f).Set(Gf.Vec3f(*m.diffuse_color[:3]));s.CreateInput('roughness',Sdf.ValueTypeNames.Float).Set(.8)
  strength=m.get('emission_strength',0)
  if strength:s.CreateInput('emissiveColor',Sdf.ValueTypeNames.Color3f).Set(Gf.Vec3f(*[v*strength for v in m.diffuse_color[:3]]))
  u.CreateSurfaceOutput().ConnectToSource(s.ConnectableAPI(),'surface');mats[m.name]=u
 def emit(o,path):
  path+='/'+o.name;u=UsdGeom.Mesh.Define(stage,path) if o.type=='MESH' else UsdGeom.Xform.Define(stage,path);m=o.matrix_local
  UsdGeom.Xformable(u).AddTransformOp().Set(Gf.Matrix4d(*[m[j][i] for i in range(4) for j in range(4)]))
  if o.type=='MESH':
   o.data.calc_loop_triangles();points=[Gf.Vec3f(*v.co) for v in o.data.vertices];u.CreatePointsAttr(points);u.CreateFaceVertexCountsAttr([3]*len(o.data.loop_triangles));u.CreateFaceVertexIndicesAttr([i for t in o.data.loop_triangles for i in t.vertices]);u.CreateSubdivisionSchemeAttr('none');u.CreateDoubleSidedAttr(True);u.CreateExtentAttr(UsdGeom.PointBased.ComputeExtent(points));UsdShade.MaterialBindingAPI.Apply(u.GetPrim()).Bind(mats[o.data.materials[0].name])
  for c in sorted(o.children,key=lambda c:c.name):emit(c,path)
 emit(root,'');stage.SetDefaultPrim(stage.GetPrimAtPath('/CrossPointer'));stage.GetRootLayer().Save();stage.GetRootLayer().Export(str(OUT/'CrossPointer.usdc'))
 target=OUT/'CrossPointer.usdz'
 if target.exists():target.unlink()
 assert UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(str(OUT/'CrossPointer.usdc')),str(target))
export()
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'CrossPointer.blend'))
# Preview is a separate transient setup, not saved back to neutral source.
if '--preview' in sys.argv:
 scene=bpy.context.scene;scene.render.engine='BLENDER_WORKBENCH';scene.render.resolution_x=1000;scene.render.resolution_y=1000;scene.render.resolution_percentage=100;scene.display.shading.light='STUDIO';scene.display.shading.color_type='MATERIAL';scene.display.shading.show_shadows=False;scene.display.shading.show_cavity=True;scene.world.color=(.06,.06,.06)
 d=bpy.data.cameras.new('ReviewCamera');camera=bpy.data.objects.new('ReviewCamera',d);bpy.context.collection.objects.link(camera);camera.location=(0,0,.2);camera.rotation_euler=(0,0,0);d.type='ORTHO';d.ortho_scale=.073;scene.camera=camera
 (OUT/'review').mkdir(exist_ok=True)
 for name,l,f in [('neutral',0,0),('example-right-forward',-.008,.008),('negative-full-scale',.016,-.016)]:
  lat.location.x=zero[0]+l;fwd.location.y=zero[1]+f;scene.render.filepath=str(OUT/'review'/(name+'.png'));bpy.ops.render.render(write_still=True)
print('CROSSPOINTER BUILD COMPLETE')
