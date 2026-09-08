"""Small static orientation reviews; never saves state into integration assets."""
import bpy,math,json,time
from pathlib import Path
from mathutils import Vector
P=Path(__file__).resolve().parent
bpy.ops.wm.open_mainfile(filepath=str(P/'FDAI.blend'))
s=bpy.context.scene;s.render.engine='BLENDER_EEVEE';s.render.resolution_x=s.render.resolution_y=600
cam=s.camera;cam.location=(0,0,.5);cam.rotation_euler=(Vector((0,0,0))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=.172
p=bpy.data.objects['FDAI_Ball_Pivot'];times={}
for name,axis,angle in [('pitch-30',0,30),('yaw-plus-90',1,90),('yaw-minus-90',1,-90),('roll-30',2,30)]:
 p.rotation_euler=(0,0,0);p.rotation_euler[axis]=math.radians(angle)
 bpy.data.objects['FDAI_RollBug_Pivot'].rotation_euler.z=math.radians(angle if axis==2 else 0)
 s.render.filepath=str(P/'review'/f'{name}.png');t=time.perf_counter();bpy.ops.render.render(write_still=True);times[name]=time.perf_counter()-t
(P/'review/orientation-cost.json').write_text(json.dumps(times,indent=2)+'\n')
