"""Capture immutable evidence; optional LM path argument defaults to accepted isolated checkout."""
from pathlib import Path
import json,hashlib,shutil,sys,subprocess
out=Path(__file__).resolve().parent/'evidence'; comp=out.parent.parent
lm=Path(sys.argv[1]) if len(sys.argv)>1 else Path('/Users/zac/.codex/worktrees/591e/LM')
records=[]
def save(source,dest,usage):
 target=out/dest; target.parent.mkdir(parents=True,exist_ok=True); shutil.copyfile(source,target)
 records.append({'snapshot':dest,'original_path':str(source),'sha256':hashlib.sha256(target.read_bytes()).hexdigest(),'bytes':target.stat().st_size,'usage':usage})
for name in ['CommanderStationAssemblyHandoff.md','Validation/CommanderStationAssembly/README.md','Validation/CommanderStationAssembly/observers.json']:
 save(lm/'Docs'/name,'assembly/'+Path(name).name,'Accepted installation context; compatibility evidence, not hardware dimensions')
save(lm/'LM/LMCommanderStationAssembly.swift','assembly/LMCommanderStationAssembly.swift','Read-only source for accepted transforms and disabled geometry')
for name in ['AS11-36-5389HR.jpg','69-H-134.jpg']:
 save(comp/'Cabin/evidence/Docs/Research/LunarModuleInterior/references/images'/name,name,'Full image, no crop. Apollo 11-led qualitative panel/edge relationships only; no photogrammetric measurements')
for part,name in [('DSKY','sources.json'),('DSKY','mount-fit-research.md'),('DSKY','2003956-B.png'),('FDAI','research.md'),('FDAI','sources.json')]:
 save(comp/part/'evidence'/name,part+'/'+name,'Inherited original source provenance; do not promote provisional geometry to flight dimensions')
save(comp/'Cabin/evidence/Docs/Research/LunarModuleInterior/references/images/manifest.json','Cabin-image-manifest.json','Original URL attempts; failed URLs remain recorded')
save(comp/'Cabin/evidence/Docs/Research/LunarModuleInterior/photo-reference-catalog.md','photo-reference-catalog.md','Original scan provenance and source URL mapping')
(out/'provenance.json').write_text(json.dumps({'LM_revision':subprocess.check_output(['git','-C',str(lm),'rev-parse','HEAD'],text=True).strip(),'LMKit_revision':'3ad1a999ff17aea859eaea5750f1c65e66fad673','files':records},indent=2)+'\n')
