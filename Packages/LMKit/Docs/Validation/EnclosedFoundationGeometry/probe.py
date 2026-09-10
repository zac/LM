import bpy,json,hashlib,math
from pathlib import Path
from mathutils import Vector,Matrix,Quaternion
R=Path('/Users/zac/Projects/personal/lm/LMKit');O=Path('/tmp/lmkit-combined-review');C=Matrix.Rotation(math.pi/2,4,'X')
bpy.ops.wm.read_factory_settings(use_empty=True)
inventory=json.loads((R/'Assets/Cockpit/Components/PanelInventory/inventory.json').read_text())
def matrix(p):
 x,y,z,w=p['quaternion_xyzw'];return Matrix.Translation(Vector(p['translation_m']))@Quaternion((w,x,y,z)).to_matrix().to_4x4()
def slotmatrix(sid):
 for p in inventory['panels']:
  for s in p['slots']:
   if s['id']==sid:return matrix(p['pose'])@matrix(s['pose'])
inputs={};groups={}
for folder,name,pose in [('Cabin','Cabin',Matrix.Identity(4)),('WindowsLPD','WindowsLPD',Matrix.Identity(4)),('PanelInventory','PanelInventory',Matrix.Identity(4)),('CommanderPanels','CommanderPanels',Matrix.Identity(4)),('DSKY','DSKY',slotmatrix('Panel4__DSKY')),('FDAI','FDAI',slotmatrix('Panel1__FDAI')),('HandControllers','ACA',Matrix.Translation(Vector((-.49,.9075,-.37))))]:
 p=R/'Assets/Cockpit/Components'/folder/(name+'.usdz');inputs[name]={'path':str(p),'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'pose_y_up':list(map(list,pose))};before=set(bpy.data.objects);bpy.ops.wm.usd_import(filepath=str(p));new=set(bpy.data.objects)-before;groups[name]=list(new)
 for ob in new:
  if ob.parent not in new:ob.matrix_world=C@pose@C.inverted()@ob.matrix_world
hidden=[]
def hide(ob,reason):
 ob.hide_render=True;hidden.append({'object':ob.name,'reason':reason})
def ancestry(ob):
 a=[]
 while ob:a.append(ob.name.split('.')[0]);ob=ob.parent
 return a
for ob in bpy.data.objects:
 a=ancestry(ob)
 if any('PlanningLabels' in n for n in a):hide(ob,'planning labels explicitly disabled')
 if any(n in ['Panel1__FDAI','Panel4__DSKY'] for n in a) and any(n.startswith('Placeholder') for n in a):hide(ob,'installed instrument blank disabled')
 if ob.type=='MESH' and ('Glazing' in ob.name or ob.name == 'FDAI_Glass'):hide(ob,'Workbench glazing hidden; no transparency qualification')
scene=bpy.context.scene;scene.render.engine='BLENDER_WORKBENCH';scene.render.resolution_x=1000;scene.render.resolution_y=800;scene.render.resolution_percentage=100
scene.display.shading.light='STUDIO';scene.display.shading.color_type='MATERIAL';scene.display.shading.show_shadows=True;scene.display.shading.show_cavity=True;scene.display.shading.cavity_type='BOTH';scene.world=bpy.data.worlds.new('ReviewWorld');scene.world.color=(.12,.12,.12)
camdata=bpy.data.cameras.new('ReviewCamera');cam=bpy.data.objects.new('ReviewCamera',camdata);scene.collection.objects.link(cam);scene.camera=cam;camdata.clip_start=.008;camdata.clip_end=100
base={o:o.hide_render for o in bpy.data.objects};views=[]
def v(t):return Vector((t[0],-t[2],t[1]))
def render(name,pos,target,lens=22,cut=None):
 for ob,val in base.items():ob.hide_render=val
 removed=[]
 if cut:
  for ob in bpy.data.objects:
   if ob.type!='MESH':continue
   corners=[C.inverted()@(ob.matrix_world@Vector(c)) for c in ob.bound_box];center=sum(corners,Vector())/8
   if cut(center,ob):ob.hide_render=True;removed.append(ob.name)
 cam.location=v(pos);cam.rotation_euler=(v(target)-cam.location).to_track_quat('-Z','Y').to_euler();camdata.lens=lens;scene.render.filepath=str(O/(name+'.png'));bpy.ops.render.render(write_still=True);views.append({'name':name,'eye_y_up':pos,'target_y_up':target,'lens_mm':lens,'cutaway_removed':removed})
# Aperture center probes are geometry diagnostics, not optical qualification.
bpy.context.view_layer.update()
rays=[]
for label,eye,glazing in [('cdr',(-.5588,1.65,.20),'CDR_Glazing_Inner'),('lmp',(.5588,1.65,.20),'LMP_Glazing_Inner'),('docking',(-.5588,1.78,-.38),'Docking_Glazing_Inner')]:
 ob=bpy.data.objects.get(glazing)
 if not ob:continue
 target=sum((ob.matrix_world@v.co for v in ob.data.vertices),Vector())/len(ob.data.vertices)
 start=v(eye);direction=(target-start).normalized();total=0;hits=[]
 for _ in range(40):
  found,loc,normal,idx,hit,mat=scene.ray_cast(bpy.context.evaluated_depsgraph_get(),start,direction,distance=5-total)
  if not found:break
  dist=(loc-start).length;total+=dist
  hits.append({'object':hit.name,'distance_m':total,'hidden':hit.hide_render})
  if not hit.hide_render:break
  start=loc+direction*.0001;total+=.0001
 rays.append({'label':label,'hits':hits})
(O/'aperture-probes.json').write_text(json.dumps(rays,indent=2))
