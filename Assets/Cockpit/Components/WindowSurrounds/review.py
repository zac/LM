"""Low-cost transient crew-eye Workbench assembly previews; source stays neutral."""
import bpy,json,sys
from pathlib import Path
from mathutils import Vector
P=Path(__file__).resolve().parent;sys.path.insert(0,str(P));from build import C,v
bpy.ops.wm.open_mainfile(filepath=str(P/'WindowSurrounds.blend'));c=json.loads((P/'interface.json').read_text());suppressed={x['path'].split('/')[-1] for x in c['suppressions']}
for component in ['Cabin','WindowsLPD','CommanderPanels','PanelInventory','BreakerBanks']:
 with bpy.data.libraries.load(str(P.parent/component/(component+'.blend')),link=False) as (a,b):b.objects=a.objects
 for o in b.objects:
  if not o:continue
  bpy.context.scene.collection.objects.link(o);o.hide_render=o.name in suppressed or ('Glazing' in o.name) or o.type in ['LIGHT','CAMERA']
  if component=='PanelInventory':
   parent=o;names=[]
   while parent:names.append(parent.name);parent=parent.parent
   o.hide_render=o.hide_render or 'PlanningLabels' in names
 if component in ['PanelInventory','BreakerBanks']:bpy.data.objects[component].matrix_world=C
s=bpy.context.scene;s.render.engine='BLENDER_WORKBENCH';s.render.resolution_x=1300;s.render.resolution_y=950;s.render.resolution_percentage=100;s.display.shading.light='STUDIO';s.display.shading.color_type='MATERIAL';s.display.shading.show_shadows=True;s.display.shading.show_cavity=True;s.display.shading.background_type='WORLD';s.world.color=(.08,.09,.09)
cam=bpy.data.cameras.new('ReviewOnly');ob=bpy.data.objects.new('ReviewOnly',cam);s.collection.objects.link(ob);s.camera=ob;cam.type='PERSP';cam.clip_start=.001;cam.lens=22
for name,eye,target,lens in [('cabin-center',(0,1.75,.6),(0,1.55,-.7),22),('commander-eye',(-.5588,1.78,-.38),(-.58,1.61,-.8),16),('pilot-eye',(.5588,1.78,-.38),(.58,1.61,-.8),16),('commander-window-close',(-.5588,1.78,-.25),(-.65,1.63,-.66),22)]:
 ob.location=v(eye);ob.rotation_euler=(v(target)-ob.location).to_track_quat('-Z','Y').to_euler();cam.lens=lens;s.render.filepath=str(P/'reviews'/(name+'.png'));bpy.ops.render.render(write_still=True)
