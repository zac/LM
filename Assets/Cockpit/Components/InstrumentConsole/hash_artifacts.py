"""Pin owned delivery bytes. Run after building, validating or editing evidence."""
from pathlib import Path
import hashlib,json
root=Path(__file__).resolve().parent
files={str(p.relative_to(root)):{'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in sorted(root.rglob('*')) if p.is_file() and p.name!='artifacts.sha256.json' and '__pycache__' not in p.parts}
(root/'artifacts.sha256.json').write_text(json.dumps({'algorithm':'sha256','files':files},indent=2)+'\n')
print(f'Pinned {len(files)} owned files')
