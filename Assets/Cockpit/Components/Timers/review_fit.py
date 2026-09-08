"""Provisional mounting reviews against pinned inventory and structural panel assets."""
import bpy,json,sys,math
from pathlib import Path
from mathutils import Matrix,Quaternion,Vector
P=Path(__file__).resolve().parent;sys.path.insert(0,str(P));from build import C,pose,v
c=json.loads((P/'interface.json').read_text());inv=json.loads((P.parent/'PanelInventory/inventory.json').read_text())
for panelid in ['Panel1','Panel3']:
 bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
 panel=next(p for p in inv['panels'] if p['id']==panelid);qx,qy,qz,qw=panel['pose']['quaternion_xyzw'];pm=pose(panel['pose']['translation_m'],Quaternion((qw,qx,qy,qz)).to_matrix())
 for component in ['PanelInventory','CommanderPanels']:
  with bpy.data.libraries.load(str(P.parent/component/(component+'.blend')),link=False) as (a,b):b.objects=a.objects
  for o in b.objects:
   if not o:continue
   bpy.context.scene.collection.objects.link(o);parents=[];p=o
   while p:parents.append(p.name);p=p.parent
   o.hide_render=(panelid not in parents or 'PlanningLabels' in parents) if component=='PanelInventory' else ('Panel_'+panelid[-1] not in parents)
 bpy.data.objects['PanelInventory'].matrix_world=C
 for a in c['assets']:
  if not a.get('panel_slot','') or not a['panel_slot'].startswith(panelid+'__'):continue
  with bpy.data.libraries.load(str(P/(a['root']+'.blend')),link=False) as (src,dst):dst.objects=src.objects
  for o in dst.objects:
   if o:bpy.context.scene.collection.objects.link(o);o.hide_render='Lens' in o.name
  slot=next(s for s in panel['slots'] if s['id']==a['panel_slot']);offset=[x+y for x,y in zip(slot['pose']['translation_m'],a['slot_local_pose']['translation_m'])];bpy.data.objects[a['root']].matrix_world=pm@pose(offset)
 s=bpy.context.scene;s.render.engine='BLENDER_WORKBENCH';s.render.resolution_x=1400;s.render.resolution_y=850;s.render.resolution_percentage=100;s.display.shading.light='STUDIO';s.display.shading.color_type='MATERIAL';s.display.shading.show_shadows=True;s.display.shading.show_cavity=True;s.display.shading.background_type='WORLD';s.world.color=(.065,.07,.073)
 cam=bpy.data.cameras.new('ReviewOnly');ob=bpy.data.objects.new('ReviewOnly',cam);s.collection.objects.link(ob);s.camera=ob;cam.type='ORTHO';cam.ortho_scale=.9 if panelid=='Panel1' else 1.05;cam.clip_start=.001;target=pm.translation;ob.location=(pm@C@Vector((0,0,1,1))).to_3d();ob.rotation_euler=(target-ob.location).to_track_quat('-Z','Y').to_euler();s.render.filepath=str(P/'reviews'/(panelid+'-fit.png'));bpy.ops.render.render(write_still=True)
