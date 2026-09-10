"""Package accepted neutral surrounds without modifying authoring evidence."""
from pathlib import Path
import json
import shutil

root = Path(__file__).resolve().parents[1]
source = root / "Assets/Cockpit/Components/CommanderPanels"
out = root / "Sources/LMKit/Resources/CommanderPanels"
asset = source / "CommanderPanels.usdz"
if asset.read_bytes().startswith(b"version https://git-lfs"):
    raise SystemExit("Fetch Git LFS assets before packaging")
manifest = json.loads((source / "mounting.json").read_text())
if manifest["units"] != "meters" or manifest["root"] != "/CommanderPanels":
    raise SystemExit("Unexpected commander panel mounting contract")
out.mkdir(parents=True, exist_ok=True)
for name in (asset.name, "mounting.json"):
    shutil.copyfile(source / name, out / name)
