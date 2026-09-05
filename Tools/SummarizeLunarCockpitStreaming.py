#!/usr/bin/env python3
"""Summarize one captured cockpit mission without treating a crash as acceptance."""
import argparse
import datetime as dt
import json
import re
from pathlib import Path

from SummarizeLunarTerrainTiming import summarize


def mission(directory):
    timing = summarize(directory / "performance.log")
    pid_file = directory / "app-pid.txt"
    if pid_file.exists():
        pid = int(pid_file.read_text())
    elif len(timing) == 1:
        pid = next(iter(timing))
    else:
        raise ValueError("Capture needs an unambiguous app PID")
    run = timing[pid]
    cache = {}
    morphs = []
    for line in (directory / "performance.log").read_text().splitlines():
        parts = line.split()
        if len(parts) < 8 or parts[5] != str(pid):
            continue
        morph = re.search(r"Global morph begin tiles=(\d+) dynamic=(\d+) appearance=(\d+)", line)
        if morph:
            morphs.append(tuple(map(int, morph.groups())))
        if "Global cache " not in line:
            continue
        for key, value in re.findall(r"(\w+)=(\d+)", line.split("Global cache ", 1)[1]):
            cache[key] = cache.get(key, 0) + int(value)
    latest = json.loads((directory / "latest.json").read_text())
    if latest["outcome"] == "inFlight":
        raise ValueError("Capture has no terminal status; recover or repeat it before summarizing")
    generations = run["generations"]
    resource_peaks = {}
    for sample in run.get("memory", {}).get("samples", []):
        if sample["resourceMiB"]:
            resource_peaks[sample["phase"]] = max(resource_peaks.get(sample["phase"], 0), sample["resourceMiB"])
    report = {
        "directory": str(directory.resolve()), "pid": pid,
        "binarySHA256": (directory / "binary-sha256.txt").read_text().split()[0],
        "outcome": latest["outcome"], "simulationSeconds": latest["timeSeconds"],
        "streaming": latest.get("streaming"), "contact": latest["terrain"],
        "touchdown": {key: latest.get(key) for key in (
            "contactVerticalSpeed", "contactHorizontalSpeed", "contactTiltDegrees",
            "contactSurfaceNormalSiteENU", "contactSurfaceSlopeToSiteUpDegrees")},
        "cache": cache or None,
        "morphs": {"count": len(morphs),
                   "maximumTiles": max((m[0] for m in morphs), default=0),
                   "maximumDynamicMeshes": max((m[1] for m in morphs), default=0),
                   "maximumAppearancePairs": max((m[2] for m in morphs), default=0)},
        "generations": {"count": len(generations),
                        "totalSeconds": sum(x["milliseconds"] for x in generations) / 1000,
                        "maximumSeconds": max((x["milliseconds"] for x in generations), default=0) / 1000,
                        "maximumTiles": max((x["tiles"] for x in generations), default=0)},
        "frames": run["wholeRun"],
        "memory": {key: value for key, value in run.get("memory", {}).items() if key != "samples"},
        # Phase peaks need not coincide and can refer to retained/shared data.
        # Do not sum them or interpret logical payload as driver allocation.
        "logicalResourcePeaksMiB": resource_peaks or None,
        "phases": run["phases"],
    }
    if all((directory / name).exists() for name in ["started-at.txt", "completed-at.txt"]):
        start, end = [dt.datetime.fromisoformat((directory / name).read_text().strip().replace("Z", "+00:00"))
                      for name in ["started-at.txt", "completed-at.txt"]]
        report["captureWallSeconds"] = (end - start).total_seconds()
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    print(json.dumps(mission(parser.parse_args().directory), indent=2))
