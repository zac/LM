# Propulsion instrument cluster handoff

Editable, source-guided later-LM hardware for Panel 1: ENG/CMD thrust, fuel/oxidizer temperature and pressure, mechanical T/W face, dual fuel/oxidizer quantity readout and helium pressure-shaped readout. All seven needles and 56 illuminated segments are independently addressable. **No live historical instrument channel is supported by the audited public snapshot. All readings are neutral/unavailable in production.**

## Delivery and ownership

- Worker branch `cockpit/propulsion-instruments`, base `035c5b3ad1a522cf6d25fb222d46c2fb4a4a8de8`.
- Only `Assets/Cockpit/Components/PropulsionInstruments/` is changed. No runtime, shared packaging, peer asset, simulator, AGC or LMCore changes.
- `PropulsionInstruments.blend` is editable source; `PropulsionInstruments.usdz` is the neutral integration asset. Matching USDC/USDA and `interface.json` are included.
- Original NASA/AOH evidence and source applicability are in `EVIDENCE.md`; the signal audit is `evidence/SIGNAL_AUDIT.md`.

## Mount and replacement contract

Root `/PropulsionInstruments` is identity, meters, Y-up; +X right, +Y up, +Z toward crew. Use the accepted `Panel1__Propulsion` slot with local translation `(0,0,0.008)` meters, identity rotation and unit scale. This yields root Panel1-local `(0.177,0.105,0.008)`.

The upper cluster is 86 × 134 mm, bounded in Panel1-local XY by `(0.134,0.038)` to `(0.220,0.172)`. The separate T/W child is at root-local `(0.022,-0.150,0)`, 32 × 125 mm. Its Panel1-local XY bounds are `(0.183,-0.1075)` to `(0.215,0.0175)`. Actual exported T/W-to-AltitudeRate X separation is 16.999998 mm. AltitudeRate retains its existing pose and taller envelope. The upper support is 10.5 mm above that envelope; actual analog housings begin 13.5 mm above it.

**Preserve RangeThrust's blank and AltitudeRate's independent identity.** The root spans two disjoint placement regions; do not use its union AABB to remove neighboring slots. Replace only the Propulsion placeholder. Rear housings extend through the backing registration; no cutout/fastener/depth interference qualification is claimed. Dimensions and scale spacing are provisional reconstruction choices.

## Animation contract

`interface.json` is authoritative for paths, poses, units, ranges and source availability. Each analog root has a fixed `Fixed` subgroup and independently translated `Needles/<channel>` roots. Move a needle along local Y using the declared numeric domain and scale span, preserve its declared X and set Z to +0.003 for a valid reading. Reject missing, nonfinite and out-of-domain values; restore the exact parked transform on invalid data. Do not clamp invalid sensor data into plausible readings.

Each digit contains `SegmentA` through `SegmentG`, with conventional seven-segment order recorded in the interface. Preserve segment X/Y and move only Z: +0.002 active, -0.003 parked. All segments park on invalid data. Quantity is two digits per fluid but the sourced range is 0–95%. Helium is four digits with pressure last digit zero; 0–9990 is representation capacity only, not an established sensor range. Helium temperature/sign mode is absent. The opaque dial/window hides parked geometry; USD visibility is not authored invisible, allowing native clients to activate individual parts later.

No command-force-to-ENG conversion, invented helium reading, duplicated measured/command pair, or aggregate-propellant-to-tank conversion is valid. A future optional command percentage or DPS-only force/mass aid must be explicitly qualified by the host and reviewed independently; this delivery enables neither.

## Reproduction and checks

Run from the repository root with Blender 5.2.1 LTS (build 9e2066aef7ef) and its bundled USD Python modules:

```sh
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python-exit-code 1 --python Assets/Cockpit/Components/PropulsionInstruments/build.py -- --preview
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python-exit-code 1 --python Assets/Cockpit/Components/PropulsionInstruments/validate.py
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python-exit-code 1 --python Assets/Cockpit/Components/PropulsionInstruments/review_fit.py
xcrun swiftc -module-cache-path /tmp/propulsion-swift-cache -parse-as-library Assets/Cockpit/Components/PropulsionInstruments/validate_native.swift -o /tmp/propulsion-native
/tmp/propulsion-native "$PWD/Assets/Cockpit/Components/PropulsionInstruments"
python3 Assets/Cockpit/Components/PropulsionInstruments/hash_artifacts.py
```

`build.py` only needs its sibling interface and Blender/pxr, uses built-in Bfont converted to meshes, and writes only this component. It exports and saves the neutral state before creating transient review cameras/annotations or applying synthetic example values. `review_fit.py` additionally reads existing CommanderPanels, PanelInventory and AltitudeRate assets; it never executes peer scripts or changes peer files. Exact binary byte reproducibility across Blender/USD versions is not promised; the path, mesh, unit and transform checks establish the functional contract. Artifact hashes pin this delivery.

- `validation.json`: 1,728 checks passed; 364 meshes, 20,372 triangles; no ARKit compliance errors, failed checks or warnings. Includes identity/units, complete declared channels, neutral parks, analog minimum/midpoint/maximum movement, fixed-geometry isolation, mesh finiteness/triangulation, Blender/USD transform parity, documented domain qualifications and exported front-envelope checks.
- `native-validation.json`: 240 macOS RealityKit assertions passed, including native neutral USDZ loading, independent seven-needle and 56-segment mutation and fixed-root preservation.
- `mounting-validation.json`: positive separation from accepted AltitudeRate and other Panel1 slot envelopes. This checks XY front envelopes, not full mechanical geometry.
- `review/README.md`: neutral, explicitly synthetic-layout and Panel1 context images with limitations.

Coordinator still owns resource syncing/packaging validation and assembled runtime integration. Vision Pro, live sources, selector state, electrical failures, materials under cockpit lighting, detailed dimensions, rear hardware and full-cabin visibility remain unqualified. Do not present neutral parked readings as historical electrical behavior.
