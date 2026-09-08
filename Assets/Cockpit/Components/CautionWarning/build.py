"""Build neutral warning/caution faces; Blender and USD physically Y-up/meters.
No power logic, alarm aggregation, simulation, collisions, lights or input targets.
"""
import bpy,json,math,hashlib,re
from pathlib import Path
from mathutils import Matrix,Vector,Quaternion
from pxr import Usd,UsdGeom,UsdShade,UsdUtils,Sdf,Gf
D=Path(__file__).resolve().parent
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False);bpy.context.preferences.filepaths.save_version=0
sc=bpy.context.scene;sc.unit_settings.system='METRIC';sc.unit_settings.scale_length=1;mats={}
def material(n,c,metal=0):
 m=bpy.data.materials.new(n);m.diffuse_color=(*c,1);m.use_nodes=True;s=m.node_tree.nodes['Principled BSDF'];s.inputs['Base Color'].default_value=(*c,1);s.inputs['Metallic'].default_value=metal;s.inputs['Roughness'].default_value=.52;mats[n]=m;return m
material('Panel',(.40,.43,.40));material('Bezel',(.14,.155,.15),.6);material('Gasket',(.012,.017,.016));material('UnpoweredLens',(.022,.029,.027));material('DormantLegend',(.20,.225,.205));material('Fastener',(.39,.405,.38),.8)
def node(n,p=None,pos=(0,0,0),q=None):
 o=bpy.data.objects.new(n,None);sc.collection.objects.link(o);o.parent=p;o.location=pos
 if q is not None:o.rotation_mode='QUATERNION';o.rotation_quaternion=Quaternion((q[3],*q[:3]))
 return o
def box(n,p,pos,size,mat,bevel=0):
 bpy.ops.mesh.primitive_cube_add();o=bpy.context.object;o.name=n;o.dimensions=size;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 if bevel:
  m=o.modifiers.new('Edge radius','BEVEL');m.width=min(bevel,min(size)/4);m.segments=3;bpy.ops.object.modifier_apply(modifier=m.name)
 o.parent=p;o.location=pos;o.data.materials.append(mats[mat]);return o
def label(n,p,body,pos,size):
 c=bpy.data.curves.new(n,'FONT');c.body=body;c.size=size;c.align_x='CENTER';c.align_y='CENTER';c.space_line=.95;c.resolution_u=3;c.extrude=0;c.materials.append(mats['DormantLegend']);o=bpy.data.objects.new(n,c);sc.collection.objects.link(o);o.parent=p;o.location=pos;bpy.ops.object.select_all(action='DESELECT');o.select_set(True);bpy.context.view_layer.objects.active=o;bpy.ops.object.convert(target='MESH');return bpy.context.object
root=node('CautionWarning');inv=json.loads((D/'evidence/inventory.json').read_text());rows=json.loads((D/'labels.json').read_text())['slots'];contract={'schema':'lmkit.caution-warning.interface.v1','root':'/CautionWarning','axes':'+X right +Y up -Z forward','units':'meters','root_pose':'identity Cabin-relative; do not reapply panel poses','base_revision':'035c5b3ad1a522cf6d25fb222d46c2fb4a4a8de8','inventory_sha256':hashlib.sha256((D/'evidence/inventory.json').read_bytes()).hexdigest(),'slots':[],'lamps':[],'default_state':'all unpowered; opaque dark lens and dim physical legends; no emission','installed_master_alarms':[],'master_alarm_reference':{'file':'MasterAlarmReference.usdz','root':'/MasterAlarmReference','placement':'UNASSIGNED; specimen only, never automatically install at Cabin origin','binding':None},'qualification':'All dimensions/fit/colors provisional. Generic source topology retained. No model availability implies a simulation channel.'}
for panel in inv['panels']:
 for slot in panel['slots']:
  sid=slot['id']
  if sid not in rows:continue
  pn=node(panel['id'],root,panel['pose']['translation_m'],panel['pose']['quaternion_xyzw']);mount=node(sid,pn,slot['pose']['translation_m']);w,h,_=slot['envelope_m']
  box('MountingPlate_'+sid,mount,(0,0,.0014),(w-.004,h-.002,.0024),'Panel',.0006)
  # A common source-proportioned module pair fits the smaller45mm warning slot.
  # Wide adapter plate is explicitly provisional; no historical array-size claim.
  for bi,bank in enumerate(rows[sid]):
   bn=node('Bank_'+str(bi+1)+'_'+sid,mount,((bi-.5)*.061,0,0));box('OuterBezel_'+bn.name,bn,(0,0,.004),(.056,.041,.005),'Bezel',.0012);box('Gasket_'+bn.name,bn,(0,0,.007),(.0515,.0365,.0015),'Gasket',.0008)
   for ri,row in enumerate(bank):
    for ci,legend in enumerate(row):
     cell=f'{sid}__B{bi+1}R{ri+1}C{ci+1}';lamp=node(cell,bn,((ci-.5)*.0245,(2-ri)*.0067,0));path=f'/CautionWarning/{panel["id"]}/{sid}/{bn.name}/{cell}'
     lens=box('Lens_'+cell,lamp,(0,0,.0083),(.0228,.0057,.0014),'UnpoweredLens',.00035)
     if legend:label('Legend_'+cell,lamp,legend,(0,0,.00905),.00225)
     lamp['source_legend']=legend;lamp['is_blank_source_cell']=not bool(legend);lamp['live_binding']='unavailable/not-qualified'
     contract['lamps'].append({'id':cell,'path':path,'lens_path':path+'/'+lens.name,'legend_path':path+'/Legend_'+cell if legend else None,'legend':legend,'blank':not bool(legend),'runtime_signal':None,'state':'unpowered neutral','source':'user-pdf panel1 or2, unknown mission revision'})
  for x in [-w/2+.005,w/2-.005]:
   bpy.ops.mesh.primitive_cylinder_add(vertices=16,radius=.0015,depth=.0006);o=bpy.context.object;o.name='MountScrew_'+sid+('_L' if x<0 else '_R');o.parent=mount;o.location=(x,0,.0027);o.data.materials.append(mats['Fastener'])
  contract['slots'].append({'id':sid,'overlay_path':f'/CautionWarning/{panel["id"]}/{sid}','panel_pose':panel['pose'],'slot_pose':slot['pose'],'envelope_m':slot['envelope_m'],'default_placeholder_node':slot['default_placeholder_node'],'replacement_allowed':slot['replacement_allowed'],'suppression':'After successful overlay+interface validation hide only this exact blank, retaining mount, frame and labels; failed/absent load retains blank.','module_pair_size_m':[.117,.041,.00905],'mounting_plate':'Provisional adapter fills current inventory footprint; historical hardware footprint is unresolved.'})
# Separately exported master-alarm specimen; no invented slot or mounted position.
master=node('MasterAlarmReference');box('MasterAlarm_Housing',master,(0,0,-.006),(.025,.027,.014),'Bezel',.002);box('MasterAlarm_Gasket',master,(0,0,.002),(.022,.024,.002),'Gasket',.001)
act=node('MasterAlarm_Button',master);box('MasterAlarm_Lens',act,(0,0,.004),(.019,.021,.003),'UnpoweredLens',.001);label('MasterAlarm_Legend',act,'MASTER\nALARM',(0,0,.00555),.0036);act['binding']='none; no assigned placement or travel limit'
bpy.context.view_layer.update()
def budget(r):
 objs=[o for o in r.children_recursive if o.type=='MESH'];vs=[o.matrix_world@Vector(v) for o in objs for v in o.bound_box]
 for o in objs:o.data.calc_loop_triangles()
 return {'mesh_count':len(objs),'triangles':sum(len(o.data.loop_triangles) for o in objs),'bounds_m':{'min':[min(v[i] for v in vs) for i in range(3)],'max':[max(v[i] for v in vs) for i in range(3)]}}
contract['budget']=budget(root);contract['master_alarm_reference']['budget']=budget(master);contract['named_lamps']=sum(not l['blank'] for l in contract['lamps']);contract['blank_cells']=sum(l['blank'] for l in contract['lamps']);(D/'interface.json').write_text(json.dumps(contract,indent=2)+'\n')
def export(r):
 stage=Usd.Stage.CreateNew(str(D/(r.name+'.usda')));UsdGeom.SetStageUpAxis(stage,'Y');UsdGeom.SetStageMetersPerUnit(stage,1)
 for n,m in mats.items():
  material=UsdShade.Material.Define(stage,'/Materials/'+n);s=UsdShade.Shader.Define(stage,'/Materials/'+n+'/Surface');s.CreateIdAttr('UsdPreviewSurface');s.CreateInput('diffuseColor',Sdf.ValueTypeNames.Color3f).Set(Gf.Vec3f(*m.diffuse_color[:3]));s.CreateInput('roughness',Sdf.ValueTypeNames.Float).Set(.52);s.CreateInput('metallic',Sdf.ValueTypeNames.Float).Set(m.node_tree.nodes['Principled BSDF'].inputs['Metallic'].default_value);material.CreateSurfaceOutput().ConnectToSource(s.ConnectableAPI(),'surface')
 def emit(o,parent):
  path=parent+'/'+o.name;xf=UsdGeom.Mesh.Define(stage,path) if o.type=='MESH' else UsdGeom.Xform.Define(stage,path);m=o.matrix_local;xf.AddTransformOp().Set(Gf.Matrix4d(*[m[j][i] for i in range(4) for j in range(4)]))
  if o.type=='MESH':
   pts=[Gf.Vec3f(*v.co) for v in o.data.vertices];xf.CreatePointsAttr(pts);xf.CreateFaceVertexCountsAttr([len(p.vertices) for p in o.data.polygons]);xf.CreateFaceVertexIndicesAttr([i for p in o.data.polygons for i in p.vertices]);xf.CreateSubdivisionSchemeAttr('none');xf.CreateExtentAttr(UsdGeom.PointBased.ComputeExtent(pts));UsdShade.MaterialBindingAPI.Apply(xf.GetPrim()).Bind(UsdShade.Material(stage.GetPrimAtPath('/Materials/'+o.data.materials[0].name)))
  for c in o.children:emit(c,path)
  return xf
 u=emit(r,'');stage.SetDefaultPrim(u.GetPrim());stage.GetRootLayer().Save();stage.GetRootLayer().Export(str(D/(r.name+'.usdc')));target=D/(r.name+'.usdz')
 if target.exists():target.unlink()
 assert UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(str(D/(r.name+'.usdc'))),str(target))
export(root);export(master)
sc.render.engine='BLENDER_WORKBENCH';sc.render.resolution_x=1400;sc.render.resolution_y=700;sc.render.resolution_percentage=100;sc.render.image_settings.file_format='PNG';sc.display.shading.light='STUDIO';sc.display.shading.color_type='MATERIAL';sc.display.shading.show_cavity=True;sc.display.shading.cavity_type='BOTH';sc.world.color=(.06,.06,.06);sc.view_settings.view_transform='Standard';sc.render.filepath='//review/warning.png'
camd=bpy.data.cameras.new('Inspection');cam=bpy.data.objects.new('Inspection',camd);sc.collection.objects.link(cam);sc.camera=cam;camd.type='ORTHO';camd.ortho_scale=.27
bpy.ops.wm.save_as_mainfile(filepath=str(D/'CautionWarning.blend'))
for key,sid,scale in [('warning','Panel1__Warning',.25),('caution','Panel2__Caution',.31),('master','MasterAlarmReference',.075)]:
 target=bpy.data.objects[sid].matrix_world.translation;cam.location=target+Vector((.01,.055,.45));forward=(target-cam.location).normalized();right=forward.cross(Vector((0,1,0))).normalized();up=right.cross(forward);cam.rotation_euler=Matrix((right,up,-forward)).transposed().to_euler();camd.ortho_scale=scale;sc.render.filepath=str(D/'review'/f'{key}.png');bpy.ops.render.render(write_still=True)
print('PASS BUILD',contract['named_lamps'],contract['blank_cells'],contract['budget'])
