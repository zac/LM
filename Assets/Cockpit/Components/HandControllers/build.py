"""blender -b --python build.py. All authored coordinates are X right/Y up/Z crewward."""
import bpy, math, json, time
from pathlib import Path
from mathutils import Vector, Matrix
from pxr import Usd, UsdGeom, UsdUtils, Sdf
P=Path(__file__).resolve().parent
bpy.ops.wm.read_factory_settings(use_empty=True)
S=bpy.context.scene; S.unit_settings.system='METRIC'; S.unit_settings.scale_length=1
S.render.resolution_x=640; S.render.resolution_y=640; S.render.resolution_percentage=100
S.render.engine='BLENDER_WORKBENCH'; S.display.shading.light='STUDIO'; S.display.shading.color_type='MATERIAL'; S.display.shading.show_cavity=True
S.world=bpy.data.worlds.new('Review World'); S.world.color=(.12,.12,.12)
def mat(n,c,metal=0):
 m=bpy.data.materials.new(n); m.diffuse_color=(*c,1); m.use_nodes=True
 bs=m.node_tree.nodes.get('Principled BSDF'); bs.inputs['Base Color'].default_value=(*c,1); bs.inputs['Metallic'].default_value=metal; bs.inputs['Roughness'].default_value=.55
 return m
case=mat('Painted warm gray housing',(.39,.42,.40)); rubber=mat('Dark elastomer',(.045,.042,.038)); grip=mat('Warm ivory grip provisional',(.61,.55,.41)); steel=mat('Satin metal',(.38,.4,.42),.65); black=mat('Dark hardware',(.08,.08,.075))
entries=[]
def empty(n,p=None,loc=(0,0,0),motion=None,axis=None,demo=0):
 o=bpy.data.objects.new(n,None); S.collection.objects.link(o); o.parent=p; o.location=loc
 if motion: entries.append(dict(name=n,parent=p.name,neutral_origin_m=list(loc),neutral_rotation_degrees=[0,0,0],motion=motion,axis=axis,demonstration_offset=demo,limits='UNVERIFIED; demonstration is not a mechanical stop'))
 return o
def box(n,loc,dim,m,p,bevel=.003):
 bpy.ops.mesh.primitive_cube_add(size=1); o=bpy.context.object; o.name=n; o.dimensions=dim; bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 if bevel:
  mod=o.modifiers.new('Machined edge radius provisional','BEVEL'); mod.width=bevel; mod.segments=3; bpy.ops.object.modifier_apply(modifier=mod.name)
 o.parent=p; o.location=loc; o.data.materials.append(m); return o
def cyl(n,loc,r,d,m,p,axis='Y'):
 bpy.ops.mesh.primitive_cylinder_add(vertices=32,radius=r,depth=d); o=bpy.context.object; o.name=n
 if axis=='Y': o.rotation_euler.x=math.pi/2
 if axis=='X': o.rotation_euler.y=math.pi/2
 bpy.ops.object.transform_apply(location=False,rotation=True,scale=True); o.parent=p; o.location=loc; o.data.materials.append(m); return o
def loft(n,rings,p,m):
 # elliptical cross sections perpendicular to Y, capped, smooth side wall
 vs=[]; N=32
 for y,rx,rz,z in rings:
  vs.extend((rx*math.cos(i*2*math.pi/N),y,z+rz*math.sin(i*2*math.pi/N)) for i in range(N))
 fs=[tuple(reversed(range(N)))]
 for j in range(len(rings)-1):
  for i in range(N): a=j*N+i; b=j*N+(i+1)%N; fs.append((a,b,b+N,a+N))
 fs.append(tuple((len(rings)-1)*N+i for i in range(N)))
 mesh=bpy.data.meshes.new(n); mesh.from_pydata(vs,[],fs); mesh.update(); o=bpy.data.objects.new(n,mesh); S.collection.objects.link(o); o.parent=p; mesh.materials.append(m)
 bpy.context.view_layer.objects.active=o; bpy.ops.object.select_all(action='DESELECT'); o.select_set(True); bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT'); bpy.ops.mesh.normals_make_consistent(inside=False); bpy.ops.object.mode_set(mode='OBJECT')
 for f in mesh.polygons: f.use_smooth=len(f.vertices)==4
 return o
aca=empty('ACA_Mount'); fixed=empty('ACA_Fixed',aca)
box('ACA_Housing',(0,.056,0),(.1016,.112,.1699),case,fixed,.014)
box('ACA_TopPlate',(0,.114,0),(.1016,.008,.1699),steel,fixed,.003)
for x in [-.039,.039]:
 for z in [-.066,.066]: cyl('ACA_Fastener', (x,.119,z),.003,.0015,black,fixed)
# Figure 7 places roll pivot inside housing and pitch pivot within grip.
roll=empty('ACA_Roll',aca,(0,.061,0),'rotation','Z',-8)
yaw=empty('ACA_Yaw',roll,(0,.062,0),'rotation','Y',8)
pitch=empty('ACA_Pitch',yaw,(0,.077,0),'rotation','X',8)
loft('ACA_Grip',[( -.075,.026,.026,0),(-.066,.026,.023,0),(-.045,.018,.022,.004),(-.019,.016,.024,.007),(.014,.02,.026,.001),(.046,.024,.025,-.005),(.0555,.020,.023,-.004)],pitch,grip)
# Bellows are segmented visual shells, not a solved flexible seal.
for i in range(5):
 cyl('ACA_BootFold_'+str(i),(0,.121+i*.002,0),.037-i*.002,.0026,rubber,fixed)
trigger=empty('ACA_PTT_Trigger',pitch,(0,.02,-.028),'rotation','X',-6)
box('ACA_PTT_Paddle',(0,-.008,0),(.022,.027,.007),black,trigger,.003)
# TTCA: shared vertical arc for X translation/throttle, lateral arc and axial displacement.
ttca=empty('TTCA_Mount'); tf=empty('TTCA_Fixed',ttca)
box('TTCA_Housing',(0,.055,-.045),(.115,.11,.115),case,tf,.011)
box('TTCA_FrontPlate',(0,.057,.015),(.117,.111,.007),steel,tf,.003)
for x in [-.045,.045]:
 for y in [.017,.097]: cyl('TTCA_Fastener',(x,y,.019),.003,.002,black,tf,'Z')
vertical=empty('TTCA_VerticalShared',ttca,(0,.072,.021),'rotation','X',-15)
lateral=empty('TTCA_Lateral',vertical,(0,0,0),'rotation','Y',8)
axial=empty('TTCA_Axial',lateral,(0,0,0),'translation','Z',.007)
cyl('TTCA_Stem',(0,0,.055),.010,.11,steel,axial,'Z')
box('TTCA_TGrip',(0,0,.116),(.034,.105,.039),grip,axial,.013)
for side in [-1,1]: box('TTCA_GripEnd_'+str(side),(0,side*.05,.116),(.036,.006,.041),black,axial,.002)
for i in range(6): cyl('TTCA_BootFold_'+str(i),(0,0,.008+i*.004),.031-i*.0025,.004,rubber,lateral,'Z')
selector=empty('TTCA_ModeSelector',ttca,(.065,.056,-.02),'translation','Y',.018)
box('TTCA_SelectorStem',(0,0,0),(.008,.035,.01),steel,selector,.002); box('TTCA_SelectorTab',(0,.02,0),(.015,.012,.025),black,selector,.003)
friction=empty('TTCA_Friction',ttca,(-.039,.027,.025),'rotation','Z',30)
cyl('TTCA_FrictionKnob',(0,0,0),.011,.013,black,friction,'Z')
for i in range(12):
 a=i*math.tau/12; cyl('TTCA_FrictionFlute_'+str(i),(.009*math.cos(a),.009*math.sin(a),0),.002,.014,black,friction,'Z')
contract={'basis':'+X right, +Y up, +Z toward crew; not NASA vehicle axes','origin':'bottom center of provisional housing envelope; no flight mounting interface','state_owner':'LM presentation/input; AGC/LMCore simulation; no bindings implemented','entities':entries,'ACA':{'documented_maximum_envelope_m':[.1016,.2555,.1699],'source':'NASA TN D-7884 table III p8; not a neutral-pose dimensional drawing','pivot_interpretation':'Separated roll/pitch pivots from figure 7; exact positions and yaw coupling provisional'},'TTCA':{'dimensions':'All dimensions provisional; table V in TN D-7884 is CM THC and is deliberately not used','relationship':'VerticalShared serves jets X or descent throttle; lateral and axial remain available in both modes','mode':'neutral selector modeled down/JETS; upward slide selects THROTTLE; travel provisional','kinematics':'Vertical/lateral arcs and axial slide visual interpretation; internal linkage and cross-axis coupling unresolved','throttle':'TN D-7884 p10-11 gives 53 degree soft stop plus 10 degrees and center +33; LM10 handbook gives 10-92.5% engine thrust. Different quantities/revisions, not a calibrated mapping.'}}
(P/'interface.json').write_text(json.dumps(contract,indent=2)+'\n')
cost={'engine':'BLENDER_WORKBENCH','resolution':[640,640],'heavy_renders':0,'bakes':0,'renders':{}}
for root in [aca,ttca]:
 bpy.ops.object.select_all(action='DESELECT')
 for o in [root,*root.children_recursive]: o.select_set(True)
 name=root.name.split('_')[0]
 bpy.ops.wm.usd_export(filepath=str(P/(name+'.usdc')),selected_objects_only=True,export_animation=False,export_materials=True,generate_preview_surface=True,generate_materialx_network=False,convert_orientation=False,export_lights=False,export_cameras=False,triangulate_meshes=True)
 st=Usd.Stage.Open(str(P/(name+'.usdc'))); UsdGeom.SetStageUpAxis(st,'Y'); UsdGeom.SetStageMetersPerUnit(st,1); st.SetDefaultPrim(st.GetPrimAtPath('/'+root.name)); st.GetRootLayer().Save(); assert UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(str(P/(name+'.usdc'))),str(P/(name+'.usdz')))
bpy.ops.object.camera_add(); cam=bpy.context.object; cam.name='Review_Camera'; cam.data.type='ORTHO'; cam.data.ortho_scale=.34; S.camera=cam
bpy.ops.wm.save_as_mainfile(filepath=str(P/'HandControllers.blend'))
for root in [aca,ttca]:
 name=root.name.split('_')[0]
 for other in [aca,ttca]:
  for o in other.children_recursive: o.hide_render=other!=root
 target=Vector((0,.12,0)) if root==aca else Vector((0,.07,.025))
 for view,offset in [('front',(0,0,1)),('side',(1,0,0)),('oblique',(.65,.4,1)),('motion',(.65,.4,1))]:
  if view=='motion':
   for e in entries:
    if e['name'].startswith(name):
     o=bpy.data.objects[e['name']]; idx='XYZ'.index(e['axis'])
     if e['motion']=='rotation': o.rotation_euler[idx]=math.radians(e['demonstration_offset'])
     else: o.location[idx]+=e['demonstration_offset']
  cam.location=target+Vector(offset); back=(cam.location-target).normalized(); right=Vector((0,1,0)).cross(back).normalized(); up=back.cross(right); cam.rotation_euler=Matrix((right,up,back)).transposed().to_euler(); S.render.filepath=str(P/'review'/(name+'-'+view+'.png')); t=time.perf_counter(); bpy.ops.render.render(write_still=True); cost['renders'][name+'-'+view]=time.perf_counter()-t
 for e in entries:
  if e['name'].startswith(name): o=bpy.data.objects[e['name']]; o.location=e['neutral_origin_m']; o.rotation_euler=(0,0,0)
(P/'review/render-cost.json').write_text(json.dumps(cost,indent=2)+'\n')
