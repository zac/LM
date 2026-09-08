"""Small Workbench geometry review; transient camera, source file stays neutral."""
import bpy,json,math,sys
from pathlib import Path
from mathutils import Vector
OUT=Path(__file__).resolve().parent
sys.path.insert(0,str(OUT));from build import q,v,pose
bpy.ops.wm.open_mainfile(filepath=str(OUT/'AltitudeRate.blend'))
c=json.loads((OUT/'interface.json').read_text());s=bpy.context.scene;s.render.engine='BLENDER_WORKBENCH';s.render.resolution_x=850;s.render.resolution_y=1050;s.render.resolution_percentage=100
s.display.shading.light='STUDIO';s.display.shading.color_type='MATERIAL';s.display.shading.show_shadows=True;s.display.shading.show_cavity=True;s.display.shading.background_type='WORLD';s.world.color=(.065,.07,.073)
# Workbench cannot assess transparent glazing, hide it solely for geometry views.
bpy.data.objects['Lens_Glass'].hide_render=True
cam=bpy.data.cameras.new('ReviewOnly');ob=bpy.data.objects.new('ReviewOnly',cam);s.collection.objects.link(ob);s.camera=ob;cam.type='ORTHO';cam.ortho_scale=.166;cam.clip_start=.001
ob.location=v((0,0,.5));ob.rotation_euler=(v((0,0,0))-ob.location).to_track_quat('-Z','Y').to_euler()
def show(alt,rate):
 for key,val in [('altitude',alt),('altitude_rate',rate)]:
  d=c[key];valid=val is not None and d['valid_range'][0]<=val<=d['valid_range'][1]
  for r in d['rows']:
   o=bpy.data.objects[r['name']];delta=q(r['value'],d)-q(val,d) if valid else 999
   enabled=abs(delta)<=.043
   o.matrix_local=pose((0,delta,0) if enabled else (0,0,-.010))
  bpy.data.objects[d['unavailable']].matrix_local=pose(d['unavailable_parked_position_m'] if valid else d['unavailable_active_position_m'])
for name,a,r in [('neutral',0,0),('landing-100ft-minus5fps',100,-5),('descent-5000ft-minus50fps',5000,-50),('positive-rate-1000ft-plus10fps',1000,10),('maximum-60000ft-minus700fps',60000,-700),('unavailable',None,None)]:
 show(a,r);s.render.filepath=str(OUT/'reviews'/(name+'.png'));bpy.ops.render.render(write_still=True)
# Provisional commander view: transform source model by accepted Panel1 and slot pose.
show(100,-5)
from mathutils import Matrix
bpy.data.objects['AltitudeRate'].matrix_world=pose((-.245,1.604410648,-.884985924),Matrix.Rotation(math.radians(-10),3,'X'))@pose((.125,-.045,.008))
root=bpy.data.objects['AltitudeRate'];center=root.matrix_world.translation
ob.location=v((-.5588,1.78,-.38));ob.rotation_euler=(center-ob.location).to_track_quat('-Z','Y').to_euler();cam.type='PERSP';cam.lens=75;s.render.filepath=str(OUT/'reviews'/'commander-eye-isolated.png');bpy.ops.render.render(write_still=True)
