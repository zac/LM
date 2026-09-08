"""Lightweight inspection only; production geometry is never saved or changed."""
import bpy
from pathlib import Path
from mathutils import Vector,Matrix
D=Path(__file__).resolve().parent
bpy.ops.wm.open_mainfile(filepath=str(D/'BreakerBanks.blend'))
sc=bpy.context.scene;cam=sc.camera;sc.view_settings.view_transform='Standard';sc.view_settings.exposure=.4
for name,pos,look,scale in [('commander',(-.15,1.8,-.02),(-.90,1.5,-.10),.9),('pilot',(.13,1.83,-.02),(.90,1.52,-.10),.9),('profile',(-.3,1.73,.52),(-.89,1.5,-.10),.9),('legend-detail',(-.30,1.72,-.11),(-.90,1.52,-.11),.38)]:
 cam.location=pos;forward=(Vector(look)-cam.location).normalized();right=forward.cross(Vector((0,1,0))).normalized();up=right.cross(forward);cam.rotation_euler=Matrix((right,up,-forward)).transposed().to_euler();cam.data.ortho_scale=scale;sc.render.filepath=str(D/'review'/f'{name}.png');bpy.ops.render.render(write_still=True)
