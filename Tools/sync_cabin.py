"""Refresh enclosed cabin resource and clarify the mounting manifest coordinate space."""
from pathlib import Path
import json, shutil
root = Path(__file__).resolve().parents[1]
source = root / "Assets/Cockpit/Components/Cabin"
out = root / "Sources/LMKit/Resources/Cabin"
asset = source / "Cabin.usdz"
if asset.read_bytes().startswith(b"version https://git-lfs"):
    raise SystemExit("Fetch Git LFS assets before packaging")
manifest = json.loads((source / "mounts.json").read_text())
manifest["coordinate_space"] = "Cabin root; positions and rotations are NOT parent-local, including nested mounts"
manifest["acceptance"] = "enclosed visual foundation; provisional dimensions; instruments/windows/panels assembled separately; no flight or headset qualification"
out.mkdir(parents=True, exist_ok=True)
shutil.copyfile(asset, out / asset.name)
(out / "mounts.json").write_text(json.dumps(manifest, indent=2) + "\n")
for name in ["interface-v2.json", "migration.json"]:
    shutil.copyfile(source / name, out / name)
