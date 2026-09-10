"""Record owned delivery hashes after regeneration/validation; not a substitute for validation."""
import hashlib,json
from pathlib import Path
p=Path(__file__).resolve().parent
files=[x for x in p.rglob('*') if x.is_file() and x.name not in ('artifact-hashes.json',) and '__pycache__' not in x.parts]
report={str(x.relative_to(p)):{'sha256':hashlib.sha256(x.read_bytes()).hexdigest(),'bytes':x.stat().st_size} for x in sorted(files)}
(p/'artifact-hashes.json').write_text(json.dumps(report,indent=2)+'\n')
print('HASHED',len(report),'artifacts')
