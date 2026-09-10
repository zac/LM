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
render('front-closed',(0,1.5,-3.8),(0,1.25,0),35)
render('cdr-closed',(-.5588,1.65,.20),(-.38,1.4,-.9),18)
render('lmp-closed',(.5588,1.65,.20),(.30,1.4,-.9),18)
render('rear-interior-closed',(0,1.65,-.55),(0,1.1,1.1),18)
render('overhead-closed',(0,4.8,0),(0,.9,0),35)
render('overhead-cutaway',(0,4.8,0),(0,.9,0),35,lambda c,o:c.y>1.85)
render('side-cutaway',(-3.5,1.8,.15),(0,1.15,0),30,lambda c,o:c.x<-.75)
render('front-interior-cutaway',(0,1.65,2.8),(0,1.25,-.8),26,lambda c,o:c.z>.55)
(O/'manifest.json').write_text(json.dumps({'inputs':inputs,'hidden':hidden,'views':views,'method':'USDZ import at preserved units/up-axis; mounted instruments using pinned PanelInventory poses consistent with LM11f7335; Workbench; glazing omitted in all views; explicit centroid cutaways only','limitations':'No source mutation, exact-fit claim, optical/glass validation, swept clearance, interaction or app acceptance'},indent=2))
