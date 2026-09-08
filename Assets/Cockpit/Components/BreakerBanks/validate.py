"""Targeted static geometry, slot/axis/export and peer AABB checks; no simulator."""
import bpy,json,hashlib,math
from pathlib import Path
from mathutils import Vector,Matrix,Quaternion
from pxr import Usd,UsdGeom,UsdShade,UsdUtils,Gf
D=Path(__file__).resolve().parent
report={'checks':[],'limits':['AABB peer separation or conservative candidate report, not mechanical fit or hand reach.','No electrical binding, Vision Pro optical/performance or lighting acceptance.']}
def check(v,label):
 if not v:raise AssertionError(label)
 report['checks'].append(label)
bpy.ops.wm.open_mainfile(filepath=str(D/'BreakerBanks.blend'));root=bpy.data.objects['BreakerBanks'];objects=[root]+list(root.children_recursive);meshes=[o for o in objects if o.type=='MESH'];interface=json.loads((D/'interface.json').read_text())
check(len(interface['slots'])==9,'Nine mapped slots');check(len({r['id'] for r in interface['slots']})==9,'Unique slots');check(not bpy.data.libraries,'No linked library');check(not [i for i in bpy.data.images if i.source=='FILE' and not i.packed_file],'No external textures')
for o in objects:
 check(all(math.isfinite(x) for row in o.matrix_world for x in row),'Finite transform '+o.name)
 check((o.scale-Vector((1,1,1))).length<1e-5,'Unit scale '+o.name)
for o in meshes:
 o.data.calc_loop_triangles();check(all(t.area>1e-12 for t in o.data.loop_triangles),'Nondegenerate '+o.name)
check(len(meshes)==interface['budget']['mesh_count'],'Declared mesh count');check(sum(len(o.data.loop_triangles) for o in meshes)==interface['budget']['triangles'],'Declared triangles');check(len(meshes)<400,'Mesh budget under400');check(interface['budget']['triangles']<160000,'Triangle budget under160k')
matrices={o.name:o.matrix_world.copy() for o in objects}
for row in interface['slots']:
 p=row['panel_pose'];q=p['quaternion_xyzw'];expected=Matrix.Translation(Vector(p['translation_m']))@Quaternion((q[3],*q[:3])).to_matrix().to_4x4()@Matrix.Translation(Vector(row['slot_pose']['translation_m']))
 actual=bpy.data.objects[row['id']].matrix_world
 check(max(abs(actual[i][j]-expected[i][j]) for i in range(4) for j in range(4))<1e-6,'Exact slot matrix '+row['id'])
 check(row['replacement_allowed'] and row['default_placeholder_node'].endswith('/'+row['id']+'/Placeholder'),'Exact placeholder scope '+row['id'])
 mount=bpy.data.objects[row['id']];local=[mount.matrix_world.inverted()@o.matrix_world@Vector(v) for o in mount.children_recursive if o.type=='MESH' for v in o.bound_box]
 check(max(abs(v.x) for v in local)<.3725,'Slot width contained '+row['id'])
 check(max(abs(v.y) for v in local)<.030,'Slot height contained '+row['id'])
 check(min(v.z for v in local)>-1e-6,'Crewward geometry only '+row['id'])
# Independent grouping of current static occupants; no fake actuator behavior.
a=bpy.data.objects[interface['slots'][0]['id']];peer=bpy.data.objects[interface['slots'][-1]['id']];old=a.location.copy();fixed=peer.matrix_world.copy();a.location.z+=.01;bpy.context.view_layer.update();check(peer.matrix_world==fixed,'Independent row transforms');a.location=old;bpy.context.view_layer.update()
from mathutils.bvhtree import BVHTree
def bvh(stage,path,shift=(0,0,0)):
 p=stage.GetPrimAtPath(path);m=UsdGeom.XformCache().GetLocalToWorldTransform(p);mesh=UsdGeom.Mesh(p);pts=[Vector(m.Transform(Gf.Vec3d(*v)))+Vector(shift) for v in mesh.GetPointsAttr().Get()];counts=mesh.GetFaceVertexCountsAttr().Get();idx=mesh.GetFaceVertexIndicesAttr().Get();faces=[];a=0
 for n in counts:faces.append(tuple(idx[a:a+n]));a+=n
 return BVHTree.FromPolygons(pts,faces)
def worldboxes(stage):
 cache=UsdGeom.XformCache();out=[]
 for p in stage.Traverse():
  if not p.IsA(UsdGeom.Mesh):continue
  m=cache.GetLocalToWorldTransform(p);pts=[m.Transform(Gf.Vec3d(*v)) for v in UsdGeom.Mesh(p).GetPointsAttr().Get()];out.append((str(p.GetPath()),[min(v[i] for v in pts) for i in range(3)],[max(v[i] for v in pts) for i in range(3)]))
 return out
for ext in ['usda','usdc','usdz']:
 stage=Usd.Stage.Open(str(D/('BreakerBanks.'+ext)));check(bool(stage),'Open '+ext);check(UsdGeom.GetStageUpAxis(stage)=='Y' and UsdGeom.GetStageMetersPerUnit(stage)==1,'Yup meters '+ext);cache=UsdGeom.XformCache();check(Gf.IsClose(cache.GetLocalToWorldTransform(stage.GetDefaultPrim()),Gf.Matrix4d(1),1e-6),'Root identity '+ext)
 for row in interface['slots']:
  p=stage.GetPrimAtPath(row['overlay_path']);check(bool(p),'Mapped export path '+ext+row['id']);actual=cache.GetLocalToWorldTransform(p);expected=matrices[row['id']];check(max(abs(actual[i][j]-expected[j][i]) for i in range(4) for j in range(4))<1e-6,'USD slot physical matrix '+ext+row['id'])
 for p in stage.Traverse():
  check(not any('physics' in a.GetName().lower() for a in p.GetAttributes()),'No physics '+ext+str(p.GetPath()))
  if p.IsA(UsdGeom.Mesh):check(bool(UsdShade.MaterialBindingAPI(p).ComputeBoundMaterial()[0]),'Material '+ext+str(p.GetPath()))
checkr=UsdUtils.ComplianceChecker(arkit=True);checkr.CheckCompliance(str(D/'BreakerBanks.usdz'));report['compliance']={'errors':checkr.GetErrors(),'failed':checkr.GetFailedChecks(),'warnings':checkr.GetWarnings()};check(not checkr.GetErrors() and not checkr.GetFailedChecks(),'ARKit USDZ compliance')
ownstage=stage;own=worldboxes(stage);report['peer_clearance']={};base=D.parent;own_bvhs={}
for key,rel in [('Cabin','Cabin/Cabin.usdz'),('WindowsLPD','WindowsLPD/WindowsLPD.usdz'),('PanelInventory','PanelInventory/PanelInventory.usdz'),('ACA','HandControllers/ACA.usdz')]:
 path=base/rel;peer=Usd.Stage.Open(str(path));boxes=worldboxes(peer)
 if key=='ACA':boxes=[(n,[v+t for v,t in zip(lo,[-.49,.9075,-.37])],[v+t for v,t in zip(hi,[-.49,.9075,-.37])]) for n,lo,hi in boxes]
 suppressed={r['default_placeholder_node'] for r in interface['slots']};boxes=[b for b in boxes if not any(b[0]==s or b[0].startswith(s+'/') for s in suppressed) and '/PlanningLabels/' not in b[0]]
 overlaps=[];gap=100
 for an,alo,ahi in own:
  for bn,blo,bhi in boxes:
   d=[max(alo[i]-bhi[i],blo[i]-ahi[i],0) for i in range(3)];dist=math.sqrt(sum(v*v for v in d));gap=min(gap,dist)
   if dist==0:overlaps.append((an,bn))
 crossings=[];peer_bvhs={}
 for an,bn in overlaps:
  if an not in own_bvhs:own_bvhs[an]=bvh(ownstage,an)
  if bn not in peer_bvhs:peer_bvhs[bn]=bvh(peer,bn,(-.49,.9075,-.37) if key=='ACA' else (0,0,0))
  hits=own_bvhs[an].overlap(peer_bvhs[bn])
  if hits:crossings.append({'own':an,'peer':bn,'triangle_pairs':len(hits)})
 report['peer_clearance'][key]={'surface_crossings':crossings,'method':'Conservative AABB broad phase plus actual triangle BVH surface overlap; no containment/continuous sweep proof.','sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'minimum_aabb_gap_m':gap,'possible_overlaps':overlaps,'static_pose_only':True}
# Reimport validates materialization and actual coordinate conversion.
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False);bpy.ops.wm.usd_import(filepath=str(D/'BreakerBanks.usdz'))
C=Matrix(((1,0,0,0),(0,0,-1,0),(0,1,0,0),(0,0,0,1)))
for row in interface['slots']:
 o=bpy.data.objects.get(row['id']);check(o is not None,'Reimport '+row['id']);actual=C.inverted()@o.matrix_world;expected=matrices[row['id']];check(max(abs(actual[i][j]-expected[i][j]) for i in range(4) for j in range(4))<1e-5,'Reimport physical frame '+row['id'])
report['hashes']={f:hashlib.sha256((D/f).read_bytes()).hexdigest() for f in ['BreakerBanks.blend','BreakerBanks.usdz','interface.json']};report['check_count']=len(report['checks']);(D/'validation.json').write_text(json.dumps(report,indent=2)+'\n');print('CHECKS',report['check_count'],'PEER_CROSSINGS',{k:len(v['surface_crossings']) for k,v in report['peer_clearance'].items()});check(not any(v['surface_crossings'] for v in report['peer_clearance'].values()),'No peer triangle surface crossings');print('PASS')
