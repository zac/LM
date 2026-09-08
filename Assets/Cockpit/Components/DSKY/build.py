"""Blender 5.2: blender -b --factory-startup --python build.py
All authoring inputs are local constants; no network, AGC emulation or add-ons.
Coordinate arguments are in the app's meter-based X-right/Y-up/Z-crew basis.
"""
import bpy, math, json, time, hashlib, sys
from pathlib import Path
from mathutils import Vector
OUT=Path(__file__).resolve().parent
sys.path.insert(0,str(OUT))
from usd_pipeline import normalize_and_package
I=.0254
W,H,D=8.124*I,8*I,6.91*I
DISPLAY_Y=(.5+2.33+4.67/2-4)*I
KEYS=[('VERB',1.11,2.25),('NOUN',1.11,1.55),
 ('PLUS',2.08,2.25),('7',2.98,2.25),('8',3.88,2.25),('9',4.78,2.25),('CLR',5.68,2.25),
 ('MINUS',2.08,1.55),('4',2.98,1.55),('5',3.88,1.55),('6',4.78,1.55),('PRO',5.68,1.55),
 ('0',2.08,.85),('1',2.98,.85),('2',3.88,.85),('3',4.78,.85),('KEY_REL',5.68,.85),
 ('ENTR',6.67,2.25),('RSET',6.67,1.55)]
LAMPS=[('UPLINK_ACTY',11),('NO_ATT',12),('STBY',13),('KEY_REL',14),('OPR_ERR',15),
 ('TEMP',21),('GIMBAL_LOCK',22),('PROG',23),('RESTART',24),('TRACKER',25),('ALT',26),('VEL',27)]
def xyz(p): return (p[0],-p[2],p[1])
def material(name,color,metal=0,rough=.5,emission=0):
 m=bpy.data.materials.new('DSKY_'+name); m.diffuse_color=(*color,1); m.use_nodes=True
 bs=m.node_tree.nodes.get('Principled BSDF'); bs.inputs['Base Color'].default_value=(*color,1)
 bs.inputs['Metallic'].default_value=metal; bs.inputs['Roughness'].default_value=rough
 bs.inputs['Emission Color'].default_value=(*color,1); bs.inputs['Emission Strength'].default_value=emission
 return m
def parent_at(o,parent,p):
 o.parent=parent; o.location=xyz(p); return o
def empty(name,parent=None,p=(0,0,0)):
 o=bpy.data.objects.new(name,None); bpy.context.collection.objects.link(o); return parent_at(o,parent,p)
def finish(o,name,mat,parent,p):
 o.name=name; o.data.name=name+'_Geometry'; o.data.materials.append(mat); parent_at(o,parent,p); return o
def box(name,p,size,mat,parent,bevel=.0005):
 bpy.ops.mesh.primitive_cube_add(); o=bpy.context.object
 o.dimensions=(size[0],size[2],size[1]); bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 if bevel:
  mod=o.modifiers.new('Machined edge radius','BEVEL'); mod.width=min(bevel,min(size)*.2); mod.segments=3
  bpy.ops.object.modifier_apply(modifier=mod.name)
 return finish(o,name,mat,parent,p)
def cylinder(name,p,r,depth,mat,parent,vertices=32):
 bpy.ops.mesh.primitive_cylinder_add(vertices=vertices,radius=r,depth=depth,rotation=(math.pi/2,0,0))
 o=bpy.context.object; bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
 mod=o.modifiers.new('Turned rim','BEVEL'); mod.width=min(.0003,depth*.2); mod.segments=2; bpy.ops.object.modifier_apply(modifier=mod.name)
 return finish(o,name,mat,parent,p)
def text(name,label,p,size,mat,parent,maxwidth=None):
 curve=bpy.data.curves.new(name,'FONT'); curve.body=label; curve.align_x='CENTER'; curve.align_y='CENTER'
 curve.size=size; curve.space_line=.9; curve.resolution_u=3; curve.extrude=0
 o=bpy.data.objects.new(name,curve); bpy.context.collection.objects.link(o); o.rotation_euler=(math.pi/2,0,0)
 parent_at(o,parent,p); bpy.context.view_layer.update()
 if maxwidth and o.dimensions.x>maxwidth: o.scale*=maxwidth/o.dimensions.x
 bpy.ops.object.select_all(action='DESELECT'); o.select_set(True); bpy.context.view_layer.objects.active=o
 bpy.ops.object.convert(target='MESH'); bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 o.data.materials.append(mat); return o
def frame(name,p,w,h,t,depth,mat,parent):
 for suffix,offset,size in [('L',(-w/2+t/2,0,0),(t,h,depth)),('R',(w/2-t/2,0,0),(t,h,depth)),
 ('T',(0,h/2-t/2,0),(w-2*t,t,depth)),('B',(0,-h/2+t/2,0),(w-2*t,t,depth))]:
  box(name+'_'+suffix,tuple(p[i]+offset[i] for i in range(3)),size,mat,parent,.0004)
def screw(name,x,y,z,parent):
 cylinder(name+'_Seat',(x,y,z-.0008),.0038,.001,steel,parent)
 cylinder(name+'_Head',(x,y,z),.0028,.0015,steel,parent)
 # Dark recessed-looking cross; visual approximation, not a certified screw specification.
 for i,sz in enumerate([(.0033,.00055,.00012),(.00055,.0033,.00012)]):
  box(name+'_Recess'+str(i),(x,y,z+.0008),sz,black,parent,.00006)
def digit(parent,name,x,y,width=.010,height=.014):
 d=empty(name,parent,(x,y,0)); thick=.001
 positions=[(0,height/2,width-thick,thick),(width/2,height/4,thick,height/2-thick),
 (width/2,-height/4,thick,height/2-thick),(0,-height/2,width-thick,thick),
 (-width/2,-height/4,thick,height/2-thick),(-width/2,height/4,thick,height/2-thick),(0,0,width-thick,thick)]
 for letter,(sx,sy,sw,sh) in zip('ABCDEFG',positions):
  box(name+'_'+letter,(sx,sy,.00025),(sw,sh,.0003),phosphor,d,.00012)
 for child in d.children:
  for v in child.data.vertices: v.co.x += .12*v.co.z
  child.location.x += .12*child.location.z
 return d

def build():
 global steel,black,phosphor
 bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
 for m in list(bpy.data.materials): bpy.data.materials.remove(m)
 scene=bpy.context.scene; scene.unit_settings.system='METRIC'; scene.unit_settings.scale_length=1
 face_mat=material('Paint_gray_olive',(.24,.255,.23),.35,.58)
 body_mat=material('Housing_anodized',(.32,.34,.31),.7,.46)
 black=material('Recess_black',(.009,.014,.012),0,.66)
 steel=material('Fasteners',(.39,.42,.40),.8,.29)
 keys_mat=material('Keycap_ivory',(.72,.74,.65),0,.42)
 ink=material('Key_ink',(.018,.024,.019),0,.6)
 glass=material('Display_dark_filter',(.012,.032,.024),.05,.24)
 legend=material('Face_legend',(.35,.63,.43),0,.55,.20)
 lampmat=material('Lamp_unpowered',(.23,.23,.23),0,.85)
 phosphor=material('Segments_unpowered',(.022,.052,.032),0,.48,.02)
 lit=material('EL_green_on',(.20,.85,.42),0,.4,.9)
 white_on=material('Status_white_on',(.75,.86,.71),0,.4,.35)
 amber_on=material('Caution_amber_on',(.95,.58,.10),0,.4,.35)
 for m in [lit,white_on,amber_on]: m.use_fake_user=True
 root=empty('DSKY_Mount'); root['source_baseline']='97f877b52bf569656c6798cff5790b7207c42af0'
 root['evidence']='Apollo11-led; outline2003956B; dimensions and uncertainties in HANDOFF.md'
 root['binding_status']='visual_only'; root['local_origin']='Face center at plate mid-depth'
 # Maximum total depth stays inside app budget, including protruding cap legend.
 back=.0153-D
 box('DSKY_Housing',(0,0,(back-.006)/2),(7.7*I,7.55*I,-.006-back),body_mat,root,.004)
 # Separate rear cover, seams and stiffening rails: provisional external reconstruction.
 box('DSKY_RearCover',(0,0,back+.002),(7.6*I,7.45*I,.004),face_mat,root,.002)
 for side in [-1,1]:
  for j in range(5):
   box('DSKY_SideRail_'+('L' if side<0 else 'R')+'_'+str(j),(side*.0973,0,-.035-j*.025),(.0015,.177,.003),steel,root,.0004)
 face=box('DSKY_Face',(0,0,0),(W,H,.012),face_mat,root,.0025)
 display=empty('DSKY_Display_Mount',root,(0,DISPLAY_Y,.010))
 # All display objects use local coordinates relative to the compatibility mount.
 box('DSKY_Display_Back',(0,0,-.002),(.17526,.118618,.002),black,display,.001)
 frame('DSKY_Display_OuterBezel',(0,0,-.0002),.179,.122,.003,.003,steel,display)
 box('DSKY_Annunciator_Filter',(-.047,0,0),(.075,.112,.001),glass,display,.0015)
 box('DSKY_Numeric_Filter',(.040,0,0),(.088,.112,.001),glass,display,.0015)
 frame('DSKY_AlarmBezel',(-.047,0,.0008),.077,.115,.002,.002,face_mat,display)
 frame('DSKY_NumericBezel',(.040,0,.0008),.091,.115,.002,.002,face_mat,display)
 lamp_specs=[]
 for row in [5,6]:
  box('DSKY_Lamp_Blank_'+str(row),(-.066,.045-row*.015113,.0012),(.02794,.013462,.0008),lampmat,display,.0006)
 # Two banks: five white condition lamps at left, seven caution/radar at right.
 for idx,(name,code) in enumerate(LAMPS):
  col=0 if idx<5 else 1; row=idx if idx<5 else idx-5
  x=-.066 if col==0 else -.029; y=.045-row*.015113
  node=empty('DSKY_Lamp_'+name,display,(x,y,.0012)); node['snapshot_indicator_id']=code
  box('DSKY_Lamp_'+name+'_Lens',(0,0,0),(.02794,.013462,.0008),lampmat,node,.0006)
  text('DSKY_Lamp_'+name+'_Legend',name.replace('_','\n'),(0,0,.0006),.0035,ink,node,.025)
  lamp_specs.append({'name':node.name,'indicator_id':code,'path':'/DSKY_Mount/DSKY_Display_Mount/'+node.name})
 comp=empty('DSKY_Lamp_COMP_ACTY',display,(.016,.041,.0012))
 box('DSKY_COMP_ACTY_Lens',(0,0,0),(.029,.025,.0008),lampmat,comp,.0008)
 text('DSKY_COMP_ACTY_Legend','COMP\nACTY',(0,0,.0006),.004,ink,comp)
 fields={}
 for name,x,y,count in [('PROG',.062,.033,2),('VERB',.017,.008,2),('NOUN',.062,.008,2),
 ('R1',.040,-.011,5),('R2',.040,-.029,5),('R3',.040,-.047,5)]:
  region=empty('DSKY_Readout_'+name,display,(x,y,.001))
  fields[name]={'path':'/DSKY_Mount/DSKY_Display_Mount/'+region.name,'positions':count,'sign':name.startswith('R')}
  if count==2:
   text('DSKY_Label_'+name,name,(x,y+.012,.0014),.004,legend,display)
   for n in range(2): digit(region,'DSKY_Digit_'+name+'_'+str(n),-.007+n*.014,0,.009,.013)
  else:
   for n in range(5): digit(region,'DSKY_Digit_'+name+'_'+str(n),-.021+n*.012,0,.008,.012)
   sign=empty('DSKY_Sign_'+name,region,(-.034,0,0))
   box('DSKY_Sign_'+name+'_Minus',(0,0,.00025),(.006,.001,.0003),phosphor,sign,.0001)
   box('DSKY_Sign_'+name+'_Plus',(0,0,.00025),(.001,.006,.0003),phosphor,sign,.0001)
  if name in ['R1','R2']:
   box('DSKY_RegisterRule_'+name,(.040,y-.009,.0014),(.079,.0005,.0002),legend,display,.00005)
 manifest_keys=[]
 for name,x,y in KEYS:
  pos=(x*I-W/2,y*I-H/2,.011)
  frame('DSKY_KeySocket_'+name,(pos[0],pos[1],.0068),.0200,.0176,.0011,.0017,black,face)
  key=empty('DSKY_Key_'+name,root,pos); key['travel_m']=.003; key['press_axis_blender']=[0,1,0]
  box('DSKY_Cap_'+name,(0,0,0),(.70*I,.62*I,.008),keys_mat,key,.0012)
  label={'PLUS':'+','MINUS':'−','KEY_REL':'KEY\nREL'}.get(name,name)
  text('DSKY_KeyLegend_'+name,label,(0,0,.0042),.009 if len(label)==1 else .0048,ink,key,.015)
  manifest_keys.append({'name':key.name,'path':'/DSKY_Mount/'+key.name,'legend':label,'neutral_usd_m':list(pos),
   'press_axis_usd':[0,0,-1],'travel_m':.003,'travel_evidence':'provisional app animation',
   'spring_return':True,'guard':None,'detents':None,'runtime_owner':'AGC','binding_status':'visual_only'})
 for i,(x,y) in enumerate([(-W/2+.010,H/2-.010),(W/2-.010,H/2-.010),(-W/2+.010,0),(W/2-.010,0),(-W/2+.010,-H/2+.010),(W/2-.010,-H/2+.010)]):
  screw('DSKY_FaceFastener_'+str(i),x,y,.0072,face)
 for i,(x,y) in enumerate([(-.080,.083),(.080,.083),(-.080,-.024),(.080,-.024)]):
  screw('DSKY_DisplayFastener_'+str(i),x,y,.012,face)
 for i,(x,y) in enumerate([(-.08,-.08),(.08,-.08),(-.08,.08),(.08,.08)]):
  # Rear screws face rear; cylinders are symmetric and recess detail is omitted there.
  cylinder('DSKY_RearFastener_'+str(i),(x,y,back+.0003),.003,.0006,steel,root)
 manifest={'baseline':root['source_baseline'],'units':'meters','usd_axes':'+X right +Y up +Z crew',
 'blender_to_usd':'(x,y,z) -> (x,z,-y)','face_m':[W,H,.012],'depth_budget_m':D,
 'display_mount_usd_m':[0,DISPLAY_Y,.010],'keys':manifest_keys,'lamps':lamp_specs,
 'computer_activity':{'path':'/DSKY_Mount/DSKY_Display_Mount/DSKY_Lamp_COMP_ACTY','snapshot':'compActy'},
 'fields':fields,'display_state':'unpowered, no static flight readout','textures':[]}
 (OUT/'bindings.json').write_text(json.dumps(manifest,indent=2)+'\n')
 # Asset-only export; review cameras are added only after export.
 bpy.ops.object.select_all(action='SELECT')
 settings=dict(selected_objects_only=True,export_animation=False,export_materials=True,
 generate_preview_surface=True,generate_materialx_network=False,convert_orientation=True,
 export_global_forward_selection='NEGATIVE_Z',export_global_up_selection='Y',
 root_prim_path='',merge_parent_xform=False,convert_scene_units='METERS',meters_per_unit=1,
 export_lights=False,export_cameras=False,convert_world_material=False,relative_paths=True,
 triangulate_meshes=True,export_custom_properties=True)
 bpy.ops.wm.usd_export(filepath=str(OUT/'DSKY.usda'),**settings)
 normalize_and_package(OUT/'DSKY.usda')
 (OUT/'export-settings.json').write_text(json.dumps(settings,indent=2)+'\n')
 # Lightweight workbench previews; no heavy render slot required.
 scene.render.engine='BLENDER_WORKBENCH'; scene.render.resolution_x=900; scene.render.resolution_y=900
 scene.render.resolution_percentage=100; scene.render.image_settings.file_format='PNG'
 scene.world.color=(.12,.12,.12); sh=scene.display.shading; sh.light='STUDIO'; sh.color_type='MATERIAL'
 sh.show_shadows=True; sh.show_cavity=True; sh.cavity_type='BOTH'; sh.show_specular_highlight=True
 sh.background_type='WORLD'; scene.view_settings.view_transform='Standard'
 cameras=[('front',(0,0,.7),(0,0,0),.25),('oblique',(.34,.23,.48),(0,0,-.04),.34),
 ('key-detail',(.09,-.10,.25),(0,-.057,.004),.17)]
 times={}
 for name,loc,target,scale in cameras:
  bpy.ops.object.camera_add(location=xyz(loc)); cam=bpy.context.object; cam.name='Review_'+name
  cam.rotation_euler=(Vector(xyz(target))-cam.location).to_track_quat('-Z','Y').to_euler()
  cam.data.type='ORTHO'; cam.data.ortho_scale=scale; cam.data.clip_start=.001; scene.camera=cam
  scene.render.filepath=str(OUT/'review'/(name+'.png')); start=time.monotonic(); bpy.ops.render.render(write_still=True)
  times[name]=time.monotonic()-start
 scene.camera=bpy.data.objects['Review_front']
 bpy.ops.object.select_all(action='DESELECT'); root.select_set(True); bpy.context.view_layer.objects.active=root
 for screen in bpy.data.screens:
  for area in screen.areas:
   if area.type=='VIEW_3D':
    area.spaces.active.region_3d.view_distance=.5; area.spaces.active.region_3d.view_location=(0,0,0)
 scene.render.filepath='//review/front.png'
 bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'DSKY.blend'))
 # A separate static lamp-test lookdev export, explicitly not live AGC state.
 original=[]
 for o in bpy.data.objects:
  if o.type!='MESH': continue
  mat=o.data.materials[0] if o.data.materials else None
  replacement=None
  if mat==phosphor: replacement=lit
  elif o.name.endswith('_Lens'):
   replacement=white_on if any(n in o.name for n in ['UPLINK_ACTY','NO_ATT','STBY','KEY_REL','OPR_ERR']) else amber_on
   if o.name=='DSKY_COMP_ACTY_Lens': replacement=lit
  if replacement: original.append((o,mat)); o.data.materials[0]=replacement
 root['binding_status']='STATIC_LAMP_TEST_PREVIEW_NOT_AGC'
 bpy.ops.object.select_all(action='DESELECT')
 for o in [root]+list(root.children_recursive): o.select_set(True)
 bpy.ops.wm.usd_export(filepath=str(OUT/'DSKY-LightingPreview.usda'),**settings)
 normalize_and_package(OUT/'DSKY-LightingPreview.usda')
 # Small Eevee preview evaluates actual emission/PBR; no bake or path tracing.
 scene.render.engine='BLENDER_EEVEE'
 scene.view_settings.view_transform='AgX'
 scene.render.resolution_x=720; scene.render.resolution_y=720
 scene.render.resolution_percentage=100
 scene.camera=bpy.data.objects['Review_front']
 for name,loc,power,size in [('Key',(-.2,.3,.45),2.0,.3),('Fill',(.25,0,.35),.8,.25)]:
  bpy.ops.object.light_add(type='AREA',location=xyz(loc)); light=bpy.context.object; light.name='ReviewLight_'+name
  light.data.energy=power; light.data.shape='DISK'; light.data.size=size
  light.rotation_euler=(-light.location).to_track_quat('-Z','Y').to_euler()
 scene.world.use_nodes=True; scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.025,.025,.025,1)
 scene.world.node_tree.nodes['Background'].inputs[1].default_value=.25
 scene.render.filepath=str(OUT/'review'/'lighting-preview.png'); start=time.monotonic()
 bpy.ops.render.render(write_still=True); times['lighting-preview']=time.monotonic()-start
 for o,m in original: o.data.materials[0]=m
 (OUT/'review'/'render-cost.json').write_text(json.dumps({'engine':'Workbench; lighting preview Eevee','resolution':{'front':[900,900],'oblique':[900,900],'key-detail':[900,900],'lighting-preview':[720,720]},
 'seconds':times,'peak_memory':'not measured','machine':'zacbookpro.local'},indent=2)+'\n')
if __name__=='__main__': build()
