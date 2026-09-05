#!/usr/bin/env bash
# Production global clipmaps, pinned source status and >=90 s settled captures.
set -euo pipefail
[[ $# == 4 ]] || { echo "usage: $0 <udid> <LM.app> <lat,lon> <fresh-output-directory>" >&2; exit 64; }
udid=$1
app=$2
coordinate=$3
out=$4
[[ -d "$app" && ! -e "$out/captures.tsv" ]] || exit 66
mkdir -p "$out"
command -v magick >/dev/null
xcrun simctl boot "$udid" 2>/dev/null || true
xcrun simctl bootstatus "$udid" -b
xcrun simctl install "$udid" "$app"
xcrun simctl spawn "$udid" log stream --level=info \
    --predicate 'subsystem == "io.positron.LM"' > "$out/performance.log" 2>&1 &
logger_pid=$!
cleanup() { kill "$logger_pid" 2>/dev/null || true; wait "$logger_pid" 2>/dev/null || true; }
trap cleanup EXIT
printf 'stop\tcoordinate\taltitude_m\twidth_m\tpid\tsha256\n' > "$out/captures.tsv"
args=(--lunar-explorer-capture --lunar-explorer-profile --lunar-explorer-detail=procedural)
args+=("--lunar-explorer-shadows=${LUNAR_CAPTURE_SHADOWS:-on}")
args+=("--lunar-explorer-normal-maps=${LUNAR_CAPTURE_NORMAL_MAPS:-on}")
if [[ ${LUNAR_CAPTURE_TILE_TINT:-0} == 1 ]]; then args+=(--lunar-explorer-tile-tint=id); fi
if [[ ${LUNAR_CAPTURE_REANCHOR:-0} == 1 ]]; then args+=(--lunar-explorer-reanchor-probe); fi
if [[ ${LUNAR_CAPTURE_OFFLINE:-0} == 1 ]]; then args+=(--lunar-explorer-offline); fi
stops=(
    '01-128m|orbit|159999|120000'
    '02-32m|orbit|39999|60000'
    '03-8m|regional|9999|24000'
    '04-2m|approach|2499|4000'
    '05-0.5m|terminal|249|700'
    '06-0.125m|landing|24.5|40'
    '07-surface|surface|2|8'
    '08-crossfade|globe|30000|210000'
)
for spec in "${stops[@]}"; do
    IFS='|' read -r name preset altitude width <<< "$spec"
    filter=${LUNAR_CAPTURE_FILTER:-}
    if [[ -n "$filter" && ",$filter," != *",$name,"* ]]; then continue; fi
    launch=$(xcrun simctl launch --terminate-running-process "$udid" io.positron.LM \
        --lunar-explorer "--lunar-explorer-coordinate=$coordinate" \
        "--lunar-explorer-preset=$preset" "--lunar-explorer-altitude=$altitude" \
        "--lunar-explorer-meters-across=$width" "--lunar-explorer-profile-label=$name" \
        --lunar-globe-texture-tier=wac-global-64ppd "${args[@]}")
    pid=${launch##*: }
    ready=false
    for ((attempt=0; attempt<600; attempt++)); do
        kill -0 "$pid"
        if awk -v pid="$pid" '$6 == pid && /Global terrain ready tiles=/ { found=1 } END { exit !found }' "$out/performance.log"; then
            ready=true; break
        fi
        sleep 1
    done
    [[ "$ready" == true ]] || { echo "Terrain generation timed out: $name" >&2; exit 70; }
    sleep 90
    kill -0 "$pid"
    xcrun simctl io "$udid" screenshot "$out/$name.png"
    saturation=$(magick "$out/$name.png" -colorspace HSL -channel G -separate -format '%[fx:mean]' info:)
    if [[ ${LUNAR_CAPTURE_TILE_TINT:-0} != 1 ]]; then
        awk -v s="$saturation" 'BEGIN { exit !(s <= 0.01) }'
    fi
    hash=$(shasum -a 256 "$out/$name.png" | awk '{print $1}')
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$name" "$coordinate" "$altitude" "$width" "$pid" "$hash" >> "$out/captures.tsv"
    if [[ ${LUNAR_CAPTURE_REANCHOR:-0} == 1 ]]; then
        sleep 110
        kill -0 "$pid"
        awk -v pid="$pid" '$6 == pid && /Reanchor generation=/ { found=1 } END { exit !found }' "$out/performance.log"
        xcrun simctl io "$udid" screenshot "$out/$name-reanchored.png"
    fi
done
