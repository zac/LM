"""Blender --background --factory-startup --python validate.py. Read-only geometry checks."""
import bpy,bmesh,json,hashlib,itertools,math
from pathlib import Path
from mathutils import Vector,Matrix,Quaternion
from mathutils.bvhtree import BVHTree
from pxr import Usd,UsdGeom,UsdUtils
D=Path(__file__).resolve().parent;R=D.parents[3];C=Matrix.Rotation(math.pi/2,4,'X');report={}
meta=json.loads((D/'interface.json').read_text());st=Usd.Stage.Open(str(D/'InteriorDetails.usdz'))
assert st.GetDefaultPrim().GetName()=='InteriorDetails';assert UsdGeom.GetStageUpAxis(st)=='Y';assert UsdGeom.GetStageMetersPerUnit(st)==1
assert meta['artifact_sha256']==hashlib.sha256((D/'InteriorDetails.usdz').read_bytes()).hexdigest()
assert not any(p.GetTypeName() in ['Camera','DistantLight','SphereLight','RectLight'] for p in st.Traverse())
assert not any(any('Physics' in s or 'Input' in s for s in p.GetAppliedSchemas()) for p in st.Traverse())
root=UsdGeom.Xformable(st.GetDefaultPrim());assert root.GetLocalTransformation().GetRow(3)==(0,0,0,1)
checker=UsdUtils.ComplianceChecker(arkit=True,skipVariants=False,rootPackageOnly=False);checker.CheckCompliance(str(D/'InteriorDetails.usdz'))
report['usd_compliance']={'errors':checker.GetErrors(),'failed_checks':checker.GetFailedChecks(),'warnings':checker.GetWarnings()}
def fingerprint(prim):
 rows=[]
 for p in Usd.PrimRange(prim):
  rows.append([str(p.GetPath()),p.GetTypeName(),[[a.GetName(),str(a.Get())] for a in sorted(p.GetAttributes(),key=lambda a:a.GetName())],[[r.GetName(),list(map(str,r.GetTargets()))] for r in sorted(p.GetRelationships(),key=lambda r:r.GetName())]])
 return hashlib.sha256(json.dumps(rows,sort_keys=True).encode()).hexdigest()
baseline=json.loads((D/'evidence/phase1-group-fingerprints.json').read_text())
report['phase1_groups_preserved']={name:fingerprint(st.GetPrimAtPath('/InteriorDetails/'+name))==sha for name,sha in baseline['groups'].items()}
assert all(report['phase1_groups_preserved'].values())
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.wm.usd_import(filepath=str(D/'InteriorDetails.usdz'));details=[o for o in bpy.data.objects if o.type=='MESH'];inputs={}
for name,folder in [('Cabin','Cabin'),('WindowsLPD','WindowsLPD'),('PanelInventory','PanelInventory'),('CommanderPanels','CommanderPanels')]:
 p=R/'Assets/Cockpit/Components'/folder/(name+'.usdz');inputs[name]={'path':str(p),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()};bpy.ops.wm.usd_import(filepath=str(p))
# ACA imported and mounted at its retained baseline root.
p=R/'Assets/Cockpit/Components/HandControllers/ACA.usdz';before=set(bpy.data.objects);bpy.ops.wm.usd_import(filepath=str(p));aca=set(bpy.data.objects)-before
for o in aca:
 if o.parent not in aca:o.matrix_world=C@Matrix.Translation(Vector((-.49,.9075,-.37)))@C.inverted()@o.matrix_world
inputs['ACA']={'path':str(p),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}
# Current accepted functional peers and static banks, all at their contracted mounts.
inventory=json.loads((R/'Assets/Cockpit/Components/PanelInventory/inventory.json').read_text())
def pose(p):
 x,y,z,w=p['quaternion_xyzw'];return Matrix.Translation(Vector(p['translation_m']))@Quaternion((w,x,y,z)).to_matrix().to_4x4()
def slot(sid):
 for p in inventory['panels']:
  for s in p['slots']:
   if s['id']==sid:return pose(p['pose'])@pose(s['pose'])
 raise KeyError(sid)
base=R/'Assets/Cockpit/Components'
alt=json.loads((base/'AltitudeRate/interface.json').read_text())
config=[('BreakerBanks','BreakerBanks',Matrix.Identity(4)),('AltitudeRate','AltitudeRate',slot(alt['slot'])@pose(alt['slot_local_pose'])),('CrossPointer','CrossPointer',slot('Panel1__CrossPointer')),('DSKY','DSKY',slot('Panel4__DSKY')),('FDAI','FDAI',slot('Panel1__FDAI'))]
for item in json.loads((base/'DescentControls/interface.json').read_text())['components']:config.append(('DescentControls',item['id'],slot(item['slot'])))
for folder,name,matrix in config:
 p=base/folder/(name+'.usdz');inputs[name]={'path':str(p),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()};before=set(bpy.data.objects);bpy.ops.wm.usd_import(filepath=str(p));new=set(bpy.data.objects)-before
 for ob in new:
  if ob.parent not in new:ob.matrix_world=C@matrix@C.inverted()@ob.matrix_world
bpy.context.view_layer.update();peers=[o for o in bpy.data.objects if o.type=='MESH' and o not in details]
def bounds(o):
 v=[o.matrix_world@Vector(p) for p in o.bound_box];return [Vector([min(p[i] for p in v) for i in range(3)]),Vector([max(p[i] for p in v) for i in range(3)])]
def overlaps(a,b):return all(a[0][i]<=b[1][i] and b[0][i]<=a[1][i] for i in range(3))
cache={};bb={o:bounds(o) for o in details+peers}
def tree(o):
 if o not in cache:
  o.data.calc_loop_triangles();cache[o]=BVHTree.FromPolygons([o.matrix_world@v.co for v in o.data.vertices],[t.vertices for t in o.data.loop_triangles],all_triangles=True)
 return cache[o]
crossings=[];candidates=0
for d in details:
 for p in peers:
  if overlaps(bb[d],bb[p]):
   candidates+=1;pairs=tree(d).overlap(tree(p))
   if pairs:crossings.append({'detail':d.name,'peer':p.name,'triangle_pairs':len(pairs)})
bad_solids=[]
for ob in details:
 bm=bmesh.new();bm.from_mesh(ob.data)
 if bm.calc_volume(signed=True)<=0 or any(not e.is_manifold for e in bm.edges):bad_solids.append(ob.name)
 bm.free()
report['nonpositive_or_nonmanifold_meshes']=bad_solids
def group_name(ob):
 while ob.parent and ob.parent.name!='InteriorDetails':ob=ob.parent
 return ob.name
newgroups={'ForwardOverheadLiner','CDRAftCrownInserts','LMPAftCrownInserts','ForwardHatchFittings','TransferHatchFittings','ForwardHeaderCableRun'}
intergroup=[]
for i,a in enumerate(details):
 for b in details[i+1:]:
  ga,gb=group_name(a),group_name(b)
  if ga==gb or (ga not in newgroups and gb not in newgroups):continue
  if overlaps(bb[a],bb[b]):
   pairs=tree(a).overlap(tree(b))
   if pairs:intergroup.append({'a':a.name,'group_a':ga,'b':b.name,'group_b':gb,'triangle_pairs':len(pairs)})
report['new_group_crossings']=intergroup
report['surface_crossings']=crossings;report['aabb_candidate_pairs']=candidates
# Conservative exact-axis slot envelope exclusion: transforms each detail's vertices to slot coordinates.
inventory=json.loads((R/'Assets/Cockpit/Components/PanelInventory/inventory.json').read_text())
def pose(p):
 x,y,z,w=p['quaternion_xyzw'];return Matrix.Translation(Vector(p['translation_m']))@Quaternion((w,x,y,z)).to_matrix().to_4x4()
slot_candidates=[]
for panel in inventory['panels']:
 for slot in panel['slots']:
  inv=(pose(panel['pose'])@pose(slot['pose'])).inverted()@C.inverted();center=Vector(slot.get('envelope_center_local_m',[0,0,0]));half=Vector(slot['envelope_m'])/2
  for d in details:
   verts=[inv@(d.matrix_world@v.co) for v in d.data.vertices];low=Vector([min(v[i] for v in verts) for i in range(3)]);high=Vector([max(v[i] for v in verts) for i in range(3)])
   if overlaps((low,high),(center-half,center+half)):slot_candidates.append({'detail':d.name,'slot':slot['id']})
report['slot_envelope_aabb_candidates']=slot_candidates;report['inputs']=inputs;report['detail_meshes']=len(details);report['triangle_count']=meta['triangles'];report['limitations']='Neutral geometry; triangle surface crossing and conservative slot envelope tests; no swept human/hand clearance, optics, fabrication or application acceptance.'
# Interior details alone must not block representative clear window paths.
window_hits=[];window_rays=0
for name,eye in [('CDR_Glazing_Inner',(-.5588,1.78,-.38)),('LMP_Glazing_Inner',(.5588,1.78,-.38)),('Docking_Glazing_Inner',(-.5588,1.78,-.38))]:
 ob=bpy.data.objects.get(name)
 if not ob:raise AssertionError(name)
 pts=[ob.matrix_world@v.co for v in ob.data.vertices];center=sum(pts,Vector())/len(pts);start=C@Vector(eye)
 for target in [center]+[center.lerp(p,.70) for p in pts]:
  direction=(target-start).normalized();length=(target-start).length;window_rays+=1
  for detail in details:
   location,normal,index,distance=tree(detail).ray_cast(start,direction,length)
   if location is not None:window_hits.append({'window':name,'detail':detail.name,'distance_m':distance})
report['window_detail_probe_count']=window_rays;report['window_detail_probe_hits']=window_hits
report['pass']=not window_hits and not intergroup and not bad_solids and not crossings and not slot_candidates and not checker.GetErrors() and not checker.GetFailedChecks()
(D/'validation.json').write_text(json.dumps(report,indent=2)+'\n');print('VALIDATION',report['pass'],'crossings',len(crossings),'slot candidates',len(slot_candidates))
assert report['pass']
