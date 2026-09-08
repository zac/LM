"""Refresh optional neutral hand controllers and their proposed interface."""
from pathlib import Path
import shutil
root = Path(__file__).resolve().parents[1]
source = root / "Assets/Cockpit/Components/HandControllers"
files = [source / name for name in ["ACA.usdz", "TTCA.usdz", "interface.json"]]
for file in files:
    if file.read_bytes().startswith(b"version https://git-lfs"):
        raise SystemExit("Fetch Git LFS assets before packaging")
for file in files:
    shutil.copyfile(file, root / "Sources/LMKit/Resources/HandControllers" / file.name)
