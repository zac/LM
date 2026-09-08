# DSKY component handoff

## Assignment

- Component: standalone DSKY; worker `cockpit/dsky`.
- Machine: zacbookpro.local; Blender 5.2.1 LTS (9e2066aef7ef).
- Exact source baseline: `97f877b52bf569656c6798cff5790b7207c42af0`, verified equal to cockpit/integration before edits. Initial detached checkout clean (LFS filtering disabled for read-only status because sandbox blocked shared LFS tmp).
- Owned directory: `Assets/Cockpit/Components/DSKY/` only.
- Contract: draft v0 and assignment/coordination/app geometry at the baseline above. No AGC dependency required to build this visual asset; integration must pin its accepted AGC revision.
- Deliverables: reproducible script, editable Blender scene, USDZ and inspectable USD, review views, validation and binding manifests, source evidence.
- Acceptance: exact 19 key transforms and required direct parents, portable clean reopen, metric dimensions and identity root, independent displays, export roundtrip where supported, honest reference comparison. Native runtime/device acceptance belongs to integration.

### Frozen local interface (before detailing)

Origin is the center of the app's face plate at its mid-depth plane. USD +X right, +Y top, +Z toward crew; body extends along -Z. Blender authors X right, Z top, -Y toward crew; export physically converts `(x,y,z)` to `(x,z,-y)`. No cabin placement is baked in.

Face width 0.2063496 m, height 0.2032 m; maximum depth budget 0.175514 m. These are compatibility values claimed as drawing dimensions by LMDSKYGeometry, now cross-checked against the original Rev B scan (depth is MAX REF, not a controlled dimension). Mounting width 0.19558 m, inner width 0.17526 m. Display mount center `(0,0.029591,0.010)` m (z surface offset provisional). Face thickness 0.012 m; keys centered at z=0.011 m with 0.008 m cap depth, following the procedural app. Key centers are digitized, not dimensioned drawing callouts; all 19 x/y values remain unchanged. Cap width/height 0.01778/0.015748 m. Travel 0.003 m along USD -Z, Blender +Y, spring return, no detents/guards; provisional inherited app animation, not a verified switch measurement.

Housing depth, rear details, bevels, fastener sizes, display subdivision and typography are provisional unless explicitly verified below. Freeze the envelope rather than inferring installation from a standalone origin.

## Delivered revision

- Exact component commit: `85c072502a087aadf97c118e5de8bad9a2b6ba5d`. The following handoff-only commit records this immutable asset revision; no asset changes in that follow-up.
- Blender: 5.2.1 LTS, build 9e2066aef7ef; no add-ons. Native smoke check: Apple Swift 6.3.3, macOS RealityKit.
- Editable source: `DSKY.blend`; reproducible builder: `build.py`; USD coordinate bake/package: `usd_pipeline.py`.
- Neutral exports: `DSKY.usda`, `DSKY.usdc`, `DSKY.usdz`. Lighting exports: `DSKY-LightingPreview.usda`, `.usdc`, `.usdz` (STATIC lamp-test lookdev, never live output).
- Materials are mesh-bound USD Preview Surface PBR, with separately addressable phosphor, lamp backgrounds, fixed legends and key ink. On-state materials retained in the neutral Blender source; lighting export demonstrates them. Zero texture dependencies; built-in font converted to geometry. Relative `//review/front.png` output setting; no linked libraries.
- Settings: `export-settings.json`. Blender exports triangulated Y-up, meter-based USD with separate parent transforms and Preview Surface. `usd_pipeline.py` bakes the exporter's rotation into every local transform, mesh point and normal, then emits binary USDC and a self-contained USDZ. Root transform is identity after baking, not just root scale. No review cameras/lights are exported.
- Review images: `review/front.png`, `review/oblique.png`, `review/key-detail.png` (900 square Workbench); `review/lighting-preview.png` (720 square Eevee, STATIC all-segments display).

### Reproduce

From the repository root, with Blender 5.2.1:

```sh
blender -b --factory-startup --python-exit-code 1 --python Assets/Cockpit/Components/DSKY/build.py
blender -b --factory-startup --python-exit-code 1 --python Assets/Cockpit/Components/DSKY/validate.py
xcrun swiftc -parse-as-library Assets/Cockpit/Components/DSKY/validate_native.swift -o Assets/Cockpit/Components/DSKY/scratch/validate-native
Assets/Cockpit/Components/DSKY/scratch/validate-native "$PWD/Assets/Cockpit/Components/DSKY/DSKY.usdz"
```

Blender requires host execution on this machine: sandboxed startup crashed; the same executable ran successfully outside the sandbox. No heavy render/bake was launched and no render slot was claimed. Small Workbench/Eevee reviews only. Build scripts use component-local files and do not run the AGC or edit the app. Create `scratch/` first for the optional native executable if rebuilding in a fresh clone.

## Evidence and behavior

- Primary outline 2003956 Rev B, archive page 73; assembly 2003994 Rev G, archive page 4; **Rev G is structure evidence, not proof of the -091 configuration**. Original 38 MB archive stays ignored; hashes and full-page review PNGs are in `evidence/`.
- Selected -091 subassembly reference is primary 1005025-001, status/caution indicator, initial release sheets 1–3. These establish the 2×7 layout, blank spares, lamp cells, neutral-gray finish, black lettering and white/yellow lamp colors. Evidence and direct URLs: `evidence/research.md`, original JPEG sheets and `evidence/sources.json`.
- Apollo 11 contextual photographs: AS11-36-5389 and 69-H-135. They do not provide a clear calibrated standalone DSKY close-up. No Apollo 16/17 facade substitution or PRIO DISP/NO DAP decals. Detailed comparison, contradictions and images: `evidence/comparison.md`.
- Source nominal lamp areas: 1.10×.53 in = 27.94×13.462 mm; row pitch .595 in =15.113 mm. Source font family is not reproduced exactly; built-in outline font is a disclosed approximation.
- Moving parts: 19 direct-child key pivots with separate caps and legends. Full neutral positions, paths, spring return and provisional 3 mm -Z press axis in `bindings.json`. Fixed sockets and face stay separate. No guards or detents. No mechanical internals modeled; housing rear is a simplified envelope for the external-facade scope.
- Named regions: `DSKY_Readout_PROG/VERB/NOUN/R1/R2/R3`, each digit and sign, twelve labeled annunciators, two blank spares, COMP ACTY; all beneath `DSKY_Display_Mount`. Neutral file is unpowered; the separate lookdev file intentionally lights all labeled lamps and all segments.
- Runtime owner: existing AGC; binding status **visual_only**. No substitute computer or vehicle dynamics. PRO must retain independent press and release, including cancellation. Native hover/input/collision components are an integration responsibility.
- Binding proposal and acceptance procedure: `INTEGRATION.md`. Gaze highlight can target each key subtree independently; pinch dispatch must populate the imported-key dictionary rather than relying on names alone. Existing expanded collision boxes overlap at this historical spacing; start with nonoverlapping cap-sized targets and evaluate device usability.

## Validation

- **171 automated checks passed**, detailed in `validation.json`: clean Blender reopen, no missing external dependencies, unique names, all 19 exact centers and direct parents, mesh scales, nondegenerate faces/normals, root transform, dimension budget, separate regions, material bindings, emissive shader inputs, OpenUSD compliance and clean USDZ reimport.
- Source complexity: 70,135 triangles, 372 meshes, 10 used neutral materials, zero textures. Extra lookdev material states are separate. No scene budget was specified; integration should profile draw calls before optimizing.
- Native macOS RealityKit load **passed**: all 19 direct keys, positions, required parents and scale (`native-validation.json`, reproducible `validate_native.swift`). This is not an app build or on-device interaction check.
- Final front, oblique, key-detail and lit images visually inspected. Corrected thin-fastener degenerate bevels, lower-register bezel occlusion and overexposed preview lighting before final acceptance. No measured camera match or photometric calibration claimed.
- LFS verification: all seven Blender/USD asset files contain real local asset bytes; each staged pointer OID matches its local SHA-256. Scoped `.gitattributes` adds USDC coverage; existing root rules cover Blender/USDA/USDZ.
- OpenUSD compliance: zero errors, failed checks or warnings for both packages. Reimport preserved key/face parent paths and materials. Native shader visual appearance in RCP remains untested.
- Reality Composer Pro GUI, visionOS app, gaze/hover/pinch, PRO runtime behavior, frame timing and Vision Pro hardware: **not tested**; coordinator-owned gates.
- Review wall time per image (seconds): front 0.215, oblique 0.094, key-detail 0.091, lighting-preview 0.401. Peak memory not measured. Machine zacbookpro.local; no heavy render/bake.
- Known gaps: exact Gorton lettering, original key surface sculpt, historical key travel, exact fastener and flange contours, numeric optical stack, calibrated emission and COMP ACTY white/green disagreement. Source drawing stagger differs from required app key centers; retained compatibility and proposed coordinator reconciliation. This is a detailed external facade delivery with explicit fidelity limits, not a certified flight-unit reconstruction.

### Export SHA-256

- `DSKY.usdz`: `0c9b4b0b5101e7b94e407124c32171bcc347e38f7a502b202adfb163307dff67`
- `DSKY-LightingPreview.usdz`: `2e8abea3cc47e9a4f6cf793e0a88061b04d88c5f6c29af107a771cd550f64214`

## Integration acceptance

Coordinator fills after review:

- Accepted component commit: not yet accepted.
- Integration commit: not performed.
- Acceptance evidence: asset/native-loader checks above; runtime acceptance pending.
- Follow-up work: import in RCP, apply accepted cabin placement, bind collision/input/hover per key and live snapshot display, preserve PRO release/cancel, eliminate duplicate procedural controls, validate on Vision Pro. Reconcile historical key staggering only through a coordinated geometry-contract change.

No push or merge was performed. All delivered changes are confined to this component directory.
