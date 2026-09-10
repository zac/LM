"""Read-only assembly review: blender -b --python review_combined.py -- /path/to/WindowsLPD.usdz
Never saves imported Windows geometry into Cabin source or production USD.
"""
import bpy,sys,json,hashlib
from pathlib import Path
OUT=Path(__file__).resolve().parent
bpy.ops.wm.open_mainfile(filepath=str(OUT/'Cabin.blend'))
path=Path(sys.argv[sys.argv.index('--')+1]);bpy.ops.wm.usd_import(filepath=str(path),import_materials=True)
# Workbench cannot render transparent panes: hide only glazing for aperture/retainer inspection.
hidden=[]
for o in bpy.data.objects:
 if o.type=='MESH' and any('pane' in m.name.lower() or 'glass' in m.name.lower() for m in o.data.materials if m):o.hide_render=True;hidden.append(o.name)
scene=bpy.context.scene
from mathutils import Vector
c=bpy.data.cameras.new('docking-review');o=bpy.data.objects.new('docking-review',c);bpy.context.collection.objects.link(o)
def v(p):return Vector((p[0],-p[2],p[1]))
o.location=v((-.5588,1.78,-.38));o.rotation_euler=(v((-.5588,2.1261097,-.2))-o.location).to_track_quat('-Z','Y').to_euler();c.lens=18;c.clip_start=.01
for name in ['crew-eye','lmp-eye','overhead','side-interior','docking-review']:
 scene.camera=bpy.data.objects[name];scene.render.filepath=str(OUT/'reviews'/('combined-'+name+'.png'));bpy.ops.render.render(write_still=True)
(OUT/'combined-review.json').write_text(json.dumps({'windows_commit':'5699e64','windows_usdz_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'cabin_usdz_sha256':hashlib.sha256((OUT/'Cabin.usdz').read_bytes()).hexdigest(),'method':'Blender USD import at identity, lightweight Workbench, glazing hidden because Workbench is opaque','hidden_glazing':hidden,'qualification':'visual frame-miter and shell-edge inspection; no production assembly modifications or optical acceptance'},indent=2)+'\n')
