#!/bin/bash
# Uses the caller's isolated simulator. Does not change Simulator foreground.
set -euo pipefail
udid=${1:?simulator UDID}
app=${2:?LM.app path}
out=${3:?output directory}
mkdir -p "$out"
xcrun simctl install "$udid" "$app"
for view in front side crew-eye; do
    xcrun simctl launch --terminate-running-process "$udid" io.positron.LM \
        --terminal-descent-cockpit --commander-station-assembly \
        "--assembly-validation-view=$view" > "$out/$view-launch.txt"
    sleep 12
    date -u +%FT%TZ > "$out/$view-time.txt"
    xcrun simctl io "$udid" screenshot "$out/$view.png"
done
# Existing observer/trace harness, with assembly enabled; never fake state/input.
xcrun simctl launch --terminate-running-process "$udid" io.positron.LM \
    --terminal-descent-cockpit --commander-station-assembly \
    --instrument-validation > "$out/instrument-observer-launch.txt"
sleep 12
date -u +%FT%TZ > "$out/instrument-observer-time.txt"
xcrun simctl io "$udid" screenshot "$out/instrument-observer.png"
container=$(xcrun simctl get_app_container "$udid" io.positron.LM data)
cp "$container/Documents/InstrumentValidation.jsonl" "$out/observation.jsonl"
xcrun simctl spawn "$udid" log show --last 3m --style compact \
    --predicate 'subsystem == "io.positron.LM" AND (eventMessage CONTAINS "skeleton" OR eventMessage CONTAINS "DSKY" OR category == "InstrumentValidation")' > "$out/runtime.log"
shasum -a 256 "$app/LM" "$app/LM.debug.dylib" > "$out/app-binary-sha256.txt"
