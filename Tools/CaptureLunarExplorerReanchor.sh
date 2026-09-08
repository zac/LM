#!/usr/bin/env bash
# Hold one settled view across the production re-anchor trigger. The capture
# probe starts in an ENU 4.2 km from the focus and releases it after 100 seconds.
set -euo pipefail
bundle_id="${LUNAR_BUNDLE_ID:-io.positron.LM}"
if [[ $# -lt 2 || $# -gt 3 ]]; then
    echo "usage: $0 <simulator-udid> <LM.app> [output-directory]" >&2
    exit 64
fi
udid=$1
app_path=$2
out=${3:-/tmp/LM-Stage2-Anchor-Probe}
[[ -d "$app_path" ]] || exit 66
command -v magick >/dev/null
mkdir -p "$out"
xcrun simctl install "$udid" "$app_path"
xcrun simctl spawn "$udid" log stream --level=info \
    --predicate "subsystem == \"$bundle_id\"" > "$out/performance.log" 2>&1 &
log_pid=$!
trap 'kill "$log_pid" 2>/dev/null || true; wait "$log_pid" 2>/dev/null || true' EXIT
launch=$(xcrun simctl launch --terminate-running-process "$udid" "$bundle_id" \
    --lunar-explorer --lunar-explorer-preset=surface \
    --lunar-explorer-altitude=2 --lunar-explorer-meters-across=8 \
    --lunar-explorer-detail=procedural --lunar-explorer-capture \
    --lunar-globe-texture-tier=wac-global-64ppd --lunar-explorer-profile \
    --lunar-explorer-profile-label=reanchor --lunar-explorer-reanchor-probe)
app_pid=${launch##*: }
capture() {
    kill -0 "$app_pid"
    xcrun simctl io "$udid" screenshot "$out/$1.png"
    saturation=$(magick "$out/$1.png" -colorspace HSL -channel G -separate \
        -format '%[fx:mean]' info:)
    awk -v s="$saturation" 'BEGIN { exit !(s <= 0.01) }'
    date -u '+%Y-%m-%dT%H:%M:%SZ' >> "$out/capture-times.txt"
}
sleep 92
capture before
sleep 4
for index in {1..10}; do
    capture "transition-$index"
    sleep 1
done
sleep 92
capture after
# Require the actual trigger and preserve the residency/bake diagnostics.
rg 'Reanchor generation=' "$out/performance.log" > "$out/reanchor.txt"
awk '
    /Reanchor generation=/ { transitions += 1; transitioned = 1 }
    /Terrain tile ready/ { tiles += 1; if (transitioned) rebuilt += 1 }
    END { exit !(transitions == 1 && tiles > 0 && rebuilt == 0) }
' "$out/performance.log"
printf 'capture\trmse\n' > "$out/comparison.tsv"
for file in "$out"/transition-*.png "$out/after.png"; do
    status=0
    metric=$(magick compare -metric RMSE "$out/before.png" "$file" null: 2>&1) || status=$?
    [[ "$status" -le 1 ]] || exit "$status"
    printf '%s\t%s\n' "$(basename "$file")" "$metric" >> "$out/comparison.tsv"
done
shasum -a 256 "$out"/*.png > "$out/hashes.txt"
echo "Re-anchor capture complete: $out"
