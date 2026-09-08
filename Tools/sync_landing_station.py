"""Package landing-station component assets without changing their authored bytes.

Optional --source-root permits early integration from an isolated worker checkout.
A packaging receipt records hashes; normal publication uses the accepted main tree.
"""
from pathlib import Path
import argparse
import hashlib
import json
import struct
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
COMPONENTS = {
    "AltitudeRate": ("AltitudeRate.usdz", "interface.json"),
    "DescentControls": ("AttitudeMode.usdz", "DescentRate.usdz", "interface.json"),
    "CrossPointer": ("CrossPointer.usdz", "interface.json"),
    "InteriorDetails": ("InteriorDetails.usdz", "interface.json"),
    "BreakerBanks": ("BreakerBanks.usdz", "interface.json"),
    "Timers": ("MissionTimer.usdz", "EventTimer.usdz", "MissionTimerControls.usdz", "EventTimerControls.usdz", "interface.json"),
    "EngineControls": ("EngineButtons.usdz", "LunarContact.usdz", "interface.json"),
    "PropulsionInstruments": ("PropulsionInstruments.usdz", "interface.json"),
    "CautionWarning": ("CautionWarning.usdz", "interface.json"),
}


def checked_payload(path):
    payload = path.read_bytes()
    if payload.startswith(b"version https://git-lfs"):
        raise ValueError(f"Fetch Git LFS data before packaging: {path}")
    if path.suffix == ".json":
        json.loads(payload)
    elif path.suffix == ".usdz":
        with zipfile.ZipFile(path) as archive:
            if not archive.namelist() or archive.testzip() is not None:
                raise ValueError(f"Invalid or empty USDZ: {path}")
            for info in archive.infolist():
                if info.compress_type != zipfile.ZIP_STORED:
                    raise ValueError(f"Compressed USDZ entry: {path}:{info.filename}")
                with path.open("rb") as stream:
                    stream.seek(info.header_offset)
                    header = stream.read(30)
                    name_length, extra_length = struct.unpack_from("<HH", header, 26)
                    if (info.header_offset + 30 + name_length + extra_length) % 64:
                        raise ValueError(f"Unaligned USDZ member: {path}:{info.filename}")
                if info.filename.startswith("/") or ".." in Path(info.filename).parts:
                    raise ValueError(f"Unsafe USDZ member: {path}:{info.filename}")
    return payload


def package(component, source_root):
    source = source_root / "Assets/Cockpit/Components" / component
    destination = ROOT / "Sources/LMKit/Resources" / component
    # Validate the complete component before writing any runtime resource.
    payloads = {name: checked_payload(source / name) for name in COMPONENTS[component]}
    receipt = {
        "schema": "lmkit.component-packaging.v1",
        "component": component,
        "derivation": "byte-identical copy of accepted authoring resources",
        "files": {name: {"sha256": hashlib.sha256(payload).hexdigest(), "bytes": len(payload)}
                  for name, payload in payloads.items()},
    }
    destination.mkdir(parents=True, exist_ok=True)
    for name, payload in payloads.items():
        with tempfile.NamedTemporaryFile(dir=destination, delete=False) as temp:
            temp.write(payload)
            temp_path = Path(temp.name)
        temp_path.replace(destination / name)
    (destination / "packaging.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print(f"Packaged {component}: {len(payloads)} byte-identical resources")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("components", choices=list(COMPONENTS), nargs="+")
    parser.add_argument("--source-root", type=Path, default=ROOT)
    args = parser.parse_args()
    for component in args.components:
        package(component, args.source_root.resolve())


if __name__ == "__main__":
    main()
