"""Copy the exact consulted sources, preserving hashes and source revision."""
from pathlib import Path
import json,hashlib,shutil,subprocess
OUT=Path(__file__).resolve().parent/'evidence'
SRC=Path('/Users/zac/.codex/worktrees/591e/LM')
paths=['Docs/CommanderWindowCalibration.md','LM/LMCommanderStationGeometry.swift','LM/LMLandingPointDesignator.swift']
base='Docs/Research/LunarModuleInterior/'
paths += [base+p for p in ['geometry-materials-and-evidence.md','measurements.csv','controls-and-panels.md','photo-reference-catalog.md','references/manifest.json','references/images/manifest.json','references/images/69-H-134.jpg','references/images/AS11-36-5389HR.jpg','references/images/LM11-co42.jpg','references/documents/grumman-1967-crew-station-excerpt.pdf','references/documents/19730023038-spacecraft-windows.pdf']]
rows=[]
for p in paths:
 src=SRC/p; dst=OUT/p; dst.parent.mkdir(parents=True,exist_ok=True); shutil.copyfile(src,dst)
 rows.append(dict(path=p,bytes=src.stat().st_size,sha256=hashlib.sha256(src.read_bytes()).hexdigest()))
(OUT/'sources.json').write_text(json.dumps(dict(repository='zac/LM',revision=subprocess.check_output(['git','-C',str(SRC),'rev-parse','HEAD'],text=True).strip(),files=rows),indent=2)+'\n')
