"""Copy the accepted neutral DSKY export into the Swift package resource bundle."""
from pathlib import Path
import shutil
root = Path(__file__).resolve().parents[1]
source = root / "Assets/Cockpit/Components/DSKY/DSKY.usdz"
if source.read_bytes().startswith(b"version https://git-lfs"):
    raise SystemExit("Fetch Git LFS assets before packaging")
shutil.copyfile(source, root / "Sources/LMKit/Resources/DSKY/DSKY.usdz")
