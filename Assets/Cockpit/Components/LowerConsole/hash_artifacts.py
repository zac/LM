"""Refresh complete owned artifact provenance after successful build/check/review."""
import hashlib,json
from pathlib import Path
D=Path(__file__).resolve().parent
files={str(p.relative_to(D)):{'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'bytes':p.stat().st_size} for p in sorted(D.rglob('*')) if p.is_file() and p.name!='artifacts.json' and '__pycache__' not in p.parts and p.suffix!='.blend1'}
(D/'artifacts.json').write_text(json.dumps({'schema':'lmkit.artifacts.sha256.v1','files':files},indent=2)+'\n')
print('Hashed',len(files),'artifacts')
