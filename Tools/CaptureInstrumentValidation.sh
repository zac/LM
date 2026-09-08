#!/bin/bash
# Debug-only real AGC validation. Inputs are programmatic, not pinch events.
set -euo pipefail
if [[ $# -lt 3 || $# -gt 4 ]]; then
    echo 'usage: CaptureInstrumentValidation.sh <simulator-udid> <LM.app> <output-directory> [scripted|observe]' >&2
    exit 64
fi
udid=$1
app=$2
out=$3
mode=${4:-scripted}
case "$mode" in
    scripted) input_args=(--instrument-validation-inputs) ;;
    observe) input_args=() ;;
    *) echo 'mode must be scripted or observe' >&2; exit 64 ;;
esac
mkdir -p "$out"
# Caller records the revisions used to build; archive snapshots have no .git.
python3 - "$udid" "$mode" "$out" <<'PYCODE'
import json,os,subprocess,sys,hashlib
run=lambda *a:subprocess.check_output(a).decode().strip()
patch=subprocess.check_output(['git','diff','HEAD','--','LM','LMTests','Tools'])
manifest=dict(simulatorUDID=sys.argv[1],captureMode=sys.argv[2],
 sourceCommit=run('git','rev-parse','HEAD'),
 trackedSourcePatchSHA256=hashlib.sha256(patch).hexdigest(),
 lmkitRevision=os.environ.get('LM_VALIDATION_LMKIT_REV','unspecified'),
 agcRevision=os.environ.get('LM_VALIDATION_AGC_REV','unspecified'),
 inputMethod='programmatic-session-input' if sys.argv[2]=='scripted' else 'native Simulator interaction; completion must be proven by trace',
 camera='reset simulator camera; inverse DEBUG observer recorded in state',
 xcode=run('xcodebuild','-version'))
json.dump(manifest,open(sys.argv[3]+'/capture-manifest.json','w'),indent=2)
PYCODE
xcrun simctl list devices -j > "$out/simulator-devices.json"
shasum -a 256 "$app/LM" > "$out/app-binary-sha256.txt"
if [[ -f "$app/LM.debug.dylib" ]]; then
    shasum -a 256 "$app/LM.debug.dylib" >> "$out/app-binary-sha256.txt"
fi
xcrun simctl install "$udid" "$app"
xcrun simctl launch --terminate-running-process "$udid" io.positron.LM \
    --terminal-descent-cockpit --instrument-validation "${input_args[@]}" > "$out/launch.txt"
pid=$(sed 's/.*: //' "$out/launch.txt")
container=$(xcrun simctl get_app_container "$udid" io.positron.LM data)
trace="$container/Documents/InstrumentValidation.jsonl"
wait_for_action() {
    for ((attempt=0; attempt<1200; attempt++)); do
        if python3 - "$trace" "$pid" "$1" <<'PYCODE'
import json,sys
try:
    rows=[json.loads(line) for line in open(sys.argv[1]) if line.strip()]
    rows=[r for r in rows if str(r.get('processID'))==sys.argv[2]]
    last=rows[-1] if rows else {}
    if sys.argv[3]=='lamp-lit':
        found=last.get('lampTest') and last.get('mode')=='88' and not last.get('flashBlank')
    elif sys.argv[3]=='v16-lit':
        found=last.get('verb')=='16' and last.get('noun')=='36' and not last.get('flashBlank')
    else:
        found=any(sys.argv[3] in r.get('action','') for r in rows)
    sys.exit(0 if found else 1)
except (OSError,ValueError): sys.exit(1)
PYCODE
        then return; fi
        sleep 0.1
    done
    echo "Timed out waiting for $1 in process $pid" >&2
    exit 1
}
capture() {
    date -u +%FT%TZ > "$out/$1-time.txt"
    if [[ -f "$trace" ]]; then tail -1 "$trace" > "$out/$1-state.json"; fi
    xcrun simctl io "$udid" screenshot "$out/$1.png"
}
wait_for_action observe
capture 03-baseline
if [[ "$mode" == observe ]]; then
    echo "Observation-only process $pid; complete native input, then copy $trace into the evidence directory."
    exit 0
fi
wait_for_action 'programmatic V16N36E'
wait_for_action v16-lit
capture 04-v16-input
wait_for_action 'programmatic PRO'
sleep 1
capture 05-pro-input
wait_for_action 'programmatic V35E'
wait_for_action lamp-lit
capture 06-v35-input
wait_for_action 'programmatic RSET'
sleep 1
capture 07-reset-input
cp "$trace" "$out/programmatic-inputs.jsonl"
xcrun simctl spawn "$udid" log show --last 2m --style compact \
    --predicate 'subsystem == "io.positron.LM" AND (category == "InstrumentValidation" OR eventMessage CONTAINS "DSKY")' \
    > "$out/runtime.log"
