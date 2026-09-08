"""Reopen, slot/lamp hierarchy, neutral material, USD reimport and peer surface checks."""
import bpy,json,hashlib,math
from pathlib import Path
from mathutils import Vector,Matrix,Quaternion
from mathutils.bvhtree import BVHTree
from pxr import Usd,UsdGeom,UsdShade,UsdUtils,Gf
D=Path(__file__).resolve().parent;report={'checks':[],'compliance':{},'peer_clearance':{},'limits':['No electrical behavior, historical dimensional qualification or headset test','Peer tests are static triangle surfaces, not containment/reach/continuous-sweep proof']}
def check(ok,label):
 if not ok:raise AssertionError(label)
 report['checks'].append(label)
bpy.ops.wm.open_mainfile(filepath=str(D/'CautionWarning.blend'));interface=json.loads((D/'interface.json').read_text());root=bpy.data.objects['CautionWarning'];objects=[root]+list(root.children_recursive);meshes=[o for o in objects if o.type=='MESH'];matrix={o.name:o.matrix_world.copy() for o in objects}
check(interface['named_lamps']==31 and interface['blank_cells']==9,'Source31named/9blank cells');check(len(interface['lamps'])==40,'Forty individual cells');check(len(meshes)==interface['budget']['mesh_count'],'Budget meshes');check(not bpy.data.libraries,'No external library')
for o in meshes:
 o.data.calc_loop_triangles();check(all(t.area>1e-12 for t in o.data.loop_triangles),'Nondegenerate '+o.name)
check(sum(len(o.data.loop_triangles) for o in meshes)==interface['budget']['triangles'],'Triangle budget');check(interface['budget']['triangles']<20000,'Under20k main triangles')
for row in interface['slots']:
 p=row['panel_pose'];q=p['quaternion_xyzw'];expected=Matrix.Translation(Vector(p['translation_m']))@Quaternion((q[3],*q[:3])).to_matrix().to_4x4()@Matrix.Translation(Vector(row['slot_pose']['translation_m']));actual=matrix[row['id']];check(max(abs(actual[i][j]-expected[i][j]) for i in range(4) for j in range(4))<1e-6,'Exact original slot '+row['id'])
 mount=bpy.data.objects[row['id']];pts=[mount.matrix_world.inverted()@o.matrix_world@Vector(v) for o in mount.children_recursive if o.type=='MESH' for v in o.bound_box]
 check(max(abs(v.x) for v in pts)<row['envelope_m'][0]/2 and max(abs(v.y) for v in pts)<row['envelope_m'][1]/2,'Within slot footprint '+row['id']);check(min(v.z for v in pts)>0,'No rear panel penetration '+row['id'])
 check(row['replacement_allowed'] and row['default_placeholder_node'].endswith(row['id']+'/Placeholder'),'Suppression path '+row['id'])
for stem in ['CautionWarning','MasterAlarmReference']:
 for ext in ['usda','usdc','usdz']:
  st=Usd.Stage.Open(str(D/(stem+'.'+ext)));cache=UsdGeom.XformCache();check(st.GetDefaultPrim().GetName()==stem,'Separate root '+stem+ext);check(UsdGeom.GetStageUpAxis(st)=='Y' and UsdGeom.GetStageMetersPerUnit(st)==1,'Meters/Yup '+stem+ext);check(Gf.IsClose(cache.GetLocalToWorldTransform(st.GetDefaultPrim()),Gf.Matrix4d(1),1e-6),'Identity '+stem+ext)
  for p in st.Traverse():
   check(not any('physics' in a.GetName().lower() for a in p.GetAttributes()),'No physics '+stem+str(p.GetPath()))
   if p.IsA(UsdGeom.Mesh):check(bool(UsdShade.MaterialBindingAPI(p).ComputeBoundMaterial()[0]),'Bound material '+stem+str(p.GetPath()))
   if p.IsA(UsdShade.Shader):
    shader=UsdShade.Shader(p);emission=shader.GetInput('emissiveColor');check(not emission or emission.Get() in [None,Gf.Vec3f(0)],'No emission '+stem+str(p.GetPath()))
  if stem=='CautionWarning':
   check(not st.GetPrimAtPath('/MasterAlarmReference'),'No accidentally installed master specimen')
   for lamp in interface['lamps']:
    check(bool(st.GetPrimAtPath(lamp['path'])) and bool(st.GetPrimAtPath(lamp['lens_path'])),'Independent cell path '+ext+lamp['id'])
    if lamp['legend_path']:check(bool(st.GetPrimAtPath(lamp['legend_path'])),'Legend '+ext+lamp['id'])
   for row in interface['slots']:
    m=cache.GetLocalToWorldTransform(st.GetPrimAtPath(row['overlay_path']));expected=matrix[row['id']];check(max(abs(m[i][j]-expected[j][i]) for i in range(4) for j in range(4))<1e-6,'USD complete slot '+ext+row['id'])
 c=UsdUtils.ComplianceChecker(arkit=True);c.CheckCompliance(str(D/(stem+'.usdz')));report['compliance'][stem]={'errors':c.GetErrors(),'failed':c.GetFailedChecks(),'warnings':c.GetWarnings()};check(not c.GetErrors() and not c.GetFailedChecks(),'ARKit compliance '+stem)
def geometry(stage):
 cache=UsdGeom.XformCache();result=[]
 for p in stage.Traverse():
  if not p.IsA(UsdGeom.Mesh):continue
  mesh=UsdGeom.Mesh(p);m=cache.GetLocalToWorldTransform(p);pts=[Vector(m.Transform(Gf.Vec3d(*v))) for v in mesh.GetPointsAttr().Get()];idx=mesh.GetFaceVertexIndicesAttr().Get();faces=[];a=0
  for n in mesh.GetFaceVertexCountsAttr().Get():faces.append(tuple(idx[a:a+n]));a+=n
  lo=[min(v[i] for v in pts) for i in range(3)];hi=[max(v[i] for v in pts) for i in range(3)];result.append((str(p.GetPath()),pts,faces,lo,hi))
 return result
own=geometry(Usd.Stage.Open(str(D/'CautionWarning.usdz')));suppressed={r['default_placeholder_node'] for r in interface['slots']}
for name in ['Cabin','WindowsLPD','CommanderPanels','PanelInventory']:
 path=D.parent/name/(name+'.usdz');peer=geometry(Usd.Stage.Open(str(path)));candidates=0;crossings=[]
 for an,av,af,alo,ahi in own:
  for bn,bv,bf,blo,bhi in peer:
   if '/PlanningLabels/' in bn or any(bn==s or bn.startswith(s+'/') for s in suppressed):continue
   if any(ahi[i]<blo[i] or bhi[i]<alo[i] for i in range(3)):continue
   candidates+=1;hits=BVHTree.FromPolygons(av,af).overlap(BVHTree.FromPolygons(bv,bf))
   if hits:crossings.append({'own':an,'peer':bn,'triangle_pairs':len(hits)})
 report['peer_clearance'][name]={'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'aabb_candidates':candidates,'surface_crossings':crossings}
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False);bpy.ops.wm.usd_import(filepath=str(D/'CautionWarning.usdz'));C=Matrix(((1,0,0,0),(0,0,-1,0),(0,1,0,0),(0,0,0,1)))
for row in interface['slots']:
 o=bpy.data.objects.get(row['id']);check(o is not None,'Reimport '+row['id']);actual=C.inverted()@o.matrix_world;expected=matrix[row['id']];check(max(abs(actual[i][j]-expected[i][j]) for i in range(4) for j in range(4))<1e-5,'Reimport physical matrix '+row['id'])
report['check_count']=len(report['checks']);report['hashes']={f:hashlib.sha256((D/f).read_bytes()).hexdigest() for f in ['CautionWarning.blend','CautionWarning.usdz','MasterAlarmReference.usdz','interface.json']};(D/'validation.json').write_text(json.dumps(report,indent=2)+'\n');print('CHECKS',report['check_count'],'CROSSINGS',{k:len(v['surface_crossings']) for k,v in report['peer_clearance'].items()});check(not any(v['surface_crossings'] for v in report['peer_clearance'].values()),'No peer surface crossings');print('PASS')
