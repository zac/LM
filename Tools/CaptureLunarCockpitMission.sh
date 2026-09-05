#!/usr/bin/env bash
# Capture the actual cockpit flight, using AGC state to label each stop.
set -euo pipefail
if [[ $# != 4 ]]; then
    echo "usage: $0 <simulator-udid> <LM.app> <lat,lon> <output-directory>" >&2
    exit 64
fi
udid=$1
app=$2
coordinate=$3
out=$4
mkdir -p "$out"
date -u +%FT%TZ > "$out/started-at.txt"
xcrun simctl install "$udid" "$app"
xcrun simctl terminate "$udid" io.positron.LM 2>/dev/null || true
container=$(xcrun simctl get_app_container "$udid" io.positron.LM data)
latest="$container/Documents/CockpitMissionLatest.json"
recording="$container/Documents/CockpitMissionRecording.json"
# Only these capture artifacts are replaced; other app documents are retained.
rm -f "$latest" "$recording"
xcrun simctl spawn "$udid" log stream --level=info \
    --predicate 'subsystem == "io.positron.LM"' > "$out/performance.log" 2>&1 &
log_pid=$!
trap 'kill "$log_pid" 2>/dev/null || true; wait "$log_pid" 2>/dev/null || true' EXIT
diagnostics=(--cockpit-mission-capture)
if [[ ${LUNAR_CAPTURE_TERRAIN_RAYS:-0} == 1 ]]; then diagnostics+=(--cockpit-terrain-rays); fi
printf '%s\n' --terminal-descent-cockpit "--cockpit-coordinate=$coordinate" \
    --lunar-explorer-profile "--lunar-explorer-profile-label=cockpit-$coordinate" \
    "${diagnostics[@]}" > "$out/launch-arguments.txt"
launch=$(xcrun simctl launch --terminate-running-process "$udid" io.positron.LM \
    --terminal-descent-cockpit "--cockpit-coordinate=$coordinate" \
    --lunar-explorer-profile "--lunar-explorer-profile-label=cockpit-$coordinate" "${diagnostics[@]}")
app_pid=${launch##*: }
echo "$app_pid" > "$out/app-pid.txt"
shasum -a 256 "$app/LM" > "$out/binary-sha256.txt"
for ((attempt=0; attempt<1200; attempt++)); do
    kill -0 "$app_pid"
    if [[ -f "$latest" ]]; then
        cp "$latest" "$out/latest.json"
        phases=$(python3 - "$out/latest.json" <<'PY'
import json,sys
s=json.load(open(sys.argv[1])); h=s['altitudeMeters']
if s['outcome'] != 'inFlight':
    print(s['outcome'])
else:
    if s['program'] in (63,64,65,66): print('P'+str(s['program']))
    for threshold in (250,60,10):
        if h < threshold: print('below-'+str(threshold)+'m')
PY
)
        for phase in $phases; do
        if [[ ! -f "$out/$phase.png" ]]; then
            cp "$latest" "$out/$phase-before.json"
            date -u +%FT%TZ > "$out/$phase-screenshot-started-at.txt"
            xcrun simctl io "$udid" screenshot "$out/$phase.png"
            date -u +%FT%TZ > "$out/$phase-screenshot-completed-at.txt"
            cp "$latest" "$out/$phase.json"
        fi
        done
        if [[ -f "$recording" ]]; then
            # A screenshot can block while flight continues. Refresh terminal
            # status instead of leaving the pre-screenshot in-flight report.
            cp "$latest" "$out/latest.json"
            cp "$recording" "$out/recording.json"
            outcome=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["outcome"])' "$out/latest.json")
            if [[ "$outcome" == inFlight ]]; then
                echo 'Recording exists without a terminal status; retrying.' >&2
                sleep 2
                continue
            fi
            if [[ ! -f "$out/$outcome.png" ]]; then
                xcrun simctl io "$udid" screenshot "$out/$outcome.png"
                cp "$out/latest.json" "$out/$outcome.json"
            fi
            sleep 5
            xcrun simctl io "$udid" screenshot "$out/settled.png"
            shasum -a 256 "$out"/*.png > "$out/capture-hashes.txt"
            date -u +%FT%TZ > "$out/completed-at.txt"
            exit 0
        fi
    fi
    sleep 2
done
echo 'Mission did not reach terminal contact within 40 minutes.' >&2
exit 1
