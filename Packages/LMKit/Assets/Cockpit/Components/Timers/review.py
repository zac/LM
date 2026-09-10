"""Transient low-cost Workbench previews. Reference numeric values are not mission time."""
import bpy,json,sys
from pathlib import Path
P=Path(__file__).resolve().parent;sys.path.insert(0,str(P));from build import v
c=json.loads((P/'interface.json').read_text());(P/'reviews').mkdir(exist_ok=True)
for a in c['assets']:
 bpy.ops.wm.open_mainfile(filepath=str(P/(a['root']+'.blend')))
 if a['kind']=='readout':
  for obj in bpy.data.objects:
   if 'Lens' in obj.name:obj.hide_render=True
  on=bpy.data.materials.new('ReviewOnly_EL_On');on.diffuse_color=(.63,.82,.60,1)
  sample='1005049' if a['root']=='MissionTimer' else '0215'
  for d,num in zip(a['digits'],sample):
   for seg,name in d['segments'].items():
    if seg in c['digit_masks'][num]:bpy.data.objects[name].data.materials[0]=on
 s=bpy.context.scene;s.render.engine='BLENDER_WORKBENCH';s.render.resolution_x=1400;s.render.resolution_y=450 if a['kind']=='readout' else 700;s.render.resolution_percentage=100;s.display.shading.light='STUDIO';s.display.shading.color_type='MATERIAL';s.display.shading.show_shadows=True;s.display.shading.show_cavity=True;s.display.shading.background_type='WORLD';s.world.color=(.065,.07,.073)
 camera=bpy.data.cameras.new('ReviewOnly');ob=bpy.data.objects.new('ReviewOnly',camera);s.collection.objects.link(ob);s.camera=ob;camera.type='ORTHO';camera.ortho_scale=a['size_m'][0]*1.12;camera.clip_start=.001
 ob.location=v((0,0,.5));ob.rotation_euler=(v((0,0,0))-ob.location).to_track_quat('-Z','Y').to_euler();s.render.filepath=str(P/'reviews'/(a['root']+'-front.png'));bpy.ops.render.render(write_still=True)
 if a['kind']!='readout':
  ob.location=v((.07,.06,.35));ob.rotation_euler=(v((0,0,0))-ob.location).to_track_quat('-Z','Y').to_euler();s.render.filepath=str(P/'reviews'/(a['root']+'-oblique.png'));bpy.ops.render.render(write_still=True)
