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
    for line in (directory / "performance.log").read_text().splitlines():
        parts = line.split()
        if len(parts) < 8 or parts[5] != str(pid) or "Global cache " not in line:
            continue
        for key, value in re.findall(r"(\w+)=(\d+)", line.split("Global cache ", 1)[1]):
            cache[key] = cache.get(key, 0) + int(value)
    latest = json.loads((directory / "latest.json").read_text())
    if latest["outcome"] == "inFlight":
        raise ValueError("Capture has no terminal status; recover or repeat it before summarizing")
    generations = run["generations"]
    report = {
        "directory": str(directory.resolve()), "pid": pid,
        "binarySHA256": (directory / "binary-sha256.txt").read_text().split()[0],
        "outcome": latest["outcome"], "simulationSeconds": latest["timeSeconds"],
        "streaming": latest.get("streaming"), "contact": latest["terrain"],
        "cache": cache or None,
        "generations": {"count": len(generations),
                        "totalSeconds": sum(x["milliseconds"] for x in generations) / 1000,
                        "maximumSeconds": max((x["milliseconds"] for x in generations), default=0) / 1000,
                        "maximumTiles": max((x["tiles"] for x in generations), default=0)},
        "frames": run["wholeRun"],
        "memory": {key: value for key, value in run.get("memory", {}).items() if key != "samples"},
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
