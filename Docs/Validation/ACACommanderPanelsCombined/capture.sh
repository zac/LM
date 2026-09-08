#!/bin/bash
set -euo pipefail
udid=6EB2B257-9EFE-4CEB-A64A-5EF0086FFF85
app=/tmp/lm-aca-panels-verification/build/Build/Products/Debug-xrsimulator/LM.app
out=/tmp/lm-aca-panels-verification/evidence
xcrun simctl install "$udid" "$app"
for view in front side crew-eye; do
 xcrun simctl launch --terminate-running-process "$udid" io.positron.LM --terminal-descent-cockpit --commander-station-assembly "--assembly-validation-view=$view" > "$out/$view-launch.txt"
 sleep 12
 date -u +%FT%TZ > "$out/$view-time.txt"
 xcrun simctl io "$udid" screenshot "$out/$view.png"
done
for pose in neutral positive negative; do
 xcrun simctl launch --terminate-running-process "$udid" io.positron.LM --terminal-descent-cockpit --commander-station-assembly "--aca-visual-review=$pose" > "$out/aca-$pose-launch.txt"
 sleep 12
 date -u +%FT%TZ > "$out/aca-$pose-time.txt"
 xcrun simctl io "$udid" screenshot "$out/aca-$pose.png"
done
shasum -a 256 "$app/LM" "$app/LM.debug.dylib" > "$out/app-binary-sha256.txt"
xcrun simctl spawn "$udid" log show --last 5m --style compact --predicate 'subsystem == "io.positron.LM" AND (eventMessage CONTAINS "ACA" OR eventMessage CONTAINS "skeleton" OR eventMessage CONTAINS "DSKY")' > "$out/runtime.log"
