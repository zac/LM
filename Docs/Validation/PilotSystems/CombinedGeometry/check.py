import bpy,json,math,hashlib,itertools
from pathlib import Path
from mathutils import Vector,Matrix,Quaternion
from mathutils.bvhtree import BVHTree
R=Path('/Users/zac/Projects/personal/lm/LMKit');D=R/'Assets/Cockpit/Components';O=Path('/private/tmp/lm-pilot-systems-geometry-review');C=Matrix.Rotation(math.pi/2,4,'X');I=Matrix.Identity(4)
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
assets={};inputs={};newnames=set();suppressed=[]
for name,p,matrix,new in configs:
 before=set(bpy.data.objects);bpy.ops.wm.usd_import(filepath=str(p));added=set(bpy.data.objects)-before
 for ob in added:
  if ob.parent not in added:ob.matrix_world=C@matrix@C.inverted()@ob.matrix_world
 meshes=[]
 for ob in added:
  if ob.type!='MESH':continue
  names=[];ancestor=ob
  while ancestor:names.append(ancestor.name.split('.')[0]);ancestor=ancestor.parent
  suppress=any('PlanningLabels' in n for n in names)
  if name=='CommanderPanels' and ob.name.startswith(('Panel_1_Backing_','Panel_4_Backing_')):suppress=True
  if name=='PanelInventory' and any(n.startswith('Placeholder') for n in names) and any(n in fullslots for n in names):suppress=True
  if suppress:suppressed.append({'asset':name,'mesh':ob.name});continue
  meshes.append(ob)
 assets[name]=meshes;inputs[name]={'path':str(p),'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'matrix_cabin_row_major':list(map(list,matrix)),'meshes':len(meshes),'new':new}
 if new:newnames.add(name)
bpy.context.view_layer.update()
def bounds(ob):
 pts=[ob.matrix_world@Vector(p) for p in ob.bound_box];return [[min(p[i] for p in pts) for i in range(3)],[max(p[i] for p in pts) for i in range(3)]]
def overlap(a,b):return all(a[0][i]<=b[1][i]+1e-7 and b[0][i]<=a[1][i]+1e-7 for i in range(3))
allmeshes=[o for group in assets.values() for o in group];bb={o:bounds(o) for o in allmeshes};trees={}
def tree(o):
 if o not in trees:
  o.data.calc_loop_triangles();trees[o]=BVHTree.FromPolygons([o.matrix_world@v.co for v in o.data.vertices],[t.vertices for t in o.data.loop_triangles],all_triangles=True)
 return trees[o]
for name,objs in assets.items():
 pts=[C.inverted()@(o.matrix_world@Vector(p)) for o in objs for p in o.bound_box];inputs[name]['aabb_cabin_m']=[[min(p[i] for p in pts) for i in range(3)],[max(p[i] for p in pts) for i in range(3)]]
previous=json.loads((O/'results.json').read_text()) if (O/'results.json').exists() else {}
prior={(r['a'],r['b']):r for r in previous.get('results',[])}
results=[]
for one,two in itertools.combinations(assets,2):
 if not (one in newnames or two in newnames):continue
 if (one,two) in prior and all(previous.get('inputs',{}).get(n)==inputs[n] for n in [one,two]):
  reused=dict(prior[(one,two)]);reused['reused_unchanged_inputs']=True;results.append(reused);continue
 candidates=[];crossings=[]
 for a in assets[one]:
  for b in assets[two]:
   if overlap(bb[a],bb[b]):
    candidates.append([a.name,b.name]);pairs=tree(a).overlap(tree(b))
    if pairs:crossings.append({'a':a.name,'b':b.name,'triangle_pairs':len(pairs)})
 results.append({'a':one,'b':two,'broadphase_candidates':len(candidates),'candidates':candidates,'surface_crossings':crossings})
# Probe actual named face surfaces rather than a whole multi-instrument root's center.
face_rays=[]
for name in sorted(newnames):
 candidates=[o for o in assets[name] if any(term in o.name.lower() for term in ['lightface','lens','dial','window','faceplate','displayface'])]
 if not candidates:
  candidates=[o for o in assets[name] if 'face' in o.name.lower() and 'back' not in o.name.lower()]
 if name=='EventTimerControls':candidates=[o for o in assets[name] if 'Grip' in o.name]
 # Pilot FDAI has a named ball rather than a face plate: front-of-local-bounds representative.
 if name=='PilotFDAI':candidates=[next(o for o in assets[name] if 'Ball' in o.name or 'Sphere' in o.name)] if any('Ball' in o.name or 'Sphere' in o.name for o in assets[name]) else []
 for surface in candidates:
  target=sum((surface.matrix_world@v.co for v in surface.data.vertices),Vector())/len(surface.data.vertices)
  pos=C.inverted()@target;pilot=name.startswith('Pilot') or (name=='CautionWarning' and pos.x>0)
  eye=C@Vector((.5588 if pilot else -.5588,1.78,-.38));direction=(target-eye).normalized();length=(target-eye).length;hits=[]
  for peer,meshes in assets.items():
   if peer==name:continue
   for ob in meshes:
    if any(t in ob.name.lower() for t in ['glazing','glass','lens']):continue
    location,normal,index,dist=tree(ob).ray_cast(eye,direction,length-.0005)
    if location is not None:hits.append({'component':peer,'mesh':ob.name,'distance_m':dist})
  face_rays.append({'asset':name,'surface':surface.name,'eye':'LMP' if pilot else 'CDR','target_cabin_m':list(pos),'hits':sorted(hits,key=lambda h:h['distance_m'])})
def iter_parents(ob):
 ob=ob.parent
 while ob:
  yield ob;ob=ob.parent
report={'method':'new installed components vs each other and accepted peers; neutral USDZ at contracted transforms; AABB then triangle BVH; full replacement blanks and duplicate panel backing suppressed, partial backings retained','inputs':inputs,'inventory_sha256':hashlib.sha256((D/'PanelInventory/inventory.json').read_bytes()).hexdigest(),'mesh_paths':{o.name:'/'.join(reversed([o.name]+[p.name for p in iter_parents(o)])) for o in allmeshes},'suppressed':suppressed,'results':results,'face_rays':face_rays,'surface_crossing_pairs':sum(len(r['surface_crossings']) for r in results),'limits':['Static neutral geometry; no self-intersection or continuous motion proof','Rear housing penetration of retained backing may be intentional; each candidate needs classification','No material/native/simulator/headset acceptance','MissionTimerControls not installed and omitted']}
(O/'results.json').write_text(json.dumps(report,indent=2)+'\n');print('CHECK',len(results),'component pairs',report['surface_crossing_pairs'],'crossing mesh pairs')
