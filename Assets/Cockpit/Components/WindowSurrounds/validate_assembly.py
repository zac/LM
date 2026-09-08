"""Scoped assembly check adapted from the coordinator audit_model pilot-systems checker.
This worker changes only WindowSurrounds; all companion models are read-only inputs.
Raw USD points and world transforms avoid Blender importer axis reinterpretation. Exact paths and hashes are recorded. Explicit sibling worktree fallbacks support
parallel delivery; after merge update these paths to the accepted component copies.
"""
import bpy,json,math,hashlib,itertools
from pxr import Usd,UsdGeom
from pathlib import Path
from mathutils import Vector,Matrix,Quaternion
from mathutils.bvhtree import BVHTree
O=Path(__file__).resolve().parent;D=O.parent;R=D.parents[2];C=Matrix.Rotation(math.pi/2,4,'X');I=Matrix.Identity(4)
bpy.ops.wm.read_factory_settings(use_empty=True)
inv=json.loads((D/'PanelInventory/inventory.json').read_text())
def pose(p):
 x,y,z,w=p.get('quaternion_xyzw',[0,0,0,1]);return Matrix.Translation(Vector(p.get('translation_m',[0,0,0])))@Quaternion((w,x,y,z)).to_matrix().to_4x4()
def panel(pid):return pose(next(p['pose'] for p in inv['panels'] if p['id']==pid))
def slot(sid):
 for p in inv['panels']:
  for s in p['slots']:
   if s['id']==sid:return pose(p['pose'])@pose(s['pose'])
 raise KeyError(sid)
configs=[]
def add(name,path,matrix,new=False):configs.append((name,Path(path),matrix,new))
for name in ['Cabin','WindowsLPD','PanelInventory','CommanderPanels','InteriorDetails','BreakerBanks']:add(name,D/name/(name+'.usdz'),I)
a=json.loads((D/'AltitudeRate/interface.json').read_text());add('AltitudeRate',D/'AltitudeRate/AltitudeRate.usdz',slot(a['slot'])@pose(a['slot_local_pose']))
add('CrossPointer',D/'CrossPointer/CrossPointer.usdz',slot('Panel1__CrossPointer'));add('DSKY',D/'DSKY/DSKY.usdz',slot('Panel4__DSKY'));add('FDAI',D/'FDAI/FDAI.usdz',slot('Panel1__FDAI'));add('PilotFDAI',D/'FDAI/FDAI.usdz',slot('Panel2__FDAI'),True)
add('ACA',D/'HandControllers/ACA.usdz',Matrix.Translation(Vector((-.49,.9075,-.37))))
for item in json.loads((D/'DescentControls/interface.json').read_text())['components']:add(item['id'],D/'DescentControls'/item['asset'],slot(item['slot']))
em=json.loads((D/'EngineControls/mounting-matrices.json').read_text());add('EngineButtons',D/'EngineControls/EngineButtons.usdz',Matrix(em['EngineButtons']),True)
for lamp in em['LunarContact']:add(lamp['id'],D/'EngineControls/LunarContact.usdz',Matrix(lamp['Cabin_matrix_rows']),True)
p=Path('/private/tmp/lmkit-propulsion-instruments/Assets/Cockpit/Components/PropulsionInstruments');m=json.loads((p/'interface.json').read_text())['mounting'];add('PropulsionInstruments',p/'PropulsionInstruments.usdz',slot(m['slot'])@Matrix.Translation(Vector(m['slot_local_translation_m'])),True)
t=Path('/private/tmp/lmkit-timers/Assets/Cockpit/Components/Timers')
for a in json.loads((t/'interface.json').read_text())['assets']:
 if a.get('panel_slot'):add(a['root'],t/a['filename'],slot(a['panel_slot'])@pose(a['slot_local_pose']),True)
w=Path('/private/tmp/lmkit-caution-warning/Assets/Cockpit/Components/CautionWarning');add('CautionWarning',w/'CautionWarning.usdz',I,True)
# Suppress only validated full-slot occupants; partial backings remain physical context.
fullslots={'Panel1__FDAI','Panel2__FDAI','Panel4__DSKY','Panel1__CrossPointer','Panel3__Stability','Panel5__Engine','Panel1__Warning','Panel2__Caution'}
fullslots.update(s['id'] for s in json.loads((D/'BreakerBanks/interface.json').read_text())['slots'])
add('WindowSurrounds',O/'WindowSurrounds.usdz',I,True)
extra_suppressions={}
for component,location in [('WindowSurrounds',O),('InstrumentConsole',Path('/private/tmp/lmkit-instrument-console/Assets/Cockpit/Components/InstrumentConsole')),('LowerConsole',Path('/private/tmp/lmkit-lower-console/Assets/Cockpit/Components/LowerConsole'))]:
 if (location/(component+'.usdz')).exists():
  if component!='WindowSurrounds':add(component,location/(component+'.usdz'),I)
  ci=json.loads((location/'interface.json').read_text())
  for row in ci.get('suppressions',[]):extra_suppressions.setdefault(row['component'],set()).add(row['path'].split('/')[-1])

assets={};inputs={};suppressed=[]
for name,p,matrix,new in configs:
 stage=Usd.Stage.Open(str(p));cache=UsdGeom.XformCache();meshes=[]
 for prim in stage.Traverse():
  if not prim.IsA(UsdGeom.Mesh):continue
  names=str(prim.GetPath()).split('/');pn=prim.GetName();skip='PlanningLabels' in names or pn in extra_suppressions.get(name,set())
  if name=='CommanderPanels' and pn.startswith(('Panel_1_Backing_','Panel_4_Backing_')):skip=True
  if name=='PanelInventory' and any(n.startswith('Placeholder') for n in names) and any(n in fullslots for n in names):skip=True
  if skip:suppressed.append({'asset':name,'path':str(prim.GetPath())});continue
  usdmesh=UsdGeom.Mesh(prim);world=cache.GetLocalToWorldTransform(prim);points=[matrix@Vector(world.Transform(q)) for q in usdmesh.GetPointsAttr().Get()];counts=usdmesh.GetFaceVertexCountsAttr().Get();indices=usdmesh.GetFaceVertexIndicesAttr().Get();polygons=[];at=0
  for count in counts:polygons.append(indices[at:at+count]);at+=count
  if not polygons:continue
  bound=[[min(q[i] for q in points) for i in range(3)],[max(q[i] for q in points) for i in range(3)]];meshes.append({'name':pn,'path':str(prim.GetPath()),'points':points,'bounds':bound,'tree':BVHTree.FromPolygons(points,polygons)})
 assets[name]=meshes;inputs[name]={'path':str(p),'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'stage_up_axis':str(UsdGeom.GetStageUpAxis(stage)),'meters_per_unit':UsdGeom.GetStageMetersPerUnit(stage),'matrix_cabin_row_major':list(map(list,matrix)),'meshes':len(meshes)}
def overlap(a,b):return all(a[0][i]<=b[1][i]+1e-7 and b[0][i]<=a[1][i]+1e-7 for i in range(3))
results=[]
for peer,meshes in assets.items():
 if peer=='WindowSurrounds':continue
 crossing=[]
 for a in assets['WindowSurrounds']:
  for b in meshes:
   if overlap(a['bounds'],b['bounds']):
    pairs=a['tree'].overlap(b['tree'])
    if pairs:crossing.append({'surround':a['name'],'peer':b['name'],'triangle_pairs':len(pairs)})
 results.append({'peer':peer,'surface_crossings':crossing})
face_rays=[]
for name,meshes in assets.items():
 if name in ['Cabin','WindowsLPD','WindowSurrounds','InstrumentConsole','LowerConsole','PanelInventory','CommanderPanels','InteriorDetails','BreakerBanks']:continue
 candidates=[o for o in meshes if any(t in o['name'].lower() for t in ['lightface','lens','dial','window','faceplate','displayface'])]
 if not candidates:candidates=[o for o in meshes if 'face' in o['name'].lower() and 'back' not in o['name'].lower()]
 if name=='EventTimerControls':candidates=[o for o in meshes if 'Grip' in o['name']]
 if name=='PilotFDAI':candidates=[o for o in meshes if 'Ball' in o['name']][:1]
 for surface in candidates:
  target=sum(surface['points'],Vector())/len(surface['points']);pilot=name.startswith('Pilot') or (name=='CautionWarning' and target.x>0);eye=Vector((.5588 if pilot else -.5588,1.78,-.38));delta=target-eye;hits=[]
  for o in assets['WindowSurrounds']:
   hit=o['tree'].ray_cast(eye,delta.normalized(),delta.length-.0005)
   if hit[0] is not None:hits.append({'mesh':o['name'],'hit_cabin_m':list(hit[0]),'distance_m':hit[3]})
  face_rays.append({'asset':name,'surface':surface['name'],'target_cabin_m':list(target),'eye':'LMP' if pilot else 'CDR','hits':hits})
report={'method':'Raw USD points transformed by authored world matrices and coordinator placement; no Blender import axis conversion; triangle BVH overlaps and eye-to-face rays','inputs':inputs,'suppressed':suppressed,'results':results,'face_rays':face_rays,'blocked_face_rays':sum(bool(r['hits']) for r in face_rays),'limitations':['Static source meshes; joint-contact intersections require classification','No inferred physical survey or optical calibration','Companion new enclosure files may be supplied from explicitly recorded sibling worktrees']};(O/'assembly-validation.json').write_text(json.dumps(report,indent=2)+'\n');print('PAIRS',len(results),'RAYS',len(face_rays),'BLOCKED',report['blocked_face_rays']);print('CROSSINGS',[(r['peer'],len(r['surface_crossings'])) for r in results if r['surface_crossings']])
