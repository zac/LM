#!/usr/bin/env bash
# Verify a real streamed source, persistent offline reuse, and the global base.
set -euo pipefail
bundle_id="${LUNAR_BUNDLE_ID:-io.positron.LM}"
if [[ $# -lt 2 || $# -gt 3 ]]; then
    echo "usage: $0 <simulator-udid> <LM.app> [output-directory]" >&2
    exit 64
fi
udid=$1
app_path=$2
out=${3:-/tmp/LM-Stage2-Elevation-Live}
[[ -d "$app_path" ]] || exit 66
command -v magick >/dev/null
mkdir -p "$out"
[[ ! -e "$out/captures.tsv" && ! -e "$out/original-cache" ]] || {
    echo "Use a fresh capture directory" >&2; exit 73;
}
xcrun simctl boot "$udid" 2>/dev/null || true
xcrun simctl bootstatus "$udid" -b
xcrun simctl install "$udid" "$app_path"
xcrun simctl terminate "$udid" "$bundle_id" 2>/dev/null || true
container=$(xcrun simctl get_app_container "$udid" "$bundle_id" data)
cache="$container/Library/Caches/LunarElevation-v1"
log_pid=
cleanup() {
    xcrun simctl terminate "$udid" "$bundle_id" 2>/dev/null || true
    if [[ -n "$log_pid" ]]; then
        kill "$log_pid" 2>/dev/null || true
        wait "$log_pid" 2>/dev/null || true
    fi
    if [[ -d "$cache" ]]; then mv "$cache" "$out/result-cache"; fi
    if [[ -d "$out/original-cache" ]]; then mv "$out/original-cache" "$cache"; fi
}
trap cleanup EXIT
# Preserve any existing app cache and prove this run begins with a cold fetch.
if [[ -d "$cache" ]]; then mv "$cache" "$out/original-cache"; fi
xcrun simctl spawn "$udid" log stream --level=info \
    --predicate "subsystem == \"$bundle_id\"" > "$out/performance.log" 2>&1 &
log_pid=$!
printf 'case\tcoordinate\tpid\tsha256\n' > "$out/captures.tsv"
for spec in 'streamed|0.67,25|online|sldem2015-512-apollo11-slab' \
            'offline|0.67,25|offline|sldem2015-512-apollo11-slab' \
            'global-base|-42,120|offline|lola-ldem-16ppd-global' \
            'cache-miss|0.67,25|offline|lola-ldem-16ppd-global'; do
    IFS='|' read -r name coordinate mode expected_source <<< "$spec"
    if [[ "$name" == cache-miss ]]; then
        xcrun simctl terminate "$udid" "$bundle_id"
        mv "$cache" "$out/verified-cache"
    fi
    args=(--lunar-explorer-capture)
    if [[ "$mode" == offline ]]; then args+=(--lunar-explorer-elevation-offline); fi
    launch=$(xcrun simctl launch --terminate-running-process "$udid" "$bundle_id" \
        --lunar-explorer --lunar-explorer-preset=approach \
        --lunar-explorer-altitude=2000 --lunar-explorer-meters-across=8000 \
        "--lunar-explorer-elevation-preview=$coordinate" \
        --lunar-explorer-profile "--lunar-explorer-profile-label=$name" "${args[@]}")
    app_pid=${launch##*: }
    # A source can take up to 120 seconds to arrive. Begin the visual settle
    # only after this process reports a fully realized elevation mesh.
    ready=false
    for ((attempt=0; attempt<180; attempt++)); do
        kill -0 "$app_pid"
        if awk -v pid="$app_pid" -v source="$expected_source" \
            '$6 == pid && /Elevation preview source=/ && index($0, "source=" source " ") { found=1 } END { exit !found }' \
            "$out/performance.log"; then ready=true; break; fi
        if awk -v pid="$app_pid" '$6 == pid && /Elevation preview failed:/ { found=1 } END { exit !found }' \
            "$out/performance.log"; then exit 70; fi
        sleep 1
    done
    [[ "$ready" == true ]] || { echo "Expected elevation source did not become ready: $expected_source" >&2; exit 70; }
    if [[ "$name" == cache-miss ]]; then
        awk -v pid="$app_pid" '$6 == pid && /fallback=unavailableOffline/ { found=1 } END { exit !found }' \
            "$out/performance.log"
    fi
    sleep 90
    kill -0 "$app_pid"
    xcrun simctl io "$udid" screenshot "$out/$name.png"
    saturation=$(magick "$out/$name.png" -colorspace HSL -channel G -separate -format '%[fx:mean]' info:)
    awk -v s="$saturation" 'BEGIN { exit !(s <= 0.01) }'
    hash=$(shasum -a 256 "$out/$name.png" | awk '{print $1}')
    printf '%s\t%s\t%s\t%s\n' "$name" "$coordinate" "$app_pid" "$hash" >> "$out/captures.tsv"
done
cmp "$out/streamed.png" "$out/offline.png"
echo "Elevation captures and exact offline repeat verified: $out"
