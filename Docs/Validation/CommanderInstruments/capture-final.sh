#!/bin/zsh
set -euo pipefail
capture_view=$1
capture_mode=$2
capture_device=DE0FAD53-2A01-4B96-95D3-3505E6900DA3
capture_out=/private/tmp/lm-commander-instruments-validation/evidence/captures-final
mkdir -p "$capture_out"
capture_args=(--terminal-descent-cockpit "--assembly-validation-view=$capture_view")
case "$capture_mode" in
 normal) ;;
 no-details) capture_args+=(--no-interior-details) ;;
 planning) capture_args+=(--cockpit-planning-labels) ;;
 training) capture_args+=(--cockpit-training-overlays --cockpit-eye-alignment) ;;
 fallback) capture_args+=(--procedural-cockpit) ;;
 *) exit 2 ;;
esac
xcrun simctl launch --terminate-running-process "$capture_device" io.positron.LM "${capture_args[@]}" > "$capture_out/$capture_view-$capture_mode-launch.txt"
printf '%s\n' "${capture_args[@]}" > "$capture_out/$capture_view-$capture_mode-arguments.txt"
sleep 10
xcrun simctl io "$capture_device" screenshot "$capture_out/$capture_view-$capture_mode.png"
