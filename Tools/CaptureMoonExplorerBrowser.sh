#!/usr/bin/env bash
# Opt-in native view-state captures, not synthesized UI taps.
set -euo pipefail
bundle_id="${LUNAR_BUNDLE_ID:-io.positron.LM}"
[[ $# == 3 ]] || { echo 'usage: CaptureMoonExplorerBrowser.sh <udid> <LM.app> <fresh-output-directory>' >&2; exit 64; }
udid=$1
app=$2
out=$3
[[ -d "$app" && ! -e "$out/stages.tsv" ]] || exit 66
mkdir -p "$out"
xcrun simctl bootstatus "$udid" -b
xcrun simctl install "$udid" "$app"
xcrun simctl spawn "$udid" log stream --level=info --predicate "subsystem == \"$bundle_id\"" > "$out/performance.log" 2>&1 &
logger=$!
trap 'kill "$logger" 2>/dev/null || true; wait "$logger" 2>/dev/null || true' EXIT
args=(--lunar-explorer --lunar-explorer-profile --lunar-explorer-profile-browser)
stages=(selected mission saved saved-views settings placement lighting far-side)
if [[ ${LUNAR_BROWSER_CAPTURE_LIGHTING_ONLY:-0} == 1 ]]; then
    args+=(--lunar-explorer-profile-browser-lighting)
    stages=(lighting)
elif [[ ${LUNAR_BROWSER_CAPTURE_SELECTED_ONLY:-0} == 1 ]]; then
    args+=(--lunar-explorer-profile-browser-selected)
    stages=(selected)
elif [[ ${LUNAR_BROWSER_CAPTURE_SEARCH_ONLY:-0} == 1 ]]; then
    args+=(--lunar-explorer-profile-browser-search)
    stages=(search empty coordinate coordinate-selected)
fi
printf '%s\n' "${args[@]}" > "$out/launch-arguments.txt"
launch=$(xcrun simctl launch --terminate-running-process "$udid" "$bundle_id" "${args[@]}")
pid=${launch##*: }
printf 'stage\tpid\tsha256\n' > "$out/stages.tsv"
wait_stage() {
    for ((attempt=0; attempt<300; attempt++)); do
        kill -0 "$pid"
        if awk -v pid="$pid" -v stage="$1" '$6 == pid && index($0, "Moon browser stage=" stage) {found=1} END {exit !found}' "$out/performance.log"; then return; fi
        sleep 1
    done
    echo "Timed out waiting for $1" >&2
    exit 70
}
for stage in "${stages[@]}"; do
    wait_stage "$stage"
    sleep 10
    xcrun simctl io "$udid" screenshot "$out/$stage.png"
    hash=$(shasum -a 256 "$out/$stage.png" | awk '{print $1}')
    printf '%s\t%s\t%s\n' "$stage" "$pid" "$hash" >> "$out/stages.tsv"
done
wait_stage passed
