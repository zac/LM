"""FDAI visual component. Blender 5.2; component-local output only.
Deliberately authored Y-up: X right, Y top, Z toward crew, meters.
No dynamics or instrument-state implementation. See HANDOFF.md.
"""
import bpy, math, json, time, sys
from pathlib import Path
from mathutils import Vector
P=Path(__file__).resolve().parent
bpy.ops.wm.read_factory_settings(use_empty=True)
S=bpy.context.scene
S.unit_settings.system='METRIC'; S.unit_settings.scale_length=1
S.render.engine='BLENDER_EEVEE'
S.render.resolution_x=S.render.resolution_y=800; S.render.resolution_percentage=100
S.world=bpy.data.worlds.new('ReviewWorld'); S.world.use_nodes=True
S.world.node_tree.nodes['Background'].inputs[0].default_value=(.12,.14,.17,1)
S.world.node_tree.nodes['Background'].inputs[1].default_value=.4
S.view_settings.view_transform='Standard'

def mat(name,color,metal=0,rough=.45,alpha=1):
 m=bpy.data.materials.new(name); m.diffuse_color=(*color,alpha); m.use_nodes=True
 bs=m.node_tree.nodes.get('Principled BSDF'); bs.inputs['Base Color'].default_value=(*color,1); bs.inputs['Metallic'].default_value=metal; bs.inputs['Roughness'].default_value=rough; bs.inputs['Alpha'].default_value=alpha
 if alpha<1: m.surface_render_method='BLENDED'
 return m
black=mat('FDAI_Black_Enamel',(.018,.022,.023),.25,.34)
grey=mat('FDAI_Grey_Bezel',(.23,.245,.225),.3,.44)
rubber=mat('FDAI_Black_Seal',(.007,.009,.008),0,.75)
white=mat('FDAI_Ivory_Indices',(.84,.83,.72),0,.6)
orange=mat('FDAI_Amber_Error',(.95,.46,.045),.1,.38)
steel=mat('FDAI_Fastener_Steel',(.24,.27,.28),.8,.28)
glass=mat('FDAI_Glass',(.7,.85,.9),0,.12,.055)
ballmat=mat('FDAI_Ball_Print',(1,1,1),0,.66)
tex=bpy.data.images.load(str(P/'textures/fdai_8ball_albedo.png')); tex.pack(); tex.filepath='//textures/fdai_8ball_albedo.png'
nd=ballmat.node_tree.nodes.new('ShaderNodeTexImage'); nd.image=tex
ballmat.node_tree.links.new(nd.outputs['Color'],ballmat.node_tree.nodes['Principled BSDF'].inputs['Base Color'])

def empty(name,loc=(0,0,0),parent=None):
 o=bpy.data.objects.new(name,None); S.collection.objects.link(o); o.location=loc; o.parent=parent; o.empty_display_size=.01; return o
root=empty('FDAI_Mount'); root['status']='visual_only'; root['datum']='provisional panel seating plane; X right Y up Z crew; meters'
fixed=empty('FDAI_Fixed',parent=root)

def finish(o,name,m,parent=fixed):
 o.name=name; o.parent=parent
 if m: o.data.materials.append(m)
 return o

def cube(name,loc,size,m=black,parent=fixed,bevel=0):
 bpy.ops.mesh.primitive_cube_add(size=1,location=loc); o=finish(bpy.context.object,name,m,parent); o.dimensions=size
 bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 if bevel:
  mod=o.modifiers.new('Machined_edges','BEVEL'); mod.width=bevel; mod.segments=3
  bpy.context.view_layer.objects.active=o; bpy.ops.object.modifier_apply(modifier=mod.name)
 return o

def mesh(name,verts,faces,m,parent=fixed):
 d=bpy.data.meshes.new(name); d.from_pydata(verts,[],faces); d.update(); o=bpy.data.objects.new(name,d); S.collection.objects.link(o); finish(o,name,m,parent); return o

def ring(name,outer,inner,z0,z1,m,steps=128,octagon=False):
 def point(r,i,z):
  a=2*math.pi*i/steps
  if octagon:
   # ray intersection with a square with clipped 29% corners
   c,s=abs(math.cos(a)),abs(math.sin(a)); r=r/min(1e9,max(c,s,(c+s)/1.41421356))
  return (r*math.cos(a),r*math.sin(a),z)
 vs=[point(r,i,z) for z,r in [(z0,outer),(z0,inner),(z1,outer),(z1,inner)] for i in range(steps)]
 fs=[]
 for i in range(steps):
  j=(i+1)%steps
  fs += [(i,j,2*steps+j,2*steps+i),(steps+j,steps+i,3*steps+i,3*steps+j),(2*steps+i,2*steps+j,3*steps+j,3*steps+i),(j,i,steps+i,steps+j)]
 return mesh(name,vs,fs,m)

def cyl(name,loc,r,depth,m=steel,parent=fixed):
 bpy.ops.mesh.primitive_cylinder_add(vertices=48,radius=r,depth=depth,location=loc); return finish(bpy.context.object,name,m,parent)

def label(name,body,loc,size=.003,m=white,parent=fixed,angle=0):
 bpy.ops.object.text_add(location=loc); o=bpy.context.object; o.data.body=body; o.data.align_x='CENTER'; o.data.align_y='CENTER'; o.data.size=size; o.data.extrude=.000012; o.rotation_euler.z=angle
 bpy.ops.object.convert(target='MESH'); return finish(bpy.context.object,name,m,parent)

# Nominal photographed envelope, NOT a qualified cutout or LM-5 drawing.
cube('FDAI_RearHousing',(0,0,-.104),( .127,.127,.208),black,bevel=.008)
ring('FDAI_Flange',.073025,.063,-.003,0,grey,128,True)
ring('FDAI_FaceBezel',.073025,.0615,0,.009,grey,128,True)
cube('FDAI_MountingPlate',(0,0,-.002),(.14605,.14605,.004),grey,bevel=.004)
ring('FDAI_FaceGasket',.074025,.0726,-.002,.001,rubber,128,True)
ring('FDAI_InnerOctagonalMask',.0615,.0475,.001,.011,black,128,True)
ring('FDAI_BallSurround',.051,.0468,.011,.043,black)
ring('FDAI_OpticalSeal',.0479,.0467,.043,.044,rubber)
# Thin transparent plane in front of spherical ball apex. No refraction promised.
mesh('FDAI_Glass',[(.0472*math.cos(i*2*math.pi/128),.0472*math.sin(i*2*math.pi/128),.043) for i in range(128)],[tuple(range(128))],glass)
for x in [-1,1]:
 for y in [-1,1]:
  cyl(f'FDAI_MountScrew_{x}_{y}',(x*.063,y*.063,.001),.0025,.002)
  cube(f'FDAI_MountSlot_{x}_{y}',(x*.063,y*.063,.0021),(.003,.0005,.00015),rubber)
  cyl(f'FDAI_InnerScrew_{x}_{y}',(x*.0475,y*.0475,.012),.002,.0015,black)
  cube(f'FDAI_InnerSlot_{x}_{y}',(x*.0475,y*.0475,.0128),(.0026,.00035,.0001),steel)
# Provisional rear seam and connector envelope, intentionally no invented pinout/serial.
for z in [-.038,-.19]:
 for x in [-1,1]: cube(f'FDAI_CaseSeam_{x}_{z}',(x*.0636,0,z),(.0006,.115,.001),rubber)
cyl('FDAI_RearConnectorShell',(0,-.027,-.221),.015,.02,steel)
cyl('FDAI_RearConnectorInsert',(0,-.027,-.232),.012,.002,rubber)
cube('FDAI_BlankIdentificationPlate',(0,.036,-.2085),(.053,.022,.0007),steel,bevel=.00015)

# Ball parameterization: UV latitude along +X, zero meridian through +Z.
# Thus yaw caps are left/right, and pitch meridians cross the central wing.
pivot=empty('FDAI_Ball_Pivot',(0,0,-.008),root)
pivot['axis_convention']='X right Y up Z crew; quaternion supplied externally; UV zero seam +Z; yaw caps +/-X'
vs=[]; uvs=[]; fs=[]; n=128; k=64; r=.05
# Avoid degenerate polar quads with separate pole triangles.
vs.append((-r,0,0)); uvs.append((.5,0))
for j in range(1,k):
 lat=-math.pi/2+math.pi*j/k
 for i in range(n+1):
  lon=-math.pi+2*math.pi*i/n
  vs.append((r*math.sin(lat),-r*math.cos(lat)*math.sin(lon),r*math.cos(lat)*math.cos(lon))); uvs.append((i/n,j/k))
end=len(vs); vs.append((r,0,0)); uvs.append((.5,1))
for i in range(n): fs.append((0,1+i,2+i))
for j in range(k-2):
 for i in range(n):
  a=1+j*(n+1)+i; fs.append((a,a+n+1,a+n+2,a+1))
for i in range(n): fs.append((end,1+(k-2)*(n+1)+i+1,1+(k-2)*(n+1)+i))
ball=mesh('FDAI_Ball',vs,fs,ballmat,pivot)
uv=ball.data.uv_layers.new(name='st')
for poly in ball.data.polygons:
 poly.use_smooth=True
 for li in poly.loop_indices: uv.data[li].uv=uvs[ball.data.loops[li].vertex_index]
# Ensure outward normals regardless of parametric winding.
bpy.context.view_layer.objects.active=ball; ball.select_set(True)
bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT'); bpy.ops.mesh.normals_make_consistent(inside=False); bpy.ops.object.mode_set(mode='OBJECT'); ball.select_set(False)

# Fixed circumferential roll scale; 5-degree ticks and 30-degree abbreviations.
for i in range(72):
 a=2*math.pi*i/72; major=i%6==0; length=.0024 if major else .0013
 o=cube(f'FDAI_RollTick_{i:02}',(math.sin(a)*.0488,math.cos(a)*.0488,.0445),(.00055,length,.00025),white); o.rotation_euler.z=-a
 if major:
  label(f'FDAI_RollLegend_{i:02}',str(i*5//10),(math.sin(a)*.0455,math.cos(a)*.0455,.0438),.0024,angle=-a)
# Separately driven roll pointer: application supplies roll readout, not a child of the ball.
rollbug=empty('FDAI_RollBug_Pivot',(0,0,.0448),root)
mesh('FDAI_RollBug',[(-.0015,.044,0),(.0015,.044,0),(0,.047,0)],[(0,1,2)],white,rollbug)
# Fixed error reference brackets. LM-8 photograph supports amber edge markings;
# exact spacing is digitized/provisional, not a calibrated angular range.
for side in ['Roll','Pitch','Yaw']:
 for i in [-2,-1,0,1,2]:
  x=i*.006; y=.039
  if side=='Yaw': y=-y
  if side=='Pitch': x,y=y,x
  cube(f'FDAI_{side}_ErrorIndex_{i+2}',(x,y,.0446),(.0018,.0005,.0002) if side=='Pitch' else (.0005,.0018,.0002),orange)
# LM fixed crosshair, not the CSM inverted-wing symbol.
for axis in ['Horizontal','Vertical']:
 cube('FDAI_Reticle_'+axis+'_Outline',(0,0,.044),(.089,.00095,.0002) if axis=='Horizontal' else (.00095,.089,.0002),black)
 cube('FDAI_Reticle_'+axis,(0,0,.0443),(.089,.00035,.0002) if axis=='Horizontal' else (.00035,.089,.0002),white)
red=mat('FDAI_Red_SideBands',(.62,.023,.012),0,.55)
for side in [-1,1]:
 vs=[]
 for r in [.0475,.0505]:
  for i in range(25):
   a=math.radians(-12+i);vs.append((side*r*math.cos(a),r*math.sin(a),.0442))
 mesh('FDAI_RedSideBand_'+str(side),vs,[(i,i+1,26+i,25+i) for i in range(24)],red)

# Meter beds at top, right and bottom; axis identities from LM-8 photograph.
for axis,cx,cy,rot in [('Roll',0,.058,0),('Pitch',.058,0,-math.pi/2),('Yaw',0,-.058,0)]:
 holder=empty('FDAI_'+axis+'_RateScale',(cx,cy,.012),fixed); holder.rotation_euler.z=rot
 cube('FDAI_'+axis+'_RateWell',(0,0,0),(.054,.016,.005),rubber,holder,bevel=.001)
 cube('FDAI_'+axis+'_RateIvoryStrip',(0,.002,.003),(.05,.004,.0003),white,holder)
 for j in range(-10,11):
  length=.003 if j%5==0 else .0015
  cube(f'FDAI_{axis}_RateTick_{j+10:02}',(j*.0023,-.001-length/2,.0031),(.0004,length,.00025),white,holder)
 label('FDAI_'+axis+'_RateZero','0',(0,-.006,.0032),.0024,white,holder)
 label('FDAI_'+axis+'_RateLabel',axis.upper()+' RATE',(0,.006,.0032),.0026,white,holder)
 # Provisional hidden galvanometer pivot; no exposed mechanism invented.
 origin={'Roll':(0,.100,.020),'Pitch':(.100,0,.020),'Yaw':(0,-.100,.020)}[axis]
 rate=empty('FDAI_Rate_'+axis+'_Pivot',origin,root)
 rate['motion']='rotation about local +Z; +/-27 degrees provisional; application calibration required'
 points=[(-.0015,-.038,0),(.0015,-.038,0),(0,-.0435,0)]
 if axis=='Pitch': points=[(y,-x,z) for x,y,z in points]
 if axis=='Yaw': points=[(-x,-y,z) for x,y,z in points]
 mesh('FDAI_Rate_'+axis+'_Needle',points,[(0,1,2)],black,rate)

# Three independent error bars; hidden origins at the photograph's edge supports.
for axis,loc,size,center in [('Roll',(0,.046,.045),(.00075,.043,.0005),(0,-.0215,0)),('Pitch',(.046,0,.0455),(.043,.00075,.0005),(-.0215,0,0)),('Yaw',(0,-.046,.046),(.00075,.043,.0005),(0,.0215,0))]:
 p=empty('FDAI_Error_'+axis+'_Pivot',loc,root); p['motion']='rotation about local +Z; +/-25 degrees provisional'
 cube('FDAI_Error_'+axis+'_Needle',center,size,orange,p)
 cyl('FDAI_Error_'+axis+'_Hub',(0,0,0),.0013,.001,steel,p)

# Neutral integration asset: all seven movable groups neutral, no animation.
bpy.ops.object.select_all(action='DESELECT')
for o in bpy.data.objects:
 if o==root or o.parent: o.select_set(True)
start=time.perf_counter()
bpy.ops.wm.usd_export(filepath=str(P/'FDAI.usdc'),selected_objects_only=True,export_animation=False,export_hair=False,export_materials=True,generate_preview_surface=True,generate_materialx_network=False,convert_orientation=False,convert_world_material=False,root_prim_path='',export_lights=False,export_cameras=False,triangulate_meshes=True,export_textures_mode='NEW',overwrite_textures=True,relative_paths=True)
from pxr import Usd,UsdGeom,UsdShade,Sdf,UsdUtils
stage=Usd.Stage.Open(str(P/'FDAI.usdc')); UsdGeom.SetStageUpAxis(stage,'Y'); UsdGeom.SetStageMetersPerUnit(stage,1); stage.SetDefaultPrim(stage.GetPrimAtPath('/FDAI_Mount'))
for prim in stage.Traverse():
 if prim.IsA(UsdShade.Shader) and prim.GetAttribute('info:id').Get()=='UsdPreviewSurface' and 'FDAI_Glass' in str(prim.GetPath()):
  UsdShade.Shader(prim).CreateInput('opacity',Sdf.ValueTypeNames.Float).Set(.055)
  UsdShade.Shader(prim).CreateInput('opacityThreshold',Sdf.ValueTypeNames.Float).Set(0.0)
stage.GetRootLayer().Save()
assert UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(str(P/'FDAI.usdc')),str(P/'FDAI.usdz'))
export_time=time.perf_counter()-start
# Review-only camera/lights, excluded from above neutral exports.
bpy.ops.object.camera_add(location=(0,0,.5)); cam=bpy.context.object; cam.name='Review_Camera'; S.camera=cam; cam.data.type='ORTHO'; cam.data.ortho_scale=.172
for name,loc,power,size in [('Key',(-.15,.2,.3),1.0,.25),('Fill',(.2,0,.15),.4,.15)]:
 bpy.ops.object.light_add(type='AREA',location=loc); o=bpy.context.object; o.name='Review_'+name; o.data.energy=power; o.data.shape='DISK'; o.data.size=size; o.rotation_euler=(Vector((0,0,0))-o.location).to_track_quat('-Z','Y').to_euler()
S.render.image_settings.file_format='PNG'; S.render.filepath='//review/front.png'
# Pack texture for portable source; retain exported relative texture for USD.
bpy.ops.wm.save_as_mainfile(filepath=str(P/'FDAI.blend'))
# Small quick reviews only; no heavy rendering or bake.
S.render.engine='BLENDER_WORKBENCH'; S.display.shading.light='STUDIO'; S.display.shading.color_type='MATERIAL'; S.display.shading.show_shadows=True; S.display.shading.show_cavity=True
cost={'export_seconds':export_time,'renders':{},'heavy_renders':0,'bakes':0}
def render(name,loc,target,scale,engine):
 cam.location=loc; cam.rotation_euler=(Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler(); cam.data.ortho_scale=scale
 S.render.engine=engine; S.render.filepath=str(P/'review'/name); t=time.perf_counter(); bpy.ops.render.render(write_still=True); cost['renders'][name]=time.perf_counter()-t
render('geometry.png',(0,0,.5),(0,0,0),.172,'BLENDER_WORKBENCH')
S.render.engine='BLENDER_EEVEE'
render('front.png',(0,0,.5),(0,0,0),.172,'BLENDER_EEVEE')
render('oblique.png',(.32,.20,.46),(0,0,-.095),.34,'BLENDER_EEVEE')
rollbug.rotation_euler.z=math.radians(-25)
pivot.rotation_euler=(math.radians(30),math.radians(20),math.radians(-25))
for i,axis in enumerate(['Roll','Pitch','Yaw']):
 p=bpy.data.objects['FDAI_Error_'+axis+'_Pivot']; p.rotation_euler.z=math.radians([18,-20,12][i])
 p=bpy.data.objects['FDAI_Rate_'+axis+'_Pivot']; p.rotation_euler.z=math.radians([20,-17,13][i])
render('static-motion-demo.png',(0,0,.5),(0,0,0),.172,'BLENDER_EEVEE')
(P/'review/render-cost.json').write_text(json.dumps(cost,indent=2)+'\n')
print('FDAI build complete',cost)
