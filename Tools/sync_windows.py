"""Package accepted window geometry and its unmodified interface manifests."""
from pathlib import Path
import json
import shutil

root = Path(__file__).resolve().parents[1]
source = root / "Assets/Cockpit/Components/WindowsLPD"
out = root / "Sources/LMKit/Resources/WindowsLPD"
asset = source / "WindowsLPD.usdz"
if asset.read_bytes().startswith(b"version https://git-lfs"):
    raise SystemExit("Fetch Git LFS assets before packaging")
contract = json.loads((source / "interface-v1.json").read_text())
if contract["root"] != "/WindowsLPD" or contract["units"] != "meters":
    raise SystemExit("Unexpected window resource contract")
out.mkdir(parents=True, exist_ok=True)
for name in (asset.name, "interface-v1.json", "manifest.json"):
    shutil.copyfile(source / name, out / name)
