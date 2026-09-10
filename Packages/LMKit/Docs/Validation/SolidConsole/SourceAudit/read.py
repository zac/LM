from pxr import Usd,UsdGeom
from pathlib import Path
import json,hashlib
D=Path('/Users/zac/Projects/personal/lm/LMKit/Assets/Cockpit/Components');out={}
for name in ['FDAI','DSKY','CommanderPanels','PanelInventory']:
 p=D/name/(name+'.usdz');s=Usd.Stage.Open(str(p));cache=UsdGeom.BBoxCache(Usd.TimeCode.Default(),[UsdGeom.Tokens.default_,UsdGeom.Tokens.render]);meshes=[]
 for prim in s.Traverse():
  if prim.IsA(UsdGeom.Mesh):
   b=cache.ComputeWorldBound(prim).ComputeAlignedRange();meshes.append({'path':str(prim.GetPath()),'min':list(b.GetMin()),'max':list(b.GetMax())})
 out[name]={'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'meshes':meshes}
i=json.loads((D/'PanelInventory/inventory.json').read_text());out['panels']=[p for p in i['panels'] if p['id'] in ['Panel1','Panel2','Panel3','Panel4','Panel5']]
Path('/private/tmp/lm-solid-console-audit/bounds.json').write_text(json.dumps(out,indent=2))
