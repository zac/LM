"""Derive runtime-visible planning geometry; LM explicitly hides its group on install.

Authoring USD stays hidden for neutral previews. RealityKit retains its text meshes
but does not undo inherited USD invisibility when the app toggles isEnabled.
Only this one visibility opinion changes in the runtime layer. Requires usdcat.
"""
from pathlib import Path
import hashlib
import json
import re
import shutil
import struct
import subprocess
import tempfile
import zipfile

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
with tempfile.TemporaryDirectory(prefix="lmkit-panel-package-") as temporary:
    temp = Path(temporary)
    layer = temp / "PanelInventory.usda"
    crate = temp / "PanelInventory.usdc"
    subprocess.run(["usdcat", str(asset), "-o", str(layer)], check=True)
    original = layer.read_text()
    pattern = r'(def Xform "PlanningLabels"\s*\{\s*token visibility = )"invisible"'
    runtime, count = re.subn(pattern, r'\1"inherited"', original)
    if count != 1 or original.count('token visibility = "invisible"') != 1:
        raise SystemExit("Expected exactly one authored hidden planning group")
    layer.write_text(runtime)
    subprocess.run(["usdcat", str(layer), "-o", str(crate)], check=True)
    verified = subprocess.check_output(["usdcat", str(crate)], text=True)
    if verified != runtime:
        raise SystemExit("Runtime USD round trip altered more than planning visibility")
    # One uncompressed crate, deterministic timestamp and 64-byte-aligned data.
    item = zipfile.ZipInfo(crate.name, date_time=(1980, 1, 1, 0, 0, 0))
    padding = (-(30 + len(item.filename.encode("utf-8")))) % 64
    if padding < 4:
        padding += 64
    item.extra = struct.pack("<HH", 0xFFFF, padding - 4) + bytes(padding - 4)
    with zipfile.ZipFile(out / asset.name, "w", compression=zipfile.ZIP_STORED) as archive:
        archive.writestr(item, crate.read_bytes())
    receipt = {
        "source_sha256": hashlib.sha256(asset.read_bytes()).hexdigest(),
        "runtime_sha256": hashlib.sha256((out / asset.name).read_bytes()).hexdigest(),
        "changed_property": "/PanelInventory/PlanningLabels.visibility",
        "source_value": "invisible", "runtime_value": "inherited",
        "canonical_source_layer_sha256": hashlib.sha256(original.encode()).hexdigest(),
        "canonical_runtime_layer_sha256": hashlib.sha256(runtime.encode()).hexdigest(),
        "other_layer_text_unchanged": True,
        "consumer_requirement": "Set PlanningLabels.isEnabled=false before installation; explicitly toggle it for planning mode."
    }
    (out / "packaging.json").write_text(json.dumps(receipt, indent=2) + "\n")
shutil.copyfile(source / "inventory.json", out / "inventory.json")
