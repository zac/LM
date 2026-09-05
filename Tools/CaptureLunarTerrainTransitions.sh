#!/usr/bin/env bash
# Exercise real session requests, cancellation, and whole-generation arrival.
set -euo pipefail
[[ $# == 4 ]] || { echo "usage: $0 <udid> <LM.app> <lat,lon> <fresh-output-directory>" >&2; exit 64; }
udid=$1 app=$2 coordinate=$3 out=$4
hold=${LUNAR_TRANSITION_HOLD_SECONDS:-100}
[[ "$hold" =~ ^[0-9]+$ && "$hold" -ge 5 ]] || exit 64
[[ -d "$app" && ! -e "$out/performance.log" ]] || exit 66
mkdir -p "$out"
command -v ffprobe >/dev/null
xcrun simctl install "$udid" "$app"
xcrun simctl spawn "$udid" log stream --level=info \
    --predicate 'subsystem == "io.positron.LM"' > "$out/performance.log" 2>&1 &
logger_pid=$!
recorder_pid=
cleanup() {
    if [[ -n "$recorder_pid" ]]; then kill -INT "$recorder_pid" 2>/dev/null || true; wait "$recorder_pid" 2>/dev/null || true; fi
    kill "$logger_pid" 2>/dev/null || true
    wait "$logger_pid" 2>/dev/null || true
}
trap cleanup EXIT
arguments=(--lunar-explorer "--lunar-explorer-coordinate=$coordinate" --lunar-explorer-preset=surface
    --lunar-explorer-altitude=2 --lunar-explorer-meters-across=8 --lunar-explorer-detail=procedural
    --lunar-explorer-capture --lunar-explorer-profile --lunar-explorer-transition-probe
    "--lunar-explorer-transition-hold-seconds=$hold"
    "--lunar-explorer-shadows=${LUNAR_CAPTURE_SHADOWS:-on}"
    "--lunar-explorer-normal-maps=${LUNAR_CAPTURE_NORMAL_MAPS:-on}"
    --lunar-globe-texture-tier=wac-global-64ppd)
printf '%s\n' "${arguments[@]}" > "$out/launch-arguments.txt"
shasum -a 256 "$app/LM" > "$out/binary-sha256.txt"
launch=$(xcrun simctl launch --terminate-running-process "$udid" io.positron.LM "${arguments[@]}")
pid=${launch##*: }
wait_for() {
    local pattern=$1 minimum=$2 found=false
    for ((attempt=0; attempt<900; attempt++)); do
        kill -0 "$pid"
        if awk -v pid="$pid" '$6 == pid && /Global terrain failed/ { failed=1 } END { exit !failed }' "$out/performance.log"; then
            echo "Terrain generation failed; see $out/performance.log" >&2; exit 70
        fi
        if awk -v pid="$pid" -v pattern="$pattern" -v minimum="$minimum" \
            '$6 == pid && $0 ~ pattern { n++ } END { exit !(n >= minimum) }' "$out/performance.log"; then
            found=true; break
        fi
        sleep 1
    done
    [[ "$found" == true ]] || { echo "Timed out waiting for $pattern" >&2; exit 70; }
}
wait_for 'Global terrain ready tiles=' 1
sleep "$((hold > 10 ? hold - 10 : 0))"
xcrun simctl io "$udid" screenshot "$out/before.png"
python3 -c 'import time; print(time.time())' > "$out/recording-start.txt"
xcrun simctl io "$udid" recordVideo --codec=h264 "$out/transitions.mov" > "$out/video.log" 2>&1 &
recorder_pid=$!
wait_for 'Transition probe settled' 3
kill -INT "$recorder_pid"
recording_status=0
wait "$recorder_pid" || recording_status=$?
recorder_pid=
[[ "$recording_status" == 0 || "$recording_status" == 130 ]] || exit "$recording_status"
ffprobe -v error -select_streams v:0 -show_entries stream=width,height,duration \
    -of json "$out/transitions.mov" > "$out/video-metadata.json"
xcrun simctl io "$udid" screenshot "$out/after.png"
python3 "$(dirname "$0")/SummarizeLunarTerrainTiming.py" "$out/performance.log" > "$out/metrics.json"
printf 'pid\tcoordinate\thold_seconds\n%s\t%s\t%s\n' "$pid" "$coordinate" "$hold" > "$out/run.tsv"
