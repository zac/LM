"""Validate saved Blender and USD, conservative envelope fit and Cabin surface intersections."""
import sys,json,hashlib,itertools
from pathlib import Path
OUT=Path(__file__).resolve().parent
sys.path.insert(0,str(OUT))
from geometry import *
import bmesh
from mathutils.bvhtree import BVHTree
checks=[]
def check(name,ok):
 checks.append({'check':name,'pass':bool(ok)})
 if not ok: raise AssertionError(name)
def bounds(pts): return [[min(p[i] for p in pts) for i in range(3)],[max(p[i] for p in pts) for i in range(3)]]
def usd_meshes(path):
 stage=Usd.Stage.Open(str(path)); cache=UsdGeom.XformCache(); result=[]
 for prim in stage.Traverse():
  if prim.IsA(UsdGeom.Mesh):
   mesh=UsdGeom.Mesh(prim); m=cache.GetLocalToWorldTransform(prim)
   pts=[Vector(m.Transform(Gf.Vec3d(*p))) for p in mesh.GetPointsAttr().Get()]
   ids=list(mesh.GetFaceVertexIndicesAttr().Get()); faces=[]; n=0
   for count in mesh.GetFaceVertexCountsAttr().Get(): faces.append(ids[n:n+count]); n+=count
   result.append((str(prim.GetPath()),pts,faces))
 return result
bpy.ops.wm.open_mainfile(filepath=str(OUT/'CommanderPanels.blend'))
root=bpy.data.objects['CommanderPanels']; bpy.context.view_layer.update()
check('identity source root',all(abs(root.matrix_world[i][j]-(i==j))<1e-7 for i in range(4) for j in range(4)))
check('metric source',bpy.context.scene.unit_settings.scale_length==1)
check('no external dependencies',not bpy.data.libraries and not any(i.source=="FILE" and not i.packed_file for i in bpy.data.images))
meshes=[o for o in bpy.data.objects if o.type=='MESH']
for o in meshes:
 bm=bmesh.new(); bm.from_mesh(o.data)
 check(o.name+' closed outward solid',all(e.is_manifold for e in bm.edges) and bm.calc_volume(signed=True)>0)
 check(o.name+' nonzero faces',all(f.calc_area()>1e-12 for f in bm.faces)); bm.free()
 check(o.name+' no animation',o.animation_data is None)
stage=Usd.Stage.Open(str(OUT/'CommanderPanels.usdz')); cache=UsdGeom.XformCache()
check('meters and Y up',UsdGeom.GetStageMetersPerUnit(stage)==1 and UsdGeom.GetStageUpAxis(stage)=='Y')
check('default root',stage.GetDefaultPrim().GetPath()=='/CommanderPanels')
check('no instruments cameras lights',not any('DSKY_Mount' in str(p.GetPath()) or 'FDAI_Mount' in str(p.GetPath()) or p.GetTypeName() in ['Camera','DistantLight','SphereLight'] for p in stage.Traverse()))
for o in bpy.data.objects:
 names=[]; parent=o
 while parent is not None: names.append(parent.name); parent=parent.parent
 path='/'+'/'.join(reversed(names))
 prim=stage.GetPrimAtPath(path); check(path+' exported',bool(prim))
 expected=C.inverted()@o.matrix_world@C; actual=cache.GetLocalToWorldTransform(prim)
 check(path+' physical transform',max(abs(expected[i][j]-actual[j][i]) for i in range(4) for j in range(4))<1e-6)
 for_mesh = o.type=='MESH'
 if for_mesh:
  points=UsdGeom.Mesh(prim).GetPointsAttr().Get()
  check(path+' physical vertices',len(points)==len(o.data.vertices) and all((Vector(actual.Transform(Gf.Vec3d(*p)))-C.inverted()@o.matrix_world@v.co).length<1e-6 for p,v in zip(points,o.data.vertices)))
compliance=UsdUtils.ComplianceChecker(arkit=True,skipARKitRootLayerCheck=False); compliance.CheckCompliance(str(OUT/'CommanderPanels.usdz'))
check('USDZ compliance',not compliance.GetErrors() and not compliance.GetFailedChecks())
manifest=json.loads((OUT/'mounting.json').read_text()); production=usd_meshes(OUT/'CommanderPanels.usdz'); fit={}
for inst,row in manifest['interfaces'].items():
 ip=stage.GetPrimAtPath(row['interface_path']); im=cache.GetLocalToWorldTransform(ip)
 wanted=row['interface_cabin_relative']['position']
 check(inst+' accepted Cabin position',max(abs(im.ExtractTranslation()[i]-wanted[i]) for i in range(3))<1e-6)
 ref=usd_meshes(OUT.parent/inst/(inst+'.usdz')); bb=bounds([p for _,pts,_ in ref for p in pts])
 aperture=row['aperture_panel_local']['size_xy_m']
 gaps=[aperture[0]/2+bb[0][0],aperture[0]/2-bb[1][0],aperture[1]/2+bb[0][1],aperture[1]/2-bb[1][1]]
 check(inst+' aperture conservatively clears full reference envelope',min(gaps)>.00299)
 distances=[]
 for name,pts,faces in production:
  local=[Vector(im.GetInverse().Transform(Gf.Vec3d(*p))) for p in pts]; pb=bounds(local)
  # Separating AABBs in instrument space: positive is a conservative lower bound.
  ds=[max(bb[0][i]-pb[1][i],pb[0][i]-bb[1][i],0) for i in range(3)]
  distances.append((sum(x*x for x in ds)**.5,name))
 check(inst+' all support solids outside complete reference AABB',min(d[0] for d in distances)>1e-5)
 fit[inst]={'actual_reference_bounds_local_m':bb,'aperture_edge_gaps_left_right_bottom_top_m':gaps,'min_conservative_support_distance_m':min(distances)[0],'nearest_support':min(distances)[1],'rear_housing_clearance':'open rear; no closed compartment or connector service envelope qualified'}
# Review existing Cabin geometry, omitting exactly disabled accepted reservations/shields.
skip=['Panel_1_Reservation','Panel_4_Reservation','CDR_Glareshield','LMP_Glareshield','Reserve_']
cabin=[x for x in usd_meshes(OUT.parent/'Cabin/Cabin.usdz') if not any(n in x[0] for n in skip)]
intersections=[]
for name,pts,faces in production:
 bvh=BVHTree.FromPolygons(pts,faces,all_triangles=False)
 for other,op,of in cabin:
  pairs=bvh.overlap(BVHTree.FromPolygons(op,of,all_triangles=False))
  if pairs: intersections.append({'support':name,'cabin':other,'triangle_pairs':len(pairs)})
check('no support surfaces intersect accepted Cabin geometry',not intersections)
fit['Cabin_surface_intersections']=intersections
fit['Cabin_test_limit']='Triangle surface intersections only; containment, cabling, omitted hull, live controls, ACA sweep and egress not qualified.'
fit['DSKY_thread_conflict']={'drawing_thread_half_pitch_m':.09779,'current_visual_housing_half_width_m':.09779,'radial_room_at_thread_center_m':0,'consequence':'No credible inserted fastener along drawing thread axes through current box. Instrument attachment hardware withheld; coordinator must qualify housing and mounting surface first.'}
(OUT/'clearance.json').write_text(json.dumps(fit,indent=2)+'\n')
report={'checks':checks,'passed':len(checks),'mesh_count':len(meshes),'compliance_warnings':compliance.GetWarnings(),'sha256':{n:hashlib.sha256((OUT/n).read_bytes()).hexdigest() for n in ['CommanderPanels.blend','CommanderPanels.usdz','CommanderPanels.usdc','CommanderPanels.usda']}}
report['triangles']=sum(len(f)-2 for _,_,faces in production for f in faces)
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
bpy.ops.wm.usd_import(filepath=str(OUT/'CommanderPanels.usdz'))
check('USDZ roundtrip mesh count',len([o for o in bpy.data.objects if o.type=='MESH'])==len(meshes))
check('USDZ roundtrip neutral root',bpy.data.objects.get('CommanderPanels') is not None and bpy.data.objects['CommanderPanels'].location.length<1e-6)
report['passed']=len(checks)
(OUT/'validation.json').write_text(json.dumps(report,indent=2)+'\n')
print('VALIDATION PASS',len(checks),'checks; Cabin surface contacts',len(intersections))
