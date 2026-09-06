#!/usr/bin/env python3
"""Summarize accepted Explorer capture PIDs, including navigation soak checkpoints.

Fresh processes are cold app launches, not cold OS/filesystem caches. Phase
durations can include async suspension; they are not main-thread CPU durations.
Returned footprint measures retained residency, not proof of a leak or its absence.
"""
import argparse
import csv
import json
import re
from pathlib import Path

from SummarizeLunarTerrainTiming import summarize


def capture(directory):
    with (directory / "stages.tsv").open() as stream:
        rows = list(csv.DictReader(stream, delimiter="\t"))
    pids = {int(row["pid"]) for row in rows}
    if len(pids) != 1:
        raise ValueError(f"{directory}: expected exactly one accepted capture PID")
    pid = pids.pop()
    log = directory / "performance.log"
    result = summarize(log).get(pid)
    if result is None:
        raise ValueError(f"{directory}: no frame windows for accepted PID {pid}")
    arguments = (directory / "launch-arguments.txt").read_text().splitlines()
    prefix = "--lunar-explorer-profile-soak-cycles="
    expected = next((int(a[len(prefix):]) for a in arguments if a.startswith(prefix)), 0)
    lines = [line for line in log.read_text().splitlines()
             if len(line.split()) > 5 and line.split()[5] == str(pid)]
    passed = any(re.search(r"Moon (experience|browser) stage=passed\b", line) for line in lines)
    # The acknowledged protocol can finish before log-stream output is flushed.
    completion = directory / "completion.txt"
    if completion.exists() and any(a.startswith("--lunar-explorer-profile-capture-token=") for a in arguments):
        passed = completion.read_text() == "passed"
    failed = any("Moon experience stage=failed" in line for line in lines)
    cycles = [int(match[1]) for line in lines
              if (match := re.search(r"Moon experience cycle=(\d+) cameraAndSunlightExact=true", line))]
    samples = result.get("memory", {}).get("samples", [])
    checkpoints = [sample for sample in samples if sample["phase"].startswith("soak-")]
    returned = [sample["physicalMiB"] for sample in checkpoints if sample["phase"].endswith("-returned")]
    expected_phases = {f"soak-{i}-{stage}" for i in range(1, expected + 1)
                       for stage in ("surface", "returned")}
    observed_phases = [sample["phase"] for sample in checkpoints]
    complete = (passed and not failed and cycles == list(range(1, expected + 1))
                and set(observed_phases) == expected_phases
                and len(observed_phases) == len(expected_phases))
    return dict(pid=pid, complete=complete, arguments=arguments, captureStages=[r["stage"] for r in rows],
                expectedCycles=expected, completedCycles=cycles, timing=result,
                soak=dict(checkpoints=checkpoints,
                          returnedFirstMiB=returned[0] if returned else None,
                          returnedLastMiB=returned[-1] if returned else None,
                          returnedDriftMiB=returned[-1] - returned[0] if returned else None))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directories", nargs="+", type=Path)
    args = parser.parse_args()
    results = {str(directory): capture(directory) for directory in args.directories}
    print(json.dumps(results, indent=2))
    raise SystemExit(0 if all(result["complete"] for result in results.values()) else 1)
