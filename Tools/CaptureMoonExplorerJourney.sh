#!/usr/bin/env bash
# Product-state integration captures; desktop gestures remain a separate check.
set -euo pipefail
[[ $# == 3 ]] || { echo 'usage: CaptureMoonExplorerJourney.sh <udid> <LM.app> <fresh-output-directory>' >&2; exit 64; }
udid=$1
app=$2
out=$3
[[ -d "$app" && ! -e "$out/stages.tsv" ]] || exit 66
mkdir -p "$out"
xcrun simctl bootstatus "$udid" -b
xcrun simctl install "$udid" "$app"
container=$(xcrun simctl get_app_container "$udid" io.positron.LM data)
token=$(uuidgen)
stage_file="$container/Documents/MoonExplorerJourney-$token-stage.txt"
ack_file="$container/Documents/MoonExplorerJourney-$token-ack.txt"
xcrun simctl spawn "$udid" log stream --level=info --predicate 'subsystem == "io.positron.LM"' > "$out/performance.log" 2>&1 &
logger=$!
trap 'kill "$logger" 2>/dev/null || true; wait "$logger" 2>/dev/null || true; rm -f "$stage_file" "$ack_file"' EXIT
args=(--lunar-explorer --lunar-explorer-profile --lunar-explorer-profile-label=experience-journey --lunar-explorer-profile-journey "--lunar-explorer-profile-capture-token=$token")
stages=(globe selected immersive returned restored)
if [[ ${LUNAR_HIGHLAND_DIVE:-0} == 1 ]]; then
    args+=(--lunar-explorer-profile-highland-dive)
    stages=(highland-disk highland-arrival highland-overlap highland-regional highland-settled)
fi
if [[ ${LUNAR_ONE_ZOOM:-0} == 1 ]]; then
    args+=(--lunar-explorer-profile-one-zoom)
    stages=(disk clipped crossfade handoff terrain immersion return)
    if [[ ${LUNAR_GESTURE_PROBE:-0} == 1 ]]; then
        args+=(--lunar-explorer-profile-gestures)
        stages+=(pinch-start pinch-end pan-before pan-after)
        if [[ ${LUNAR_GESTURES_ONLY:-0} == 1 ]]; then
            args+=(--lunar-explorer-profile-gestures-only)
            stages=(pinch-start pinch-end pan-before pan-after)
        fi
    fi
fi
cycles=${LUNAR_PROFILE_SOAK_CYCLES:-0}
[[ "$cycles" =~ ^[0-9]+$ && "$cycles" -le 20 ]] || exit 64
if [[ "$cycles" -gt 0 ]]; then args+=("--lunar-explorer-profile-soak-cycles=$cycles"); fi
if [[ ${LUNAR_CAPTURE_REDUCE_MOTION:-0} == 1 ]]; then args+=(--lunar-explorer-profile-reduce-motion); fi
printf '%s\n' "${args[@]}" > "$out/launch-arguments.txt"
launch=$(xcrun simctl launch --terminate-running-process "$udid" io.positron.LM "${args[@]}")
pid=${launch##*: }
printf 'stage\tpid\tsha256\n' > "$out/stages.tsv"
wait_stage() {
    for ((attempt=0; attempt<600 + cycles * 90; attempt++)); do
        kill -0 "$pid"
        if awk -v pid="$pid" '$6 == pid && /Moon experience stage=failed/ {found=1} END {exit !found}' "$out/performance.log"; then
            echo 'Experience integration failed; see performance.log' >&2
            exit 70
        fi
        if [[ -f "$stage_file" && $(cat "$stage_file") == "$1" ]]; then return; fi
        if [[ "$attempt" == 60 ]]; then
            sample "$pid" 5 -file "$out/$1-over-60s.sample.txt" >/dev/null 2>&1 || true
        fi
        sleep 1
    done
    echo "Timed out waiting for $1" >&2
    exit 70
}
for stage in "${stages[@]}"; do
    wait_stage "$stage"
    sleep 10
    xcrun simctl io "$udid" screenshot "$out/$stage.png"
    [[ $(cat "$stage_file") == "$stage" ]] || { echo 'Capture stage changed before screenshot finished' >&2; exit 70; }
    hash=$(shasum -a 256 "$out/$stage.png" | awk '{print $1}')
    printf '%s\t%s\t%s\n' "$stage" "$pid" "$hash" >> "$out/stages.tsv"
    printf '%s' "$stage" > "$ack_file"
done
wait_stage passed
cp "$stage_file" "$out/completion.txt"
# Keep the logger alive until its buffered final checkpoint and pass record arrive.
for ((attempt=0; attempt<90; attempt++)); do
    kill -0 "$pid"
    if awk -v pid="$pid" '$6 == pid && /Moon experience stage=passed/ {found=1} END {exit !found}' "$out/performance.log"; then break; fi
    sleep 1
done
awk -v pid="$pid" '$6 == pid && /Moon experience stage=passed/ {found=1} END {exit !found}' "$out/performance.log"
container=$(xcrun simctl get_app_container "$udid" io.positron.LM data)
if [[ ${LUNAR_ONE_ZOOM:-0} != 1 && ${LUNAR_HIGHLAND_DIVE:-0} != 1 ]]; then
    cp "$container/Documents/MoonExplorerJourney.json" "$out/camera-and-sunlight.json"
fi
