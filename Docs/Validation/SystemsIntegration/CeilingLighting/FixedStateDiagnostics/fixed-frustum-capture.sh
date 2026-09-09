#!/bin/zsh
set -euo pipefail
export DEVELOPER_DIR=/Applications/Xcode-26.6.0.app/Contents/Developer
mode=$1
device=DE0FAD53-2A01-4B96-95D3-3505E6900DA3
out=/private/tmp/lm-systems-validation/evidence/lighting-diagnostics-fixed
mkdir -p "$out"
args=(--terminal-descent-cockpit --assembly-validation-view=overhead --lighting-diagnostic-report --diagnostic-freeze)
case "$mode" in
 baseline) ;;
 shell) args+=(--diagnostic-shell-shadows) ;;
 shell-12) args+=(--diagnostic-shell-shadows --diagnostic-shadow-distance=12) ;;
 shell-12-bias) args+=(--diagnostic-shell-shadows --diagnostic-shadow-distance=12 --diagnostic-shadow-bias=0.1) ;;
 shell-45-bias3) args+=(--diagnostic-shell-shadows --diagnostic-shadow-distance=45 --diagnostic-shadow-bias=3) ;;
 shell-front-cull) args+=(--diagnostic-shell-shadows --diagnostic-shadow-front-cull) ;;
 shell-fixed4) args+=(--diagnostic-shell-shadows --diagnostic-shadow-fixed=4) ;;
 shell-fixed8) args+=(--diagnostic-shell-shadows --diagnostic-shadow-fixed=8) ;;
 shell-tight) args+=(--diagnostic-shell-shadows --diagnostic-shadow-distance=5) ;;
 shell-bias) args+=(--diagnostic-shell-shadows --diagnostic-shadow-distance=5 --diagnostic-shadow-bias=0.1) ;;
 sun-off) args+=(--diagnostic-sun-off) ;;
esac
xcrun simctl launch --terminate-running-process "$device" io.positron.LM "${args[@]}" > "$out/$mode-launch.txt"
sleep 20
xcrun simctl io "$device" screenshot "$out/$mode.png"
container=$(xcrun simctl get_app_container "$device" io.positron.LM data)
cp "$container/Documents/lighting-diagnostic.json" "$out/$mode.json"
cp "$container/Documents/systems-installation.json" "$out/$mode-installation.json"
