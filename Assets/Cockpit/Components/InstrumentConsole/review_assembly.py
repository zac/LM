"""Low-cost assembled review at accepted transforms; no peer writes or scripts."""
from pathlib import Path
import bpy,json,math,hashlib
from mathutils import Matrix,Vector,Quaternion
O=Path(__file__).resolve().parent;D=O.parent;C=Matrix.Rotation(math.pi/2,4,'X');I=Matrix.Identity(4)
bpy.ops.wm.read_factory_settings(use_empty=True)
contract=json.loads((O/'interface.json').read_text());inv=json.loads((O/'evidence/accepted-inventory.json').read_text())
def pose(p):
 x,y,z,w=p.get('quaternion_xyzw',[0,0,0,1]);return Matrix.Translation(Vector(p.get('translation_m',[0,0,0])))@Quaternion((w,x,y,z)).to_matrix().to_4x4()
def panel(pid):return pose(next(p['pose'] for p in inv['panels'] if p['id']==pid))
def slot(sid):
 for p in inv['panels']:
  for s in p['slots']:
   if s['id']==sid:return pose(p['pose'])@pose(s['pose'])
 raise KeyError(sid)
configs=[]
def add(name,component,filename=None,matrix=I):configs.append((name,D/component/(filename or component+'.usdz'),matrix))
for n in ['Cabin','WindowsLPD','CommanderPanels','PanelInventory','InteriorDetails','BreakerBanks','CautionWarning','InstrumentConsole']:add(n,n)
add('CDR_FDAI','FDAI',matrix=slot('Panel1__FDAI'));add('LMP_FDAI','FDAI',matrix=slot('Panel2__FDAI'));add('DSKY','DSKY',matrix=slot('Panel4__DSKY'))
a=json.loads((D/'AltitudeRate/interface.json').read_text());add('AltitudeRate','AltitudeRate',matrix=slot(a['slot'])@pose(a['slot_local_pose']))
add('CrossPointer','CrossPointer',matrix=slot('Panel1__CrossPointer'))
a=json.loads((D/'PropulsionInstruments/interface.json').read_text())['mounting'];add('PropulsionInstruments','PropulsionInstruments',matrix=slot(a['slot'])@Matrix.Translation(Vector(a['slot_local_translation_m'])))
for a in json.loads((D/'DescentControls/interface.json').read_text())['components']:add(a['id'],'DescentControls',a['asset'],slot(a['slot']))
for a in json.loads((D/'Timers/interface.json').read_text())['assets']:
 if a.get('panel_slot'):add(a['root'],'Timers',a['filename'],slot(a['panel_slot'])@pose(a['slot_local_pose']))
em=json.loads((D/'EngineControls/mounting-matrices.json').read_text());add('EngineButtons','EngineControls','EngineButtons.usdz',Matrix(em['EngineButtons']))
for a in em['LunarContact']:add(a['id'],'EngineControls','LunarContact.usdz',Matrix(a['Cabin_matrix_rows']))
add('ACA','HandControllers','ACA.usdz',Matrix.Translation(Vector((-.49,.9075,-.37))))
fullslots={'Panel1__FDAI','Panel2__FDAI','Panel4__DSKY','Panel1__CrossPointer','Panel3__Stability','Panel5__Engine','Panel1__Warning','Panel2__Caution'}
fullslots.update(s['id'] for s in json.loads((D/'BreakerBanks/interface.json').read_text())['slots'])
inputs=[];meshes=[];suppressed=[];roots=[]
for name,f,transform in configs:
 before=set(bpy.data.objects);bpy.ops.wm.usd_import(filepath=str(f));new=set(bpy.data.objects)-before
 for ob in new:
  if ob.parent not in new:ob.matrix_world=transform@C.inverted()@ob.matrix_world;roots.append(ob)
 paths={}
 for ob in new:
  chain=[];a=ob
  while a in new:chain.append(a.name.split('.')[0]);a=a.parent
  paths[ob]='/'+'/'.join(reversed(chain))
 for ob in new:
  path=paths[ob];hide='PlanningLabels' in path
  if name=='CommanderPanels' and '/Panel_4_RemovableBacking/' in path:hide=True
  if name=='PanelInventory' and '/Placeholder' in path and any('/'+s+'/' in path for s in fullslots):hide=True
  if any(s['component']==name and (path==s['path'] or path.startswith(s['path']+'/')) for s in contract['suppressions']):hide=True
  if ob.type=='MESH':
   ob['source_component']=name;ob['source_path']=path;ob.hide_render=hide or any(t in path for t in ['FDAI_Glass','FaceGlass','Glazing']);ob.hide_viewport=hide
   if hide:suppressed.append({'component':name,'path':path})
   else:meshes.append(ob)
  ob.name='Review_'+name+'__'+ob.name
 inputs.append({'component':name,'file':str(f.relative_to(D)),'sha256':hashlib.sha256(f.read_bytes()).hexdigest(),'Cabin_matrix':list(map(list,transform))})
bpy.context.view_layer.update()
# Native USD imports retain textures; Workbench is a shape/occlusion preview, not calibrated lighting.
scene=bpy.context.scene;scene.world=bpy.data.worlds.new('ReviewWorld');scene.render.engine='BLENDER_WORKBENCH';scene.render.resolution_x=1400;scene.render.resolution_y=1100;scene.render.resolution_percentage=100;scene.display.shading.light='STUDIO';scene.display.shading.color_type='MATERIAL';scene.display.shading.show_shadows=False;scene.display.shading.show_cavity=True;scene.world.color=(.04,.045,.045)
d=bpy.data.cameras.new('ReviewCamera');cam=bpy.data.objects.new('ReviewCamera',d);bpy.context.collection.objects.link(cam);scene.camera=cam;d.lens=35;d.clip_start=.005;d.clip_end=20
views=[('crew-eye',(-.5588,1.78,-.38),(-.05,1.53,-.875)),('pilot-eye',(.5588,1.78,-.38),(.05,1.53,-.875)),('central-oblique',(-.22,1.84,-.21),(0,1.55,-.88))]
for name,eye,target in views:
 cam.location=eye;forward=(Vector(target)-Vector(eye)).normalized();right=forward.cross(Vector((0,1,0))).normalized();up=right.cross(forward);cam.rotation_euler=Matrix((right,up,-forward)).transposed().to_euler();d.lens=28 if 'eye' in name else 35;scene.render.filepath=str(O/'review'/f'{name}.png');bpy.ops.render.render(write_still=True)
(O/'review/assembly-inputs.json').write_text(json.dumps({'inputs':inputs,'suppressions':suppressed,'views':[{'name':n,'eye':e,'target':t} for n,e,t in views],'limits':'Workbench mesh/material geometry only; all source assets neutral. FDAI_Glass, FaceGlass and Glazing hidden in render only because Workbench treats transparent surfaces as opaque. No live or headset verification.'},indent=2)+'\n')
# Persist a disposable review scene outside deliverable binary path for independent visibility validation.
bpy.ops.wm.save_as_mainfile(filepath='/private/tmp/instrument-console-review.blend')
print('ASSEMBLY REVIEW',len(meshes),'visible meshes')
