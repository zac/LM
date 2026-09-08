#!/usr/bin/env bash
# Exercises the same fly-to and gear-drop actions as the Explorer panel.
# The app waits for ready terrain plus 100 s before each action; captures wait
# at least 90 s after ready/contact. Video covers the actual fly-to transition.
set -euo pipefail
bundle_id="${LUNAR_BUNDLE_ID:-io.positron.LM}"
[[ $# == 5 ]] || { echo "usage: $0 <udid> <LM.app> <start-lat,lon> <destination-lat,lon> <fresh-output-directory>" >&2; exit 64; }
udid=$1
app=$2
start=$3
destination=$4
out=$5
[[ -d "$app" && ! -e "$out/performance.log" ]] || exit 66
mkdir -p "$out"
xcrun simctl install "$udid" "$app"
xcrun simctl spawn "$udid" log stream --level=info --predicate "subsystem == \"$bundle_id\"" > "$out/performance.log" 2>&1 &
logger_pid=$!
video_pid=
cleanup() {
    if [[ -n "$video_pid" ]]; then kill -INT "$video_pid" 2>/dev/null || true; fi
    kill "$logger_pid" 2>/dev/null || true
}
trap cleanup EXIT
launch=$(xcrun simctl launch --terminate-running-process "$udid" "$bundle_id" --lunar-explorer "--lunar-explorer-coordinate=$start" --lunar-explorer-preset=surface --lunar-explorer-meters-across=30 --lunar-explorer-capture --lunar-explorer-detail=procedural "--lunar-explorer-fly-to=$destination" --lunar-explorer-contact-probe --lunar-explorer-profile --lunar-explorer-profile-label=navigation --lunar-globe-texture-tier=wac-global-64ppd)
pid=${launch##*: }
echo "$pid" > "$out/pid"
for ((i=0;i<600;i++)); do
 kill -0 "$pid"
 if awk -v pid="$pid" '$6==pid && /Global terrain ready/ {found=1} END {exit !found}' "$out/performance.log"; then break; fi
 sleep 1
done
awk -v pid="$pid" '$6==pid && /Global terrain ready/ {found=1} END {exit !found}' "$out/performance.log"
sleep 90
xcrun simctl io "$udid" screenshot "$out/before-flight.png"
xcrun simctl io "$udid" recordVideo --codec=h264 "$out/fly-to.mov" > "$out/video.log" 2>&1 &
video_pid=$!
sleep 35
kill -INT "$video_pid"
wait "$video_pid"
video_pid=
for ((i=0;i<600;i++)); do
 kill -0 "$pid"
 if awk -v pid="$pid" '$6==pid && /Global contact rehearsal: Settled/ {found=1} END {exit !found}' "$out/performance.log"; then break; fi
 sleep 1
done
awk -v pid="$pid" '$6==pid && /Global contact rehearsal: Settled/ {found=1} END {exit !found}' "$out/performance.log"
sleep 90
kill -0 "$pid"
xcrun simctl io "$udid" screenshot "$out/contact.png"
shasum -a 256 "$out/"*.png > "$out/capture-hashes.txt"
kill "$logger_pid"
wait "$logger_pid" || true
trap - EXIT
