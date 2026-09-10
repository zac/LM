"""Read-only append of existing assets for provisional Panel1 seated review, no peer edits."""
import bpy,json,sys,math
from pathlib import Path
from mathutils import Vector,Matrix
OUT=Path(__file__).resolve().parent;sys.path.insert(0,str(OUT));from build import pose,v,q,C
bpy.ops.wm.open_mainfile(filepath=str(OUT/'AltitudeRate.blend'))
contract=json.loads((OUT/'interface.json').read_text());inventory=json.loads((OUT.parent/'PanelInventory/inventory.json').read_text());panel=next(p for p in inventory['panels'] if p['id']=='Panel1');slot=next(x for x in panel['slots'] if x['id']=='Panel1__RangeThrust')
P=pose(panel['pose']['translation_m'],Matrix.Rotation(math.radians(-10),3,'X'))
mount=P@pose((.125,-.045,.008));bpy.data.objects['AltitudeRate'].matrix_world=mount
for key,value in [('altitude',100),('altitude_rate',-5)]:
 d=contract[key]
 for row in d['rows']:
  delta=q(row['value'],d)-q(value,d);bpy.data.objects[row['name']].matrix_local=pose((0,delta,0) if abs(delta)<=.043 else (0,0,-.010))
bpy.data.objects['Lens_Glass'].hide_render=True
added={}
for component in ['PanelInventory','CommanderPanels','FDAI']:
 with bpy.data.libraries.load(str(OUT.parent/component/(component+'.blend')),link=False) as (a,b):b.objects=a.objects
 for o in b.objects:
  if o:o.hide_render=False;bpy.context.scene.collection.objects.link(o)
 added[component]=[o for o in b.objects if o]
bpy.data.objects['PanelInventory'].matrix_world=C
if 'FDAI_Mount' not in bpy.data.objects:raise ValueError('FDAI root not found')
bpy.data.objects['FDAI_Mount'].matrix_world=P@pose((-.055,-.015,.016))@C
# Scope view to current Panel1 and its two real instruments; retained RangeThrust blank stays.
for o in added['PanelInventory']:
 p=o;names=[]
 while p:names.append(p.name);p=p.parent
 o.hide_render=('Panel1' not in names) or ('PlanningLabels' in names) or ('Panel1__FDAI' in names)
for o in added['CommanderPanels']:
 p=o;names=[]
 while p:names.append(p.name);p=p.parent
 o.hide_render='Panel_1' not in names
for o in added['FDAI']:
 if 'Glass' in o.name or 'glass' in o.name:o.hide_render=True
s=bpy.context.scene;s.render.engine='BLENDER_WORKBENCH';s.render.resolution_x=1100;s.render.resolution_y=1000;s.render.resolution_percentage=100;s.display.shading.light='STUDIO';s.display.shading.color_type='MATERIAL';s.display.shading.show_shadows=True;s.display.shading.show_cavity=True;s.display.shading.background_type='WORLD';s.world.color=(.065,.07,.073)
camera=bpy.data.cameras.new('FitReviewOnly');ob=bpy.data.objects.new('FitReviewOnly',camera);s.collection.objects.link(ob);s.camera=ob;camera.clip_start=.001
center=P@Vector((0,0,0,1));target=Vector(center[:3])
ob.location=(P@C@Vector((0,0,1,1))).to_3d();ob.rotation_euler=(target-ob.location).to_track_quat('-Z','Y').to_euler();camera.type='ORTHO';camera.ortho_scale=.6;s.render.filepath=str(OUT/'reviews'/'panel1-front-fit.png');bpy.ops.render.render(write_still=True)
ob.location=v((-.5588,1.78,-.38));ob.rotation_euler=(target-ob.location).to_track_quat('-Z','Y').to_euler();camera.type='PERSP';camera.lens=22;s.render.filepath=str(OUT/'reviews'/'panel1-crew-fit.png');bpy.ops.render.render(write_still=True)
