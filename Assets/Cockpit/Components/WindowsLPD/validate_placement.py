"""Check frozen non-LPD geometry plus actual exported paired artwork rays.
Run Blender --background --python validate_placement.py [-- --baseline OLD.usdz]
The committed baseline fingerprints allow later standalone regression runs.
"""
from pxr import Usd,UsdGeom,Gf
from pathlib import Path
import hashlib,json,math,sys
OUT=Path(__file__).resolve().parent
EVIDENCE=OUT/'evidence/placement-v1-fingerprints.json'
def frozen(stage):
 result={}
 for p in stage.Traverse():
  if '/LPD_' in str(p.GetPath()):continue
  attrs={a.GetName():str(a.Get()) for a in p.GetAttributes()}
  attrs['relationships']={r.GetName():list(map(str,r.GetTargets())) for r in p.GetRelationships()}
  result[str(p.GetPath())]=hashlib.sha256(json.dumps(attrs,sort_keys=True).encode()).hexdigest()
 return result
if '--baseline' in sys.argv:
 old=Path(sys.argv[sys.argv.index('--baseline')+1]);oldstage=Usd.Stage.Open(str(old))
 EVIDENCE.write_text(json.dumps({'sha256':hashlib.sha256(old.read_bytes()).hexdigest(),'non_lpd_prims':frozen(oldstage)},indent=2)+'\n')
base=json.loads(EVIDENCE.read_text());s=Usd.Stage.Open(str(OUT/'WindowsLPD.usdz'));actual=frozen(s)
assert actual==base['non_lpd_prims'],'Non-LPD geometry, datum, material or relationships changed'
c=json.loads((OUT/'interface-v1.json').read_text());eye=Gf.Vec3d(*c['eyes']['CDR']);cache=UsdGeom.XformCache()
def points(p):
 m=cache.GetLocalToWorldTransform(p);return [m.Transform(Gf.Vec3d(v)) for v in UsdGeom.Mesh(p).GetPointsAttr().Get()]
max_angle=0;vertices=0
for p in s.Traverse():
 path=str(p.GetPath())
 if '/LPD_Inner/' not in path or not p.IsA(UsdGeom.Mesh):continue
 peer=s.GetPrimAtPath(path.replace('CDR_Window_Inner','CDR_Window_Outer').replace('LPD_Inner','LPD_Outer').replace('/Inner_','/Outer_'))
 assert peer and peer.IsA(UsdGeom.Mesh),path
 a,b=points(p),points(peer);assert len(a)==len(b)
 for pa,pb in zip(a,b):
  da=(pa-eye).GetNormalized();db=(pb-eye).GetNormalized();angle=math.degrees(math.atan2(Gf.Cross(da,db).GetLength(),Gf.Dot(da,db)));max_angle=max(max_angle,angle);vertices+=1
assert max_angle<.005,max_angle
# Geometric center of each actual elevation tick must follow its degree ray.
errors=[]
for e in range(0,61,2):
 p=s.GetPrimAtPath('/WindowsLPD/CDR_FlightWindow/CDR_Window_Inner/LPD_Inner/Inner_Elevation_%02d'%e)
 pts=points(p);center=sum(pts,Gf.Vec3d())/len(pts);d=(center-eye).GetNormalized()
 elev=math.degrees(math.atan2(-d[1],-d[2]));heading=math.degrees(math.atan2(d[0],-d[2]));errors.append({'label':e,'elevation_deg':elev,'heading_deg':heading})
assert max(abs(e['elevation_deg']-e['label']) for e in errors)<.03
assert max(abs(e['heading_deg']) for e in errors)<.03
report={'non_lpd_prims_unchanged':len(actual),'baseline_sha256':base['sha256'],'asset_sha256':hashlib.sha256((OUT/'WindowsLPD.usdz').read_bytes()).hexdigest(),'corresponding_artwork_vertices':vertices,'maximum_pair_ray_difference_deg':max_angle,'elevation_tick_centers':errors,'frozen_datum_spine_check':'PASS; mathematical consistency only, not surveyed flight optics','crossbar_azimuth_qualification':'visual spacing only; not angular targeting','limits':['No native/stereo/headset acceptance','Frozen original eye and panes remain provisional','Text physical size and ink remain approximate']}
(OUT/'placement-validation.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({k:v for k,v in report.items() if k!='elevation_tick_centers'},indent=2))
