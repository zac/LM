"""Refresh the neutral FDAI shipping resource after accepted authoring changes."""
from pathlib import Path
import shutil
root = Path(__file__).resolve().parents[1]
source = root / "Assets/Cockpit/Components/FDAI/FDAI.usdz"
if source.read_bytes().startswith(b"version https://git-lfs"):
    raise SystemExit("Fetch Git LFS assets before packaging")
shutil.copyfile(source, root / "Sources/LMKit/Resources/FDAI/FDAI.usdz")
