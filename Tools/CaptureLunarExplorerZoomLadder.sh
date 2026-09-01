#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
    echo "usage: $0 <simulator-udid> <LM.app> [output-directory]" >&2
    exit 64
fi

simulator_udid=$1
app_path=$2
output_directory=${3:-/tmp/LandAnywhere-Stage1-64ppd-ladder}
capture_wait_seconds=${LUNAR_CAPTURE_WAIT_SECONDS:-90}
bundle_id=io.positron.LM

if [[ ! -d "$app_path" ]]; then
    echo "LM app bundle does not exist: $app_path" >&2
    exit 66
fi

mkdir -p "$output_directory"
xcrun simctl boot "$simulator_udid" 2>/dev/null || true
xcrun simctl bootstatus "$simulator_udid" -b
xcrun simctl install "$simulator_udid" "$app_path"

manifest="$output_directory/ladder.tsv"
printf "stop\tpreset\taltitude_m\twidth_m\tsha256\n" > "$manifest"

# Eleven stops keep the globe handoff legible and cross every production terrain
# gate. Capture mode is explicitly pinned to the accepted 64 ppd tier and all
# remote activity is disabled, so the ladder is network-independent.
stops=(
    "01-globe|globe|1000000|4400000"
    "02-global-detail|globe|30000|330000"
    "03-crossfade|globe|30000|210000"
    "04-orbit|orbit|30000|120000"
    "05-regional|regional|7500|24000"
    "06-approach-2m|approach|2499.5|4000"
    "07-terminal-0.5m|terminal|249.5|700"
    "08-landing-0.125m|landing|59.5|180"
    "09-relief-blend-start|landing|39.5|80"
    "10-relief-blend-end|landing|24.5|40"
    "11-surface|surface|2|8"
)

for stop in "${stops[@]}"; do
    IFS='|' read -r name preset altitude width <<< "$stop"
    screenshot="$output_directory/$name.png"
    echo "Launching $name; settling for ${capture_wait_seconds}s"
    xcrun simctl launch --terminate-running-process \
        "$simulator_udid" "$bundle_id" \
        --lunar-explorer \
        "--lunar-explorer-preset=$preset" \
        "--lunar-explorer-altitude=$altitude" \
        "--lunar-explorer-meters-across=$width" \
        --lunar-explorer-detail=procedural \
        --lunar-explorer-capture \
        --lunar-explorer-bundled-only \
        --lunar-globe-texture-tier=wac-global-64ppd >/dev/null
    sleep "$capture_wait_seconds"
    xcrun simctl io "$simulator_udid" screenshot "$screenshot" >/dev/null
    sha=$(shasum -a 256 "$screenshot" | awk '{print $1}')
    printf "%s\t%s\t%s\t%s\t%s\n" \
        "$name" "$preset" "$altitude" "$width" "$sha" >> "$manifest"
    echo "Captured $screenshot"
done

echo "Wrote Stage 1 zoom ladder to $output_directory"
