"""Separate-process reopen, geometry, optical, transform and USD round-trip gates."""
import bpy,sys,json,math,hashlib
from pathlib import Path
from mathutils import Vector
from pxr import Usd,UsdGeom,UsdShade,UsdUtils,Gf
OUT=Path(__file__).resolve().parent
sys.path.insert(0,str(OUT)); from build import C
report={'checks':[],'limitations':['No Vision Pro or RCP GUI acceptance','No mechanical fit certification','Forward skeleton is intentionally not pressure closed','No door or actuated controls in this component']}
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
p=bpy.data.objects['Mount_DSKY']; child=p.children[0]; before=child.matrix_world.translation.copy(); fixed=bpy.data.objects['Cabin_Deck'].matrix_world.copy(); old=p.location.copy()
p.location.x+=.01;bpy.context.view_layer.update()
check(abs((child.matrix_world.translation-before).length-.01)<1e-5 and bpy.data.objects['Cabin_Deck'].matrix_world==fixed,'Mount independence')
p.location=old;bpy.context.view_layer.update()
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
