#!/usr/bin/env bash
# Each app runs three times, in alternating order. Judge only the complete set.
set -euo pipefail
[[ $# == 5 ]] || { echo 'usage: RunMoonExplorerComparison.sh <udid> <control.app> <candidate.app> <fresh-output> <journey|soak|highland-warm|highland-cold>' >&2; exit 64; }
udid=$1
control=$2
candidate=$3
out=$4
workload=$5
[[ ! -e "$out" ]] || exit 66
[[ "$workload" == journey || "$workload" == soak || "$workload" == highland-warm || "$workload" == highland-cold ]] || exit 64
mkdir -p "$out"
printf 'sequence\trole\trun\texecutable_sha256\n' > "$out/run-order.tsv"
sequence=0
for repetition in 1 2 3; do
 for role in Control Candidate; do
  app=$control
  [[ "$role" == Control ]] || app=$candidate
  sha=$(shasum -a 256 "$app/LM" | awk '{print $1}')
  sequence=$((sequence + 1))
  printf '%s\t%s\t%s\t%s\n' "$sequence" "$role" "$repetition" "$sha" >> "$out/run-order.tsv"
  printf '%s %s %s\n' "$workload" "$role" "$repetition" > "$out/current-run.txt"
  xcrun simctl terminate "$udid" io.positron.LM >/dev/null 2>&1 || true
  sleep 10
  if [[ "$workload" == journey ]]; then
   LUNAR_ONE_ZOOM=1 bash Tools/CaptureMoonExplorerJourney.sh "$udid" "$app" "$out/$role-$repetition"
  elif [[ "$workload" == highland-warm ]]; then
   LUNAR_HIGHLAND_DIVE=1 bash Tools/CaptureMoonExplorerJourney.sh "$udid" "$app" "$out/$role-$repetition"
  elif [[ "$workload" == highland-cold ]]; then
   bash Tools/CaptureMoonExplorerColdHighland.sh "$udid" "$app" "$out/$role-$repetition"
  else
   LUNAR_PROFILE_SOAK_CYCLES=5 bash Tools/CaptureMoonExplorerJourney.sh "$udid" "$app" "$out/$role-$repetition"
  fi
  python3 Tools/MeasureMoonExplorerRuns.py measure "$out/$role-$repetition" > "$out/$role-$repetition/summary.json"
 done
done
flags=()
[[ ${LUNAR_CHANGES_TEXTURE:-0} != 1 ]] || flags+=(--changes-texture)
python3 Tools/MeasureMoonExplorerRuns.py compare "$out" --spread "${LUNAR_NOISE_SPREAD:-range}" "${flags[@]}"
printf 'complete\n' > "$out/current-run.txt"
