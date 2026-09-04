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
capture_attempts=${LUNAR_CAPTURE_ATTEMPTS:-2}
maximum_mean_saturation=${LUNAR_CAPTURE_MAXIMUM_MEAN_SATURATION:-0.01}
capture_filter=${LUNAR_CAPTURE_FILTER:-}
capture_profile=${LUNAR_CAPTURE_PROFILE:-0}
bundle_id=io.positron.LM

if [[ ! -d "$app_path" ]]; then
    echo "LM app bundle does not exist: $app_path" >&2
    exit 66
fi

if ! command -v magick >/dev/null 2>&1; then
    echo "ImageMagick is required to reject failed immersive-scene captures" >&2
    exit 69
fi

mkdir -p "$output_directory"
xcrun simctl boot "$simulator_udid" 2>/dev/null || true
xcrun simctl bootstatus "$simulator_udid" -b
xcrun simctl install "$simulator_udid" "$app_path"

profile_arguments=()
profile_logger_pid=
if [[ "$capture_profile" == 1 ]]; then
    profile_arguments+=(--lunar-explorer-profile)
    profile_log="$output_directory/performance.log"
    profile_runs="$output_directory/profile-runs.tsv"
    : > "$profile_runs"
    xcrun simctl spawn "$simulator_udid" log stream \
        --level=info \
        --predicate 'subsystem == "io.positron.LM"' \
        > "$profile_log" 2>&1 &
    profile_logger_pid=$!
fi

stop_profile_logger() {
    if [[ -n "$profile_logger_pid" ]]; then
        kill "$profile_logger_pid" 2>/dev/null || true
        wait "$profile_logger_pid" 2>/dev/null || true
        profile_logger_pid=
    fi
}
cleanup() { stop_profile_logger; }
trap cleanup EXIT

manifest="$output_directory/ladder.tsv"
printf "stop\tpreset\taltitude_m\twidth_m\tsha256\n" > "$manifest"

# Eleven stops keep the globe handoff legible and cross every production terrain
# gate. Capture mode is explicitly pinned to the accepted 64 ppd tier and all
# required globe content is bundled, so the ladder is network-independent.
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
    if [[ -n "$capture_filter" && ",$capture_filter," != *",$name,"* ]]; then
        continue
    fi
    screenshot="$output_directory/$name.png"
    stop_profile_arguments=("${profile_arguments[@]}")
    if [[ "$capture_profile" == 1 ]]; then
        stop_profile_arguments+=("--lunar-explorer-profile-label=$name")
    fi
    captured=false
    for ((attempt = 1; attempt <= capture_attempts; attempt += 1)); do
        echo "Launching $name (attempt $attempt/$capture_attempts); settling for ${capture_wait_seconds}s"
        launch_output=$(xcrun simctl launch --terminate-running-process \
            "$simulator_udid" "$bundle_id" \
            --lunar-explorer \
            "--lunar-explorer-preset=$preset" \
            "--lunar-explorer-altitude=$altitude" \
            "--lunar-explorer-meters-across=$width" \
            --lunar-explorer-detail=procedural \
            --lunar-explorer-capture \
            "${stop_profile_arguments[@]}" \
            --lunar-globe-texture-tier=wac-global-64ppd)
        launch_pid=${launch_output##*: }
        sleep "$capture_wait_seconds"
        xcrun simctl io "$simulator_udid" screenshot "$screenshot" >/dev/null

        mean_saturation=$(magick "$screenshot" \
            -colorspace HSL -channel G -separate \
            -format '%[fx:mean]' info:)
        process_alive=false
        if kill -0 "$launch_pid" 2>/dev/null; then
            process_alive=true
        fi
        if [[ "$process_alive" == true ]] && awk \
            -v saturation="$mean_saturation" \
            -v limit="$maximum_mean_saturation" \
            'BEGIN { exit !(saturation <= limit) }'; then
            captured=true
            break
        fi

        echo "Rejected $name attempt $attempt: process_alive=$process_alive mean_saturation=$mean_saturation" >&2
    done

    if [[ "$captured" != true ]]; then
        echo "Failed to capture a valid immersive frame for $name" >&2
        exit 70
    fi

    sha=$(shasum -a 256 "$screenshot" | awk '{print $1}')
    if [[ "$capture_profile" == 1 ]]; then
        printf "%s\t%s\n" "$launch_pid" "$name" >> "$profile_runs"
    fi
    printf "%s\t%s\t%s\t%s\t%s\n" \
        "$name" "$preset" "$altitude" "$width" "$sha" >> "$manifest"
    echo "Captured $screenshot (mean saturation $mean_saturation)"
done

if [[ "$capture_profile" == 1 ]]; then
    stop_profile_logger
    summary="$output_directory/performance.tsv"
    {
        printf "stop\ttile_records\ttile_mean_ms\ttile_first_ms\ttile_last_ms\tframes\tframe_mean_ms\tframe_p95_ms\tframe_p99_ms\tframe_max_ms\tmissed\tphysical_mib\n"
        awk '
            NR == FNR { accepted[$1] = $2; next }
            function field_value(field, prefix, suffix) {
                sub("^" prefix, "", field)
                if (suffix != "") sub(suffix "$", "", field)
                return field
            }
            /Explorer performance preset=/ {
                process = $6
                if (!(process in accepted)) next
                label = field_value($12, "preset=", "")
                if (label != accepted[process]) next
                labels[process] = label
                frames[label] = field_value($13, "frames=", "")
                frame_mean[label] = field_value($14, "mean=", "ms")
                frame_p95[label] = field_value($15, "p95=", "ms")
                frame_p99[label] = field_value($16, "p99=", "ms")
                frame_max[label] = field_value($17, "max=", "ms")
                missed[label] = field_value($19, "missed=", "")
                physical[label] = field_value($20, "physical=", "MiB")
            }
            /Terrain tile ready/ {
                process = $6
                if (!(process in accepted)) next
                generation = field_value($17, "generation=", "ms") + 0
                tile_count[process] += 1
                tile_sum[process] += generation
                if (!(process in tile_first) || generation < tile_first[process]) {
                    tile_first[process] = generation
                }
                if (generation > tile_last[process]) tile_last[process] = generation
            }
            END {
                for (process in labels) {
                    label = labels[process]
                    if (tile_count[process] > 0) {
                        tile_mean = sprintf("%.1f", tile_sum[process] / tile_count[process])
                        first = tile_first[process]
                        last = tile_last[process]
                    } else {
                        tile_mean = first = last = "-"
                    }
                    printf "%s\t%d\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", \
                        label, tile_count[process], tile_mean, first, last, \
                        frames[label], frame_mean[label], frame_p95[label], \
                        frame_p99[label], frame_max[label], missed[label], \
                        physical[label]
                }
            }
        ' "$profile_runs" "$profile_log" | sort
    } > "$summary"
    echo "Wrote Release performance summary to $summary"
fi

echo "Wrote Stage 1 zoom ladder to $output_directory"
