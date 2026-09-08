"""Blender headless structural and export validation; no simulator."""
import bpy,json,math,hashlib
from pathlib import Path
from mathutils import Vector,Matrix
from pxr import Usd,UsdGeom,UsdShade
OUT=Path(__file__).resolve().parent
bpy.ops.wm.open_mainfile(filepath=str(OUT/'WindowsLPD.blend'))
s=Usd.Stage.Open(str(OUT/'WindowsLPD.usdz'));assert s
assert UsdGeom.GetStageMetersPerUnit(s)==1 and UsdGeom.GetStageUpAxis(s)=='Y'
assert s.GetDefaultPrim().GetPath().pathString=='/WindowsLPD'
assert not any(p.GetTypeName() in ['Camera','DistantLight','SphereLight','DomeLight','RectLight'] for p in s.Traverse())
assert not any(o.type in ['CAMERA','LIGHT'] for o in bpy.data.objects)
for o in bpy.data.objects:
 assert abs(o.matrix_local.to_3x3().determinant()-1)<1e-5,(o.name,'reflection/scale')
 assert all(abs(col.length-1)<1e-5 for col in o.matrix_local.to_3x3().col),(o.name,'nonunit basis')
 assert o.type in ['EMPTY','MESH']
assert len([o for o in bpy.data.objects if o.name in ['LPD_Inner','LPD_Outer']])==2
assert bpy.data.objects['LPD_Inner'].parent.name=='CDR_Window_Inner'
assert bpy.data.objects['LPD_Outer'].parent.name=='CDR_Window_Outer'
assert not any('LPD' in c.name for c in bpy.data.objects['LMP_Window_Inner'].children_recursive)
# Mesh vertices of all marks/labels must lie inside the respective rounded pane.
C=Matrix(((1,0,0),(0,0,-1),(0,1,0)));inverse=C.inverted()
violations=[];minimum=100
for layer in ['Inner','Outer']:
 glass=bpy.data.objects['CDR_Glazing_'+layer];verts=[inverse@p.co for p in glass.data.vertices];boundary=verts[:len(verts)//2]
 center=sum(boundary,Vector())/len(boundary)
 for o in bpy.data.objects['LPD_'+layer].children_recursive:
  if o.type!='MESH':continue
  for pt in o.data.vertices:
   q=inverse@(o.matrix_local@pt.co)
   distances=[]
   for i,a in enumerate(boundary):
    b=boundary[(i+1)%len(boundary)];e=b-a;n=Vector((-e.y,e.x,0)).normalized()
    if n.dot(center-a)<0:n=-n
    distances.append(n.dot(q-a))
   minimum=min(minimum,min(distances))
   if min(distances)<-1e-5:violations.append(o.name)
assert not violations,sorted(set(violations))
meshes=[p for p in s.Traverse() if p.IsA(UsdGeom.Mesh)]
for p in meshes:
 m=UsdGeom.Mesh(p);points=m.GetPointsAttr().Get();inds=m.GetFaceVertexIndicesAttr().Get()
 assert all(math.isfinite(v) for q in points for v in q)
 assert min(inds)>=0 and max(inds)<len(points)
 assert sum(m.GetFaceVertexCountsAttr().Get())==len(inds)
 assert UsdShade.MaterialBindingAPI(p).ComputeBoundMaterial()[0]
report={'units_and_axis':'PASS meters Y-up','hierarchy':'PASS independent panes/LPD/retainers','mesh_count':len(meshes),'no_cameras_lights':'PASS','right_handed_unit_transforms':'PASS','marking_containment':'PASS','minimum_marking_edge_clearance_m':minimum,'finite_meshes_materials_indices':'PASS','calibrated_targeting':False,'native_transparency_reflection':'not certified by Workbench','asset_hashes':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in OUT.glob('WindowsLPD.*')}}
(OUT/'validation.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
