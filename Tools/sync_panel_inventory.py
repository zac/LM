"""Refresh accepted blank panel resources; preserve the replacement gate manifest."""
from pathlib import Path
import json
import shutil

root = Path(__file__).resolve().parents[1]
source = root / "Assets/Cockpit/Components/PanelInventory"
out = root / "Sources/LMKit/Resources/PanelInventory"
asset = source / "PanelInventory.usdz"
if asset.read_bytes().startswith(b"version https://git-lfs"):
    raise SystemExit("Fetch Git LFS assets before packaging")
manifest = json.loads((source / "inventory.json").read_text())
if manifest["schema"] != "lmkit.panel-inventory.v1" or manifest["units"] != "meters":
    raise SystemExit("Unexpected panel inventory contract")
out.mkdir(parents=True, exist_ok=True)
for name in ["PanelInventory.usdz", "inventory.json"]:
    shutil.copyfile(source / name, out / name)
