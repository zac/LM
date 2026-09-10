"""Refresh neutral control-family resources after accepted authoring changes."""
from pathlib import Path
import shutil
root = Path(__file__).resolve().parents[1]
source = root / "Assets/Cockpit/Components/ControlLibrary"
names = ["MaintainedToggle", "MomentaryToggle", "GuardedSwitch", "RotarySelector", "CircuitBreaker", "Talkback"]
files = [source / (name + ".usdz") for name in names] + [source / "components.json"]
for file in files:
    if file.read_bytes().startswith(b"version https://git-lfs"):
        raise SystemExit("Fetch Git LFS assets before packaging")
for file in files:
    shutil.copyfile(file, root / "Sources/LMKit/Resources/ControlLibrary" / file.name)
