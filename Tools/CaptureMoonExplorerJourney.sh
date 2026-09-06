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
xcrun simctl spawn "$udid" log stream --level=info --predicate 'subsystem == "io.positron.LM"' > "$out/performance.log" 2>&1 &
logger=$!
trap 'kill "$logger" 2>/dev/null || true; wait "$logger" 2>/dev/null || true' EXIT
args=(--lunar-explorer --lunar-explorer-profile --lunar-explorer-profile-label=experience-journey --lunar-explorer-profile-journey)
if [[ ${LUNAR_CAPTURE_REDUCE_MOTION:-0} == 1 ]]; then args+=(--lunar-explorer-profile-reduce-motion); fi
printf '%s\n' "${args[@]}" > "$out/launch-arguments.txt"
launch=$(xcrun simctl launch --terminate-running-process "$udid" io.positron.LM "${args[@]}")
pid=${launch##*: }
printf 'stage\tpid\tsha256\n' > "$out/stages.tsv"
wait_stage() {
    for ((attempt=0; attempt<600; attempt++)); do
        kill -0 "$pid"
        if awk -v pid="$pid" '$6 == pid && /Moon experience stage=failed/ {found=1} END {exit !found}' "$out/performance.log"; then
            echo 'Experience integration failed; see performance.log' >&2
            exit 70
        fi
        if awk -v pid="$pid" -v stage="$1" '$6 == pid && index($0, "Moon experience stage=" stage) {found=1} END {exit !found}' "$out/performance.log"; then return; fi
        sleep 1
    done
    echo "Timed out waiting for $1" >&2
    exit 70
}
for stage in globe selected immersive returned restored; do
    wait_stage "$stage"
    sleep 10
    xcrun simctl io "$udid" screenshot "$out/$stage.png"
    hash=$(shasum -a 256 "$out/$stage.png" | awk '{print $1}')
    printf '%s\t%s\t%s\n' "$stage" "$pid" "$hash" >> "$out/stages.tsv"
done
wait_stage passed
container=$(xcrun simctl get_app_container "$udid" io.positron.LM data)
cp "$container/Documents/MoonExplorerJourney.json" "$out/camera-and-sunlight.json"
