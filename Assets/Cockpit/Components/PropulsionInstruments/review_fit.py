"""Read-only peer USD context; own review output only. No peer build execution."""
from pathlib import Path
import bpy,json
from mathutils import Vector
from pxr import Usd,UsdGeom,Gf
OUT=Path(__file__).resolve().parent;COMP=OUT.parent
bpy.ops.wm.open_mainfile(filepath=str(OUT/'PropulsionInstruments.blend'))
root=bpy.data.objects['PropulsionInstruments'];root.location=(.177,.105,.008)
def mat(name,color):
 m=bpy.data.materials.new(name);m.diffuse_color=(*color,1);return m
context=mat('ReviewSurround',(.19,.24,.23));reference=mat('ReviewAltitudeReference',(.20,.37,.42));blankmat=mat('ReviewBlank',(.10,.13,.13))
def import_meshes(path,offset,material,prefix=None,local_frame=None):
 stage=Usd.Stage.Open(str(path));cache=UsdGeom.XformCache();count=0
 inv=cache.GetLocalToWorldTransform(stage.GetPrimAtPath(local_frame)).GetInverse() if local_frame else Gf.Matrix4d(1)
 for p in stage.Traverse():
  if not p.IsA(UsdGeom.Mesh) or (prefix and not str(p.GetPath()).startswith(prefix)):continue
  g=UsdGeom.Mesh(p);xf=cache.GetLocalToWorldTransform(p)*inv;verts=[tuple(xf.Transform(Gf.Vec3d(*v))+Gf.Vec3d(*offset)) for v in g.GetPointsAttr().Get()];ids=g.GetFaceVertexIndicesAttr().Get();faces=[];cursor=0
  for n in g.GetFaceVertexCountsAttr().Get():faces.append(list(ids[cursor:cursor+n]));cursor+=n
  d=bpy.data.meshes.new('ContextMesh');d.from_pydata(verts,[],faces);d.update();o=bpy.data.objects.new('ReviewPeer_'+p.GetName(),d);bpy.context.collection.objects.link(o);o.data.materials.append(material);count+=1
 return count
n=import_meshes(COMP/'CommanderPanels/CommanderPanels.usdz',(0,0,0),context,'/CommanderPanels/Panel_1/','/CommanderPanels/Panel_1')
n+=import_meshes(COMP/'AltitudeRate/AltitudeRate.usdz',(.125,-.045,.008),reference)
# Actual read-only slot blank behind meter remains required; append exact Panel1 slots with inverse panel matrix.
n+=import_meshes(COMP/'PanelInventory/PanelInventory.usdz',(0,0,0),blankmat,'/PanelInventory/Panels/Panel1/','/PanelInventory/Panels/Panel1')
scene=bpy.context.scene;scene.render.engine='BLENDER_WORKBENCH';scene.render.resolution_x=1300;scene.render.resolution_y=1000;scene.render.resolution_percentage=100;scene.display.shading.light='STUDIO';scene.display.shading.color_type='MATERIAL';scene.display.shading.show_shadows=False;scene.display.shading.show_cavity=True;scene.world.color=(.06,.06,.06)
d=bpy.data.cameras.new('ReviewFront');c=bpy.data.objects.new('ReviewFront',d);bpy.context.collection.objects.link(c);c.location=(.04,0,.8);d.type='ORTHO';d.ortho_scale=.56;scene.camera=c
scene.render.filepath=str(OUT/'review/panel1-fit.png');bpy.ops.render.render(write_still=True)
(OUT/'review/fit-metadata.json').write_text(json.dumps({'reference_meshes':n,'view':'Panel1 front, Y up','root_panel_local_offset_m':[.177,.105,.008],'AltitudeRate_panel_local_offset_m':[.125,-.045,.008],'reference_color':'blue-gray AltitudeRate; gray real CommanderPanels and PanelInventory','limitations':'inspection-only neutral source references, no runtime bindings, no full cabin or headset view; peer assets unchanged'},indent=2)+'\n')
