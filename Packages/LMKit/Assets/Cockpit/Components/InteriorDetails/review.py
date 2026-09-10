"""Small Workbench geometry previews, no source save or heavy bake."""
import bpy,json,math
from pathlib import Path
from mathutils import Vector,Matrix
D=Path(__file__).resolve().parent;R=D.parents[3];C=Matrix.Rotation(math.pi/2,4,'X')
bpy.ops.wm.open_mainfile(filepath=str(D/'InteriorDetails.blend'))
scene=bpy.context.scene;scene.render.engine='BLENDER_WORKBENCH';scene.render.resolution_x=1100;scene.render.resolution_y=850;scene.render.resolution_percentage=100
scene.display.shading.light='STUDIO';scene.display.shading.color_type='MATERIAL';scene.display.shading.show_shadows=True;scene.display.shading.show_cavity=True;scene.display.shading.cavity_type='BOTH';scene.world=bpy.data.worlds.new('ReviewWorld');scene.world.color=(.14,.14,.14)
camdata=bpy.data.cameras.new('ReviewCamera');cam=bpy.data.objects.new('ReviewCamera',camdata);scene.collection.objects.link(cam);scene.camera=cam;camdata.clip_start=.005;camdata.lens=30
records=[]
def V(p):return Vector((p[0],-p[2],p[1]))
def render(name,eye,target,lens=30):
 cam.location=V(eye);cam.rotation_euler=(V(target)-cam.location).to_track_quat('-Z','Y').to_euler();camdata.lens=lens;scene.render.filepath=str(D/'review'/(name+'.png'));bpy.ops.render.render(write_still=True);records.append({'name':name,'eye_cabin_m':eye,'target_cabin_m':target,'lens_mm':lens})
render('standalone-CDR',(-.32,.53,.36),(-1.15,.38,.3),32)
for name in ['Cabin','PanelInventory','WindowsLPD','CommanderPanels']:
 bpy.ops.wm.usd_import(filepath=str(R/'Assets/Cockpit/Components'/name/(name+'.usdz')))
for o in bpy.data.objects:
 if 'Glazing' in o.name or o.name.startswith(('Panel_1_Backing_','Panel_4_Backing_')):o.hide_render=True
 p=o
 while p:
  if 'PlanningLabels' in p.name:o.hide_render=True
  p=p.parent
render('combined-CDR-lower',(-.18,1.32,.32),(-1.14,.35,.22),23)
render('combined-LMP-lower',(.18,1.32,.32),(1.14,.35,.22),23)
render('combined-CDR-upper',(-.48,1.73,.16),(-.83,1.92,-.10),26)
render('combined-CDR-forward',(-.5588,1.65,.20),(-.38,1.4,-.9),18)
render('combined-CDR-close',(-.70,.68,.57),(-1.15,.29,.24),30)
render('phase2-forward-overhead',(-.42,1.70,.04),(0,2.17,-.72),23)
render('phase2-transfer-hatch',(0,1.60,.15),(0,2.18,.65),24)
render('phase2-forward-hatch',(-.35,1.20,.15),(0,.55,-1.0),35)
render('phase2-aft-crown',(-.32,1.74,.15),(-.68,2.03,.67),27)
(D/'review/cameras.json').write_text(json.dumps({'views':records,'method':'small Workbench; glazing omitted; no source save; geometry-only'},indent=2)+'\n')
