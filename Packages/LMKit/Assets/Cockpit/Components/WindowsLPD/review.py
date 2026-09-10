"""Small Workbench geometry reviews. Cameras exist only in memory, never exported.
Glass hidden for these geometry/visibility reviews: does not certify transparency/reflections.
"""
import bpy,json,sys
from pathlib import Path
from mathutils import Vector
OUT=Path(__file__).resolve().parent
bpy.ops.wm.open_mainfile(filepath=str(OUT/'WindowsLPD.blend'))
def v(p):return Vector((p[0],-p[2],p[1]))
scene=bpy.context.scene;scene.render.engine='BLENDER_WORKBENCH';scene.render.resolution_x=1000;scene.render.resolution_y=800;scene.render.resolution_percentage=100
scene.display.shading.light='STUDIO';scene.display.shading.color_type='MATERIAL';scene.display.shading.show_shadows=True;scene.display.shading.show_cavity=True;scene.display.shading.background_type='WORLD';scene.world.color=(.035,.04,.045)
for o in bpy.data.objects:
 if 'Glazing' in o.name:o.hide_render=True
camera=bpy.data.cameras.new('ReviewOnly');obj=bpy.data.objects.new('ReviewOnly',camera);scene.collection.objects.link(obj);scene.camera=obj
c=json.loads((OUT/'interface-v1.json').read_text());row=c['forward']['CDR_Window_Inner'];pts=[Vector(p) for p in row['corners']];center=sum(pts,Vector())/3;n=Vector(row['normal'])
views={'front':((0,1.65,1.9),(0,1.7,-.65),True,2.5),'side':((-2,1.7,-.1),(0,1.7,-.55),True,2.4),'commander-eye':(c['eyes']['CDR'],list(center),False,1),'pilot-eye':(c['eyes']['LMP'],[-center.x,center.y,center.z],False,1),'rear':((0,1.7,-2.5),(0,1.7,-.4),True,2.5),'overhead':((0,4,-.4),(0,1.7,-.4),True,2.5),'cdr-closeup':(list(center+n*.85),list(center),True,.82)}
for name,(pos,target,ortho,scale) in views.items():
 if "--placement-only" in sys.argv and name not in ["commander-eye","cdr-closeup"]:continue
 for o in bpy.data.objects:
  if o.type=='MESH':o.hide_render=('Glazing' in o.name) or (name=='cdr-closeup' and not o.name.startswith(('CDR_','Inner_','Outer_')))
 obj.location=v(pos);obj.rotation_euler=(v(target)-obj.location).to_track_quat('-Z','Y').to_euler();camera.type='ORTHO' if ortho else 'PERSP';camera.ortho_scale=scale;camera.lens=10;camera.clip_start=.005
 scene.render.filepath=str(OUT/'reviews'/f'{name}.png');bpy.ops.render.render(write_still=True)
