#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
    echo "usage: $0 <simulator-udid> <LM.app> [output-directory]" >&2
    exit 64
fi

simulator_udid=$1
app_path=$2
output_directory=${3:-Artifacts/LunarExplorerAB}
# The close-range footprint can realize nine 512 px detail tiles in an
# unoptimized Debug simulator build. Wait long enough for the requested set to
# settle so a screenshot never compares one complete mode with one partial one.
capture_wait_seconds=${LUNAR_CAPTURE_WAIT_SECONDS:-30}
capture_filter=${LUNAR_CAPTURE_FILTER:-}
bundle_id="${LUNAR_BUNDLE_ID:-io.positron.LM}"

if [[ ! -d "$app_path" ]]; then
    echo "LM app bundle does not exist: $app_path" >&2
    exit 66
fi

mkdir -p "$output_directory"

# Boot is idempotent for an already-running device. bootstatus makes every
# capture wait for SpringBoard rather than racing an asynchronous boot.
xcrun simctl boot "$simulator_udid" 2>/dev/null || true
xcrun simctl bootstatus "$simulator_udid" -b
xcrun simctl install "$simulator_udid" "$app_path"

manifest="$output_directory/comparisons.tsv"
printf "view\tpreset\taltitude_m\twidth_m\tprocedural_sha256\tneural_sha256\trmse\n" \
    > "$manifest"

compare_metric() {
    local first=$1
    local second=$2
    if command -v magick >/dev/null 2>&1; then
        magick compare -metric RMSE "$first" "$second" null: 2>&1 || true
    else
        printf "ImageMagick unavailable"
    fi
}

# Each pair has identical coordinates, camera framing, lighting, geometry,
# normals, rocks, and residency policy. Half-meter offsets deliberately straddle
# the production gate rather than landing on a potentially ambiguous boundary.
views=(
    "approach-above|approach|2500.5|700"
    "approach-below|approach|2499.5|700"
    # Sub-meter terrain is intentionally framed close enough to contribute
    # multiple pixels. Wide gate shots remain useful composition references,
    # but they cannot prove that a 0.5 m or 0.125 m band actually appeared.
    "terminal-above|terminal|250.5|8"
    "terminal-below|terminal|249.5|8"
    "landing-above|landing|60.5|8"
    "landing-below|landing|59.5|8"
    "blend-start-above|landing|40.5|8"
    "blend-start-below|landing|39.5|8"
    "blend-end-above|landing|25.5|8"
    "blend-end-below|landing|24.5|8"
    "surface|surface|2|8"
)

for view in "${views[@]}"; do
    IFS='|' read -r name preset altitude width <<< "$view"
    if [[ -n "$capture_filter" && ",$capture_filter," != *",$name,"* ]]; then
        continue
    fi

    for mode in procedural neural; do
        screenshot="$output_directory/${name}-${mode}.png"
        xcrun simctl launch --terminate-running-process \
            "$simulator_udid" "$bundle_id" \
            --lunar-explorer \
            "--lunar-explorer-preset=$preset" \
            "--lunar-explorer-altitude=$altitude" \
            "--lunar-explorer-meters-across=$width" \
            "--lunar-explorer-detail=$mode" \
            --lunar-explorer-capture >/dev/null
        sleep "$capture_wait_seconds"
        xcrun simctl io "$simulator_udid" screenshot "$screenshot" >/dev/null
    done

    procedural="$output_directory/${name}-procedural.png"
    neural="$output_directory/${name}-neural.png"
    procedural_sha=$(shasum -a 256 "$procedural" | awk '{print $1}')
    neural_sha=$(shasum -a 256 "$neural" | awk '{print $1}')
    rmse=$(compare_metric "$procedural" "$neural")
    printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
        "$name" "$preset" "$altitude" "$width" \
        "$procedural_sha" "$neural_sha" "$rmse" >> "$manifest"
done

transition_manifest="$output_directory/transitions.tsv"
printf "transition\tmode\tabove\tbelow\trmse\n" > "$transition_manifest"
transitions=(
    "approach|approach-above|approach-below"
    "terminal|terminal-above|terminal-below"
    "landing|landing-above|landing-below"
    "blend-start|blend-start-above|blend-start-below"
    "blend-end|blend-end-above|blend-end-below"
)

for transition in "${transitions[@]}"; do
    IFS='|' read -r name above below <<< "$transition"
    for mode in procedural neural; do
        above_path="$output_directory/${above}-${mode}.png"
        below_path="$output_directory/${below}-${mode}.png"
        if [[ ! -f "$above_path" || ! -f "$below_path" ]]; then
            continue
        fi
        rmse=$(compare_metric "$above_path" "$below_path")
        printf "%s\t%s\t%s\t%s\t%s\n" \
            "$name" "$mode" "$above" "$below" "$rmse" \
            >> "$transition_manifest"
    done
done

echo "Wrote Lunar Explorer A/B matrix to $output_directory"
