# WindowSurrounds handoff

Load `WindowSurrounds.usdz` once at Cabin identity: root `/WindowSurrounds`, meters, +X right/+Y up/-Z forward. This provides broad sloping window reveals, adjoining closed cheek sections and backed breaker mounting reliefs. `WindowSurrounds.blend` and `build.py` are the editable/reproducible source.

`interface.json` follows `lmkit.console-enclosure.v1`. `/WindowSurrounds/CDR` and `/WindowSurrounds/LMP` cover every model descendant and must cast shadows. Only after successful overlay and contract validation, suppress the 38 explicitly named leaf meshes under `/Cabin/Shell/Cutaway_Forward` belonging to the original CDR/LMP Front Lower/Inboard/Upper families. Their expected poses are component-root-relative, not parent-relative. Never suppress the parent cutaway group, mounts, panes, LPD, handrails, live controls or a whole planning slot.

The six protected WindowsLPD forward pane/eye paths remain unchanged. No optical aperture, crew-eye point or control mount moves. The central console trims meet the accepted InstrumentConsole footprint, and the pilot contact sight well preserves the small existing lamp view. Breaker-bank reliefs have solid rear backing, so a clearance seam does not expose an open interior cavity. Native combined appearance remains coordinator-owned; no global lighting workaround is baked into these assets.

Validation reports:

- `validation.json`: actual exported mesh topology, right-handed unit transforms, closed manifold sections, positive signed volume/outward winding, ARKit USDZ compliance and 1,560 sampled aperture rays.
- `native-validation.json`: macOS RealityKit loading, all 38 exact suppression leaves and six protected optical poses, caster-group coverage.
- `assembly-validation.json`: raw USD world-space comparison against installed peers and both new consoles, with input hashes and 79 live control-face rays. The check deliberately avoids Blender USD-import reinterpretation of legacy authoring axes.
- `reviews/`: transient Workbench whole-cabin and crew-eye views. Glazing is hidden only in these geometry reviews; authored glazing remains untouched in WindowsLPD.

Detailed dimensions, material colors, source applicability and relief policies remain provisional; read `EVIDENCE.md`. Shared-wall boundary contacts, hidden registration/backing contact and small retained detail hardware must be classified separately from exposed instrument intrusion. Final combined-review evidence and acceptance are recorded alongside the reports. No headset or simulator test was performed by this worker. No flight optical calibration, pressure integrity, electrical behavior or continuous hand-reach qualification is implied.

Reproduce from the repository root (Blender 5.2.1 LTS with USD Python SDK):

```sh
blender --background --python-exit-code 1 --python Assets/Cockpit/Components/WindowSurrounds/build.py
blender --background --python-exit-code 1 --python Assets/Cockpit/Components/WindowSurrounds/validate.py
blender --background --python-exit-code 1 --python Assets/Cockpit/Components/WindowSurrounds/validate_assembly.py
blender --background --python-exit-code 1 --python Assets/Cockpit/Components/WindowSurrounds/review.py
swiftc -parse-as-library Assets/Cockpit/Components/WindowSurrounds/validate_native.swift -o /tmp/window-surrounds-native
/tmp/window-surrounds-native Assets/Cockpit/Components/WindowSurrounds
```

The assembly checker currently records explicit parallel-worktree fallbacks for newly delivered peer components. After integration, use the accepted repository copies at the recorded hashes. The coordinator owns package resource synchronization, shared tests, final assembly and runtime/native visual acceptance. This branch changes only WindowSurrounds and is not pushed.

Final worker result: 44 closed outward-wound meshes, 820 triangles, 1,281 structural assertions, 1,560 unobstructed aperture rays and 213 native RealityKit assertions. Raw assembly checks find zero WindowSurrounds crossings with WindowsLPD, InstrumentConsole, LowerConsole, BreakerBanks or the installed live instrument components; all 79 control-face rays are clear. Retained Cabin sheet-boundary contacts, planning-frame/backing registration and two header-return bolts remain qualified assembly contacts, not pressure-vessel or mechanical acceptance.

Independent reviewer confirmed the same final geometry hash with no enclosure-pair crossings, no crossings against the updated packaged WindowsLPD or BreakerBanks, 1,560 aperture/13 instrument/25 DSKY view rays clear, and 125 sampled ACA poses clear. The three `independent-*-review.json` reports preserve that separate reviewer evidence. Remaining mission-timer rear seating belongs to the central console fit and does not involve a surround intrusion. Native combined visual acceptance is still the coordinator’s final gate.
