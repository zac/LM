#!/usr/bin/env python3
"""Summarize PID-scoped terrain phases and cold/settled frame windows.

Phase durations overlap, so their sums are CPU/work attribution, not total
generation latency. Late settled windows end at least 85 seconds after the last
ready event, retaining the final five-second window before a 90-second capture.
No frame-rate or visual acceptance is inferred from this report.
"""
import argparse
import datetime as dt
import json
import re
from collections import defaultdict
from pathlib import Path


def summarize(path):
    runs = defaultdict(lambda: {"phases": defaultdict(list), "frames": [], "ready": [], "memory": []})
    for line in path.read_text().splitlines():
        parts = line.split()
        if len(parts) < 8 or not parts[5].isdigit():
            continue
        try:
            time = dt.datetime.strptime(parts[0] + "T" + parts[1], "%Y-%m-%dT%H:%M:%S.%f%z").timestamp()
        except ValueError:
            continue
        run = runs[int(parts[5])]
        memory = re.search(r"Terrain memory phase=(\S+) physical=(\d+) peak=(\d+) metal=(\d+) resources=(\d+)", line)
        if memory:
            run["memory"].append(dict(time=time, phase=memory[1],
                **{key: int(memory[index]) / 1048576 for index, key in enumerate(
                    ["physicalMiB", "lifetimePeakMiB", "metalAllocatedMiB", "resourceMiB"], start=2)}))
        phase = re.search(r"Terrain phase end=(\S+) elapsed=([\d.]+)ms main=(\w+)", line)
        if phase:
            run["phases"][phase[1] + ("/main" if phase[3] == "true" else "/worker")].append(float(phase[2]))
        ready = re.search(r"Global terrain ready tiles=(\d+) generation=(\d+)ms", line)
        if ready:
            run["ready"].append({"time": time, "tiles": int(ready[1]), "milliseconds": int(ready[2])})
        frame = re.search(r"Explorer performance preset=(\S+).*p95=([\d.]+)ms p99=([\d.]+)ms max=([\d.]+)ms.*missed=(\d+) physical=([\d.]+)MiB", line)
        if frame:
            run["label"] = frame[1]
            run["frames"].append(dict(time=time, p95=float(frame[2]), p99=float(frame[3]), maximum=float(frame[4]), missed=int(frame[5]), physical=float(frame[6])))
    result = {}
    for pid, run in runs.items():
        if not run["frames"]:
            continue
        def frames(values):
            if not values:
                return None
            return {"windows": len(values), "maxP95MS": max(v["p95"] for v in values),
                    "maxP99MS": max(v["p99"] for v in values), "maxFrameMS": max(v["maximum"] for v in values),
                    "missed": sum(v["missed"] for v in values), "peakMiB": max(v["physical"] for v in values)}
        ready_time = run["ready"][-1]["time"] if run["ready"] else float("inf")
        result[pid] = {"label": run.get("label"), "generations": run["ready"],
                       "phases": {name: {"count": len(v), "totalMS": sum(v), "maxMS": max(v)} for name, v in run["phases"].items()},
                       "wholeRun": frames(run["frames"]),
                       "settled": frames([v for v in run["frames"] if v["time"] >= ready_time + 85])}
        if run["memory"]:
            result[pid]["memory"] = {
                "lifetimePeakMiB": max(v["lifetimePeakMiB"] for v in run["memory"]),
                "maxMetalAllocatedMiB": max(v["metalAllocatedMiB"] for v in run["memory"]),
                "samples": run["memory"],
            }
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path)
    args = parser.parse_args()
    print(json.dumps(summarize(args.log), indent=2))
