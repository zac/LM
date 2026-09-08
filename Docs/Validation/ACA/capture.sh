#!/bin/bash
set -euo pipefail
udid=${1:?dedicated simulator UDID}
app=${2:?LM.app path}
out=${3:?output directory}
mkdir -p "$out"
xcrun simctl install "$udid" "$app"
for pose in neutral positive negative; do
    xcrun simctl launch --terminate-running-process "$udid" io.positron.LM \
        --terminal-descent-cockpit --commander-station-assembly \
        "--aca-visual-review=$pose" > "$out/$pose-launch.txt"
    sleep 12
    date -u +%FT%TZ > "$out/$pose-time.txt"
    xcrun simctl io "$udid" screenshot "$out/$pose.png"
done
shasum -a 256 "$app/LM" "$app/LM.debug.dylib" > "$out/app-binary-sha256.txt"
xcrun simctl spawn "$udid" log show --last 3m --style compact \
    --predicate 'subsystem == "io.positron.LM" AND (eventMessage CONTAINS "ACA" OR eventMessage CONTAINS "skeleton")' > "$out/runtime.log"
