#!/bin/bash
set -euo pipefail
udid=$1
app=$2
out=$3
[[ ! -e "$out" ]] || exit 66
mkdir -p "$out"
xcrun simctl terminate "$udid" io.positron.LM >/dev/null 2>&1 || true
xcrun simctl install "$udid" "$app"
container=$(xcrun simctl get_app_container "$udid" io.positron.LM data)
cache="$container/Library/Caches/LunarElevation-v1"
imagery="$container/Library/Caches/LunarImagery-wac64-r8-box-pyramid-v1"
restore() {
    xcrun simctl terminate "$udid" io.positron.LM >/dev/null 2>&1 || true
    # Reinstallation can rotate the data-container UUID. Resolve it again;
    # the preserved caches must return to the live container, not its old path.
    container=$(xcrun simctl get_app_container "$udid" io.positron.LM data)
    cache="$container/Library/Caches/LunarElevation-v1"
    imagery="$container/Library/Caches/LunarImagery-wac64-r8-box-pyramid-v1"
    mkdir -p "$container/Library/Caches"
    if [[ -d "$imagery" ]]; then mv "$imagery" "$out/imagery-cache-created"; fi
    if [[ -d "$out/imagery-cache-preserved" ]]; then mv "$out/imagery-cache-preserved" "$imagery"; fi
    if [[ -d "$cache" ]]; then mv "$cache" "$out/source-cache-created"; fi
    if [[ -d "$out/source-cache-preserved" ]]; then mv "$out/source-cache-preserved" "$cache"; fi
}
trap restore EXIT
if [[ -d "$cache" ]]; then mv "$cache" "$out/source-cache-preserved"; fi
if [[ -d "$imagery" ]]; then mv "$imagery" "$out/imagery-cache-preserved"; fi
LUNAR_HIGHLAND_DIVE=1 bash Tools/CaptureMoonExplorerJourney.sh "$udid" "$app" "$out"
