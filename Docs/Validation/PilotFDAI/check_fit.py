"""Read-only Blender/USD check of pilot FDAI at the accepted Panel 2 slot.
Usage: blender -b --factory-startup --python-exit-code 1 --python check_fit.py -- RESOURCE_DIR OUTPUT_JSON
Reports mesh surface crossings, not containment or manufacturing clearance.
"""
import hashlib, json, sys
from pathlib import Path
from pxr import Usd, UsdGeom, Gf
from mathutils import Vector
from mathutils.bvhtree import BVHTree
resources, output = map(Path, sys.argv[sys.argv.index('--') + 1:])
files = {name: resources / rel for name, rel in {
    'FDAI': 'FDAI/FDAI.usdz', 'Cabin': 'Cabin/Cabin.usdz',
    'WindowsLPD': 'WindowsLPD/WindowsLPD.usdz',
    'PanelInventory': 'PanelInventory/PanelInventory.usdz',
    'CommanderPanels': 'CommanderPanels/CommanderPanels.usdz'}.items()}
# The runtime explicitly hides these unsupported instrument groups.
unbound = {'FDAI_RollBug_Pivot'} | {f'FDAI_{kind}_{axis}_Pivot' for kind in ('Rate', 'Error') for axis in ('Roll', 'Pitch', 'Yaw')}
stages = {key: Usd.Stage.Open(str(path)) for key, path in files.items()}
cache = UsdGeom.XformCache()
slot_path = '/PanelInventory/Panels/Panel2/Panel2__FDAI'
slot = stages['PanelInventory'].GetPrimAtPath(slot_path)
assert slot
mount = cache.GetLocalToWorldTransform(slot)
def meshes(stage, placement=Gf.Matrix4d(1), skip=lambda p: False):
    result=[]
    for p in stage.Traverse():
        if not p.IsA(UsdGeom.Mesh) or skip(p): continue
        g=UsdGeom.Mesh(p); transform=cache.GetLocalToWorldTransform(p)
        vertices=[Vector(placement.Transform(transform.Transform(Gf.Vec3d(*v)))) for v in g.GetPointsAttr().Get()]
        indices=g.GetFaceVertexIndicesAttr().Get(); faces=[]; start=0
        for count in g.GetFaceVertexCountsAttr().Get(): faces.append(tuple(indices[start:start+count])); start+=count
        lo=Vector(tuple(min(v[i] for v in vertices) for i in range(3))); hi=Vector(tuple(max(v[i] for v in vertices) for i in range(3)))
        result.append((str(p.GetPath()),vertices,faces,lo,hi))
    return result
def skip_instrument(p):return any(a in unbound for a in str(p.GetPath()).split('/'))
def skip_foundation(p):
    path=str(p.GetPath())
    return '/PlanningLabels/' in path or path.startswith(slot_path+'/Placeholder') or any(x in path for x in ['Panel_1_RemovableBacking','Panel_4_RemovableBacking'])
local = meshes(stages['FDAI'], skip=skip_instrument)
pilot = meshes(stages['FDAI'], placement=mount, skip=skip_instrument)
others = [m for name,st in stages.items() if name!='FDAI' for m in meshes(st,skip=skip_foundation)]
collisions=[]
for name,verts,faces,lo,hi in pilot:
    tree=None
    for peer,pv,pf,pl,ph in others:
        if any(lo[i]>ph[i] or hi[i]<pl[i] for i in range(3)):continue
        if tree is None:tree=BVHTree.FromPolygons(verts,faces)
        count=len(tree.overlap(BVHTree.FromPolygons(pv,pf)))
        if count:collisions.append({'pilot':name,'peer':peer,'surface_pairs':count})
def bounds(ms):return [[min(m[3][i] for m in ms) for i in range(3)],[max(m[4][i] for m in ms) for i in range(3)]]
record={'method':'actual USD meshes at Panel2__FDAI identity; disabled runtime groups omitted; surface intersection test does not detect complete containment','resource_sha256':{k:hashlib.sha256(v.read_bytes()).hexdigest() for k,v in files.items()},'slot':slot_path,'slot_cabin_matrix_rows':[list(row) for row in mount], 'local_bounds_m':bounds(local),'cabin_bounds_m':bounds(pilot),'pilot_mesh_count':len(pilot),'foundation_mesh_count':len(others),'surface_crossings':collisions}
output.write_text(json.dumps(record,indent=2)+'\n')
print(json.dumps({k:v for k,v in record.items() if k not in ('slot_cabin_matrix_rows','resource_sha256')},indent=2))
