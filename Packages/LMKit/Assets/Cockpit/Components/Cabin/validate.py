"""Separate-process reopen, geometry, optical, transform and USD round-trip gates."""
import bpy,sys,json,math,hashlib
from pathlib import Path
from mathutils import Vector
from pxr import Usd,UsdGeom,UsdShade,UsdUtils,Gf
OUT=Path(__file__).resolve().parent
sys.path.insert(0,str(OUT)); from build import C
report={'checks':[],'limitations':['No Vision Pro or RCP GUI acceptance','No mechanical fit certification','Visual liner only, not pressure vessel certification','Closed static hatches; no hinge or egress qualification']}
def check(ok,s):
 if not ok:raise AssertionError(s)
 report['checks'].append(s)
bpy.ops.wm.open_mainfile(filepath=str(OUT/'Cabin.blend'))
check(bpy.context.scene.unit_settings.scale_length==1,'Blender meters')
check(not bpy.data.libraries,'No linked libraries')
check(not [i for i in bpy.data.images if i.source=='FILE' and not i.packed_file],'No external texture dependency')
check(bpy.context.scene.render.filepath.startswith('//'),'Relative review output')
objects=[o for o in bpy.data.objects if o.type in ('MESH','EMPTY')]
meshes=[o for o in objects if o.type=='MESH']
check(all((o.scale-Vector((1,1,1))).length<1e-5 for o in objects),'All object scales identity')
for o in meshes:
 o.data.calc_loop_triangles()
 check(all(t.area>1e-10 and t.normal.length>.99 for t in o.data.loop_triangles),'Nondegenerate normals '+o.name)
 # Each solid must be closed and outward oriented, including triangular panes.
 edges={}
 for f in o.data.polygons:
  for edge in f.edge_keys:edges[edge]=edges.get(edge,0)+1
 check(all(n==2 for n in edges.values()),'Closed mesh '+o.name)
 vol=sum(o.data.vertices[t.vertices[0]].co.dot(o.data.vertices[t.vertices[1]].co.cross(o.data.vertices[t.vertices[2]].co))/6 for t in o.data.loop_triangles)
 check(vol>0,'Outward winding '+o.name)
# Independently movable groups: reservation child moves with mount, deck stays fixed.
p=bpy.data.objects['Forward_Hatch_Closed']; child=p.children[0]; before=child.matrix_world.translation.copy(); fixed=bpy.data.objects['Cabin_Deck'].matrix_world.copy(); old=p.location.copy()
p.location.x+=.01;bpy.context.view_layer.update()
check(abs((child.matrix_world.translation-before).length-.01)<1e-5 and bpy.data.objects['Cabin_Deck'].matrix_world==fixed,'Mount independence')
p.location=old;bpy.context.view_layer.update()
# Sample all directions from crew and aft positions; the only allowed escapes
# are the two open triangular apertures and agreed docking opening.
from mathutils.geometry import intersect_ray_tri
win=json.loads((OUT/'evidence/foundation/windows-interface-80c9b2d.json').read_text())
def permitted(origin,direction):
 for row in win['forward'].values():
  pts=[Vector(p) for p in row['corners']]
  if intersect_ray_tri(*pts,direction,origin,True) is not None:return True
 dock=win['docking'];n=Vector(dock['normal_toward_cabin']);den=direction.dot(n)
 if abs(den)>1e-8:
  t=(Vector(dock['center'])-origin).dot(n)/den
  if t>0:
   d=origin+direction*t-Vector(dock['center']);w,h=dock['shell_hole_size_m']
   # Tangent aperture through a faceted curved liner allows small edge tolerance.
   if abs(d.dot(Vector(dock['right'])))<w/2+.008 and abs(d.dot(Vector(dock['up'])))<h/2+.002:return True
 return False
check(abs(Vector(win['docking']['right']).cross(Vector(win['docking']['up'])).dot(Vector(win['docking']['normal_toward_cabin']))-1)<1e-6,'Docking contract proper rotation')
aperture_samples=0;deps=bpy.context.evaluated_depsgraph_get()
for side in ['CDR','LMP']:
 origin=Vector(win['eyes'][side]);pts=[Vector(p) for p in win['forward'][side+'_Window_Inner']['corners']]
 for i in range(1,19):
  for j in range(1,20-i):
   target=pts[0]*(1-(i+j)/20)+pts[1]*i/20+pts[2]*j/20;d=(target-origin).normalized()
   hit=bpy.context.scene.ray_cast(deps,C.to_3x3()@origin,C.to_3x3()@d,distance=4)
   if hit[0]:print('BLOCKED',side,i,j,hit[4].name,list(C.inverted().to_3x3()@hit[1]))
   check(not hit[0],'Unblocked '+side+' aperture sample '+str(aperture_samples));aperture_samples+=1
report['open_aperture_samples']=aperture_samples
misses=[];escaped=0;N=4096;deps=bpy.context.evaluated_depsgraph_get()
for origin in [Vector((-.5588,1.78,-.38)),Vector((.5588,1.78,-.38)),Vector((0,1.3,.6)),Vector((0,.3,-.25))]:
 for i in range(N):
  y=1-2*(i+.5)/N;a=i*math.pi*(3-math.sqrt(5));r=math.sqrt(1-y*y);d=Vector((r*math.cos(a),y,r*math.sin(a)))
  hit=bpy.context.scene.ray_cast(deps,C.to_3x3()@origin,C.to_3x3()@d,distance=10)[0]
  if not hit:
   escaped+=1
   if not permitted(origin,d):misses.append({'origin':list(origin),'direction':list(d)})
report['enclosure_rays']={'sample_count':N*4,'permitted_window_escapes':escaped-len(misses),'unexpected_escapes':misses}
(OUT/'enclosure-rays.json').write_text(json.dumps(report['enclosure_rays'],indent=2)+'\n')
check(not misses,'Sampled visual closure except agreed window apertures')
check(not [o for o in meshes if any(t in o.name for t in ['Reservation','Glareshield','Pane_','Frame_','Reserve_'])],'No duplicated panels, surrounds, frames or panes')
manifest=json.loads((OUT/'mounts.json').read_text()); original={o.name:C.inverted()@o.matrix_world@C for o in objects}
report['mesh_count']=len(meshes);report['triangles']=sum(len(o.data.loop_triangles) for o in meshes)
for ext in ['usda','usdc','usdz']:
 stage=Usd.Stage.Open(str(OUT/('Cabin.'+ext))); check(bool(stage),'USD open '+ext)
 check(UsdGeom.GetStageUpAxis(stage)=='Y' and UsdGeom.GetStageMetersPerUnit(stage)==1,'USD units and Y up '+ext)
 root=stage.GetDefaultPrim();check(root.GetName()=='Cabin','Default root '+ext)
 cache=UsdGeom.XformCache();check(Gf.IsClose(cache.GetLocalToWorldTransform(root),Gf.Matrix4d(1),1e-7),'Identity root '+ext)
 for prim in stage.Traverse():
  if prim.GetName() in original:
   expected=original[prim.GetName()];actual=cache.GetLocalToWorldTransform(prim)
   check(max(abs(actual[i][j]-expected[j][i]) for i in range(4) for j in range(4))<1e-6,'Physical transform '+ext+' '+prim.GetName())
  if prim.IsA(UsdGeom.Mesh):
   check(bool(UsdShade.MaterialBindingAPI(prim).ComputeBoundMaterial()[0]),'Bound material '+ext+' '+prim.GetName())
 for name,row in manifest['mounts'].items():
  prim=stage.GetPrimAtPath(row['path']);check(bool(prim),'Mount path '+ext+' '+name)
  check(Gf.IsClose(cache.GetLocalToWorldTransform(prim).ExtractTranslation(),Gf.Vec3d(*row['position']),1e-6),'Mount position '+ext+' '+name)
 eye=cache.GetLocalToWorldTransform(stage.GetPrimAtPath('/Cabin/Optical/CDR_Eye')).ExtractTranslation();check(Gf.IsClose(eye,Gf.Vec3d(-.5588,1.78,-.38),1e-6),'CDR eye preserved '+ext)
 for layer in ['Inner','Outer']:
  prim=stage.GetPrimAtPath('/Cabin/Optical/CDR_Window_'+layer);m=cache.GetLocalToWorldTransform(prim)
  check(Gf.IsClose(m.TransformDir(Gf.Vec3d(0,0,1)),Gf.Vec3d(*manifest['optical']['CDR_Window_'+layer]['normal']),1e-6),'Pane local Z toward eye '+ext+' '+layer)
  check(bool(stage.GetPrimAtPath(str(prim.GetPath())+'/LPD_'+layer)),'Separate LPD layer '+ext+' '+layer)
 bounds=UsdGeom.BBoxCache(Usd.TimeCode.Default(),['default']).ComputeWorldBound(root).ComputeAlignedRange(); report['bounds_scene_m']=[list(bounds.GetMin()),list(bounds.GetMax())]
inn=[Vector(p) for p in manifest['optical']['CDR_Window_Inner']['corners']];out=[Vector(p) for p in manifest['optical']['CDR_Window_Outer']['corners']];eye=Vector((-.5588,1.78,-.38));normal=Vector(manifest['optical']['CDR_Window_Inner']['normal'])
for a,b,length in [(0,1,.7112),(1,2,.6096),(2,0,.635)]:check(abs((inn[a]-inn[b]).length-length)<1e-6,'Nominal triangle side '+str(length))
for a,b in zip(inn,out):
 check(abs((b-a).dot(normal)+.02)<1e-6,'Provisional 20 mm plane separation')
 check((a-eye).normalized().cross((b-eye).normalized()).length<1e-6,'Corresponding corners collimate')
checker=UsdUtils.ComplianceChecker(arkit=True);checker.CheckCompliance(str(OUT/'Cabin.usdz'));report['usd_compliance']={'errors':checker.GetErrors(),'failed_checks':checker.GetFailedChecks(),'warnings':checker.GetWarnings()};check(not checker.GetErrors() and not checker.GetFailedChecks(),'USDZ ARKit compliance')
# Native Blender USD import converts Y up to native Z up; check actual geometry bounds and hierarchy.
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
bpy.ops.wm.usd_import(filepath=str(OUT/'Cabin.usdz'),import_materials=True)
for name,expected in original.items():
 o=bpy.data.objects.get(name);check(o is not None,'Reimport name '+name)
 actual=C.inverted()@o.matrix_world
 check(max(abs(actual[i][j]-expected[i][j]) for i in range(4) for j in range(4))<1e-5,'Reimport transform '+name)
vs=[C.inverted().to_3x3()@(o.matrix_world@Vector(v)) for o in bpy.data.objects if o.type=='MESH' for v in o.bound_box]
bounds=[[min(v[i] for v in vs) for i in range(3)],[max(v[i] for v in vs) for i in range(3)]]
check(max(abs(bounds[a][b]-report['bounds_scene_m'][a][b]) for a in range(2) for b in range(3))<1e-5,'Reimport physical geometry bounds')
report['sha256']={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in [OUT/'Cabin.blend',OUT/'Cabin.usda',OUT/'Cabin.usdc',OUT/'Cabin.usdz',OUT/'mounts.json']}
report['check_count']=len(report['checks']);(OUT/'validation.json').write_text(json.dumps(report,indent=2)+'\n');print('PASS',report['check_count'])
