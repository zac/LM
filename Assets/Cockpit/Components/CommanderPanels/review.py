"""Small Workbench reviews; imported reference triangles only, never exported/saved to production."""
import sys,json,time
from pathlib import Path
OUT=Path(__file__).resolve().parent; sys.path.insert(0,str(OUT))
from geometry import *
bpy.ops.wm.open_mainfile(filepath=str(OUT/'CommanderPanels.blend'))
scene=bpy.context.scene
# Read USD triangles directly, avoiding modifications or unpacked textures in reference folders.
def reference(file,parent,prefix,mat,skip=()):
 stage=Usd.Stage.Open(str(file)); cache=UsdGeom.XformCache(); objs=[]
 for prim in stage.Traverse():
  if not prim.IsA(UsdGeom.Mesh) or any(x in str(prim.GetPath()) for x in skip): continue
  u=UsdGeom.Mesh(prim); m=cache.GetLocalToWorldTransform(prim)
  pts=[tuple(m.Transform(Gf.Vec3d(*p))) for p in u.GetPointsAttr().Get()]; idx=list(u.GetFaceVertexIndicesAttr().Get()); faces=[]; n=0
  for count in u.GetFaceVertexCountsAttr().Get(): faces.append(idx[n:n+count]); n+=count
  objs.append(mesh(prefix+prim.GetName(),pts,faces,mat,parent))
 return objs
refs=node('REVIEW_ONLY_REFERENCES'); cmat=material('Review_Cabin',(.18,.20,.22)); imat=material('Review_instruments_blue',(.10,.32,.48))
cabin=reference(OUT.parent/'Cabin/Cabin.usdz',refs,'REF_',cmat,['Panel_1_Reservation','Panel_4_Reservation','CDR_Glareshield','LMP_Glareshield','Reserve_','Pane_','Shell_Crown','Shell_CDR_Lower','Shell_LMP_Lower'])
manifest=json.loads((OUT/'mounting.json').read_text()); instruments={}
for inst,row in manifest['interfaces'].items():
 r=row['interface_cabin_relative']; mount=node('REVIEW_ONLY_'+inst,r['position'],rx(r['rotation_x_degrees']),refs)
 instruments[inst]=reference(OUT.parent/inst/(inst+'.usdz'),mount,'REF_'+inst+'_',imat)
scene.render.engine='BLENDER_WORKBENCH'; scene.render.resolution_x=1200; scene.render.resolution_y=1000; scene.render.resolution_percentage=100
scene.display.shading.light='STUDIO'; scene.display.shading.color_type='MATERIAL'; scene.display.shading.show_shadows=False; scene.display.shading.show_cavity=True; scene.display.shading.background_type='WORLD'; scene.world.color=(.055,.06,.07)
views={}; times={}
def camera(name,p,target,ortho=None):
 d=bpy.data.cameras.new(name); o=bpy.data.objects.new(name,d); bpy.context.collection.objects.link(o); o.location=v(p); o.rotation_euler=(v(target)-o.location).to_track_quat('-Z','Y').to_euler(); d.clip_start=.005; d.lens=20
 if ortho: d.type='ORTHO'; d.ortho_scale=ortho

 for old in [x for x in bpy.data.objects if x.type=='FONT']: old.hide_render=True
 textdata=bpy.data.curves.new(name+'_ReviewLabel','FONT'); textdata.body='REVIEW ONLY / '+name+'\nBLUE: REFERENCE INSTRUMENTS | PROVISIONAL SUPPORTS'; textdata.size=.00066 if ortho is None else .010; textdata.space_line=1.1
 label=bpy.data.objects.new(name+'_ReviewLabel',textdata); bpy.context.collection.objects.link(label); label.parent=o; label.location=(-.0246,.0201,-.03) if ortho is None else (-ortho*.48,ortho*.38,-.01)
 textdata.materials.append(material(name+'_Label',(.95,.95,.95)))
 scene.camera=o; scene.render.filepath=str(OUT/'reviews'/(name+'.png')); start=time.time(); bpy.ops.render.render(write_still=True); times[name]=time.time()-start
 views[name]={'eye_cabin_m':list(p),'target_cabin_m':list(target),'orthographic_scale_m':ortho,'lens_mm':d.lens,'references':'Blue = actual reference geometry, neutral pose; no texture or runtime state. Gray Cabin = context only.'}
observers=json.loads((OUT/'evidence/assembly/observers.json').read_text())
for name in ['front','side','crew-eye']: camera(name,observers[name]['eye'],observers[name]['target'])
# Side section removes +X half of NEW solids by polygon clipping only in transient review scene.
for o in cabin: o.hide_render=True
for inst,row in manifest['interfaces'].items():
 for other,objects in instruments.items():
  for o in objects: o.hide_render=other!=inst
 for number in [1,4]:
  mount=bpy.data.objects[f'Panel_{number}']
  for o in mount.children_recursive: o.hide_render=(number!=(1 if inst=='FDAI' else 4))
 # Open rectangular aperture seen without instrument first.
 for o in instruments[inst]: o.hide_render=True
 r=row['interface_cabin_relative']; rot=rx(r['rotation_x_degrees']); center=Vector(r['position'])
 camera(inst+'-aperture',center+rot@Vector((0,0,.8)),center,.56)
 for o in instruments[inst]: o.hide_render=False
 # Side oblique shows true through opening and exposed rear, no clipping needed.
 camera(inst+'-clearance',center+rot@Vector((.48,.10,.28)),center,.58)
 # Exact section plane through instrument origin, clip new solids at instrument X=0.
 import bmesh
 section=[]
 for o in list(bpy.data.objects):
  if o.type!='MESH' or o.hide_render : continue
  bm=bmesh.new(); bm.from_mesh(o.data)
  local_origin=o.matrix_world.inverted()@v(center); normal=o.matrix_world.to_3x3().inverted()@v((1,0,0))
  bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),dist=1e-7,plane_co=local_origin,plane_no=normal,clear_outer=True,clear_inner=False)
  original=o.data; clipped=original.copy(); bm.to_mesh(clipped); bm.free(); o.data=clipped; section.append((o,original))
 camera(inst+'-section',center+rot@Vector((.8,0,0)),center,.58)
 for o,original in section:o.data=original
(OUT/'reviews/cameras.json').write_text(json.dumps(views,indent=2)+'\n'); (OUT/'reviews/render-times.json').write_text(json.dumps(times,indent=2)+'\n')
print('REVIEW PASS')
