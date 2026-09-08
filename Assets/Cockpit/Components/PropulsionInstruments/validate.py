"""Validate owned neutral artifacts, declared channels and front fit. Never supplies live physics."""
from pathlib import Path
import json,math
import bpy
from pxr import Usd,UsdGeom,UsdUtils,Gf
OUT=Path(__file__).resolve().parent;m=json.loads((OUT/'interface.json').read_text());stage=Usd.Stage.Open(str(OUT/'PropulsionInstruments.usdz'));cache=UsdGeom.XformCache();checks=[]
def check(name,v):
 checks.append({'check':name,'pass':bool(v)})
 if not v:raise AssertionError(name)
def near(a,b):return max(abs(x-y) for x,y in zip(a,b))<1e-6
root=stage.GetDefaultPrim();check('identity root',str(root.GetPath())==m['root'] and cache.GetLocalToWorldTransform(root)==Gf.Matrix4d(1));check('meters Yup',UsdGeom.GetStageMetersPerUnit(stage)==1 and UsdGeom.GetStageUpAxis(stage)=='Y');check('no declared measured live source',not m['availability']['live_supported_channels'])
check('quantity documented range distinct from digit capacity',m['instruments']['Quantity']['domain']==[0,95] and m['instruments']['Quantity']['digit_representation_capacity']==[0,99])
check('helium range not invented from digit capacity',m['instruments']['Helium']['domain'] is None and m['instruments']['Helium']['pressure_representation_capacity']==[0,9990])
check('no review-only geometry',not any('ReviewOnly' in p.GetName() for p in stage.Traverse()))
check('no cameras lights or external references',not any(p.IsA(UsdGeom.Camera) or 'Light' in p.GetTypeName() or p.HasAuthoredReferences() or p.HasAuthoredPayloads() for p in stage.Traverse()))
counts={'meshes':0,'triangles':0};bounds={};points={}
for p in stage.Traverse():
 if not p.IsA(UsdGeom.Mesh):continue
 g=UsdGeom.Mesh(p);verts=g.GetPointsAttr().Get();xf=cache.GetLocalToWorldTransform(p);ps=[xf.Transform(Gf.Vec3d(*v)) for v in verts];check(str(p.GetPath())+' finite vertices',bool(ps) and all(math.isfinite(c) for v in ps for c in v));ns=g.GetFaceVertexCountsAttr().Get();check(str(p.GetPath())+' triangles',all(n==3 for n in ns));counts['meshes']+=1;counts['triangles']+=sum(n-2 for n in ns);points[str(p.GetPath())]=ps
for name,r in m['instruments'].items():
 p=stage.GetPrimAtPath(r['root']);check(name+' root transform',p and near(cache.GetLocalToWorldTransform(p).ExtractTranslation(),r['translation_m']))
 ps=[v for path,vs in points.items() if path.startswith(r['root']+'/') for v in vs];bounds[name]=[[min(v[i] for v in ps) for i in range(3)],[max(v[i] for v in ps) for i in range(3)]]
 fixed=stage.GetPrimAtPath(r['root']+'/Fixed');fixed_before=cache.GetLocalToWorldTransform(fixed)
 for channel,n in r.get('needles',{}).items():
  p=stage.GetPrimAtPath(n['node']);xf=UsdGeom.Xformable(p);op=xf.GetOrderedXformOps()[0];neutral=op.Get();check(name+channel+' neutral parked',near(neutral.ExtractTranslation(),n['parked_translation_m']) and n['parked_translation_m'][2]<0)
  for value in [r['domain'][0],sum(r['domain'])/2,r['domain'][1]]:
   lo,hi=r['domain'];y0,y1=n['scale_y_m'];pos=[n['valid_translation_x_m'],y0+(value-lo)/(hi-lo)*(y1-y0),n['valid_translation_z_m']];matrix=Gf.Matrix4d(1);matrix.SetTranslate(Gf.Vec3d(*pos));op.Set(matrix);cache.Clear();check(name+channel+f' fixed isolated {value}',cache.GetLocalToWorldTransform(fixed)==fixed_before)
   check(name+channel+f' numeric value {value}',near(op.Get().ExtractTranslation(),pos));check(name+channel+f' pointer inside face {value}',abs(pos[1])+.001<r['face_size_m'][1]/2-.010)
  op.Set(neutral);cache.Clear()
 for rowname,row in r.get('rows',{}).items():
  for digit in row['digit_nodes']:
   check(digit+' exists',bool(stage.GetPrimAtPath(digit)))
   for child in row['segment_children']:
    p=stage.GetPrimAtPath(digit+'/'+child);check(str(p.GetPath())+' segment parked',p.IsA(UsdGeom.Mesh) and abs(UsdGeom.Xformable(p).GetLocalTransformation().ExtractTranslation()[2]-r['parked_segment_z_m'])<1e-6)
# Actual shape fronts vs accepted AltitudeRate and neighboring region envelopes.
slot=[.177,.105,.008];fit=[];alt=json.loads((OUT/'evidence/AltitudeRate-mounting.json').read_text());amin=alt['actual_instrument_panel_local_min_m'];amax=alt['actual_instrument_panel_local_max_m']
inv=json.loads((OUT/'evidence/PanelInventory-inventory.json').read_text());panel1=next(p for p in inv['panels'] if p['id']=='Panel1')
for name,b in bounds.items():
 pb=[[b[j][i]+slot[i] for i in range(3)] for j in range(2)]
 gap=[max(amin[i]-pb[1][i],pb[0][i]-amax[i],0) for i in range(2)];check(name+' no AltitudeRate XY overlap',max(gap)>0)
 for other in panel1['slots']:
  if other['id'] in ['Panel1__Propulsion','Panel1__RangeThrust']:continue
  xy=other['pose']['translation_m'];sz=other['envelope_m'];gaps=[max(xy[i]-sz[i]/2-pb[1][i],pb[0][i]-xy[i]-sz[i]/2,0) for i in range(2)];check(name+' no neighboring slot overlap '+other['id'],max(gaps)>0)
 fit.append({'instrument':name,'actual_panel_local_bounds_m':pb,'altitude_rate_xy_separation_m':gap})
checker=UsdUtils.ComplianceChecker(arkit=True);checker.CheckCompliance(str(OUT/'PropulsionInstruments.usdz'));check('ARKit compliance',not checker.GetErrors() and not checker.GetFailedChecks())
bpy.ops.wm.open_mainfile(filepath=str(OUT/'PropulsionInstruments.blend'));bpy.context.view_layer.update()
for o in bpy.data.objects:
 names=[];p=o
 while p is not None:names.append(p.name.split('.')[0]);p=p.parent
 path='/'+'/'.join(reversed(names));p=stage.GetPrimAtPath(path);check(path+' authored path',bool(p));a=cache.GetLocalToWorldTransform(p);check(path+' authored physical transform',max(abs(a[j][i]-o.matrix_world[i][j]) for i in range(4) for j in range(4))<1e-6)
report={'checks':checks,'passed':len(checks),'failed':0,**counts,'bounds_root_m':bounds,'compliance_errors':checker.GetErrors(),'compliance_failed':checker.GetFailedChecks(),'compliance_warnings':checker.GetWarnings(),'physics_values':'NOT VALIDATED; default unavailable'}
(OUT/'validation.json').write_text(json.dumps(report,indent=2)+'\n');(OUT/'mounting-validation.json').write_text(json.dumps({'front_fit':fit,'status':'no overlap with accepted AltitudeRate or other Panel1 slots','limits':'provisional XY envelope only; backing registration overlap, full cabin sightlines and mechanical fit unqualified'},indent=2)+'\n');print('PASS',len(checks),'checks',counts)
