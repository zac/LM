# Native control and display binding proposal

This is a standalone external facade asset, not an executable DSKY. Import `DSKY.usdz` into Reality Composer Pro. Use `DSKY-LightingPreview.usdz` only for static emissive-material inspection: its all-segments pattern is not AGC output. It intentionally lights every labeled annunciator and all segments; blank spare cells stay unlit. The `.blend` is neutral and contains the on-state authoring materials as retained datablocks. There are no linked textures, fonts, scripts or app dependencies needed to open the exports.

## Assembly and hover targets

1. Preserve `DSKY_Mount`, an identity transform in meters. Parent it at the coordinator's accepted DSKY cabin datum. Both exported vertices and local transforms are Y-up; do not add another Blender correction rotation.
2. Verify the 19 direct-child `DSKY_Key_*` paths in `bindings.json`. Each contains separate `DSKY_Cap_*` and `DSKY_KeyLegend_*` geometry. Cap and legend must move together, while the socket and face remain fixed. Child transforms and USD mesh prims may appear as separate entities after import; bind by full path/name, not a guessed ModelEntity cast on the pivot.
3. Add native InputTargetComponent, a simple CollisionComponent and HoverEffectComponent to each key's intended target/entity hierarchy. In RCP author these components if available in the coordinator's version, or install them in the RealityKit binder. Imported names do not install these components. Keep hover confined to each cap/key subtree; do not attach it to the whole DSKY root. If material highlighting is implemented manually, copy/replace only that cap's material value, not the shared source material across all keys.
4. Existing procedural collision dimensions are `(capWidth + .006, capHeight + .006, .020)` m. Those are NOT a safe default for this asset: the baseline vertical center spacing is only .01778 m, so expanded targets overlap. Start with cap-sized, nonoverlapping boxes `(0.01778,0.015748,0.008)` centered on the pivot. Coordinator must test gaze selection and adjacent-key error rate on Vision Pro, and decide on a native enlarged keypad if needed.
5. Resolve a hit by walking ancestors to an imported key pivot. Populate the existing key lookup with imported Entity references, changing the procedural ModelEntity-only storage if necessary. Apply InputTarget/hover/collision to the actual imported hierarchy. Dispatch pinch/tap to existing `PoweredDescentSession.sendDSKYKey`; remove/disable duplicate procedural controls only after binding succeeds.
6. Move the pivot from the exact neutral in `bindings.json` by `(0,0,-.003)` m and spring back. This is provisional app-compatible travel, not a qualified switch measurement. Do not accumulate deltas. PRO must send separate press AND release edges, including cancellation. Current session sends true, waits 120 ms, then false even if cancelled. Preserve this behavior; a held gesture implementation needs release/cancel handling as well.

Apple references: [InputTargetComponent](https://developer.apple.com/documentation/realitykit/inputtargetcomponent), [HoverEffectComponent](https://developer.apple.com/documentation/realitykit/hovereffectcomponent), [responding to gestures](https://developer.apple.com/documentation/realitykit/responding-to-gestures-on-an-entity). RCP UI, installed component authoring capabilities and on-device hover/pinch have **not been tested by this asset task**.

## Live display mapping

Read `snapshot.agc.dsky` through the existing session; do not parse a second verb/noun state machine. Each field has a named `DSKY_Readout_*` transform under `DSKY_Display_Mount`. Replace the child geometry with a native live renderer, or drive the authored per-digit segments. `DSKY_Digit_<field>_<index>` uses zero-based left-to-right positions; children A top, B upper-right, C lower-right, D bottom, E lower-left, F upper-left, G middle. Signs have separate Plus vertical and Minus horizontal meshes. The material layer is a display renderer only; it must preserve blank states, flash and lamp test from AGC.

| Asset | Existing snapshot input |
|---|---|
| PROG (2 digits) | `mode`; `programNumber` is derived metadata |
| VERB / NOUN (2 each) | `verb` / `noun`; honor runtime flash/blank state |
| R1 / R2 / R3 | `r1` / `r2` / `r3`, five digits plus sign; preserve spaces |
| COMP ACTY | `compActy` or `lampTest` |
| Named lamps | `indicatorIsOn(id)` or `lampTest`; IDs in bindings.json |
| Two blank lower-left cells | No runtime binding; spare cells, remain blank |

The neutral export keeps all segments faintly visible as physical phosphor. Switch their assigned material (or visibility) for live output. LightingPreview supplies `DSKY_EL_green_on`, `DSKY_Status_white_on`, `DSKY_Caution_amber_on`; their shader emission is authored in USD Preview Surface. Numeric label strips and register rules have separately swappable phosphor materials; the label characters stay dark. Lamp characters remain opaque black while their background lights. Green COMP ACTY is a provisional lookdev choice: the dossier's white/green source conflict remains unresolved. Engine strengths are not measured luminance; the primary lamp specification is 15 ±3 foot-lamberts, requiring renderer/device calibration.

The current procedural display mount z=0.010 m and this asset's region placement are provisional surface locations. Bind to the named regions instead of overlaying the existing whole-panel attachment blindly; that could occlude the modeled lamp/numeric separation.

## Coordinator acceptance

Required before claiming interaction: import in RCP, inspect materials and hierarchy, native load on accepted app/AGC commits, all 19 key dispatches, neighboring-key selection, single-key hover, key spring return, PRO release/cancellation, blank/flashing digits, signs, all lamps/lamp test, no duplicate procedural geometry, and on-device label readability. Measure scene memory and frame timing with the full cockpit and terrain. No runtime or Vision Pro acceptance is claimed here.

## Refined display preview

`DSKY-DisplayPreview.usdz` is an additional static appearance example (66 / 06 / 60, signed zero registers, annunciators off). It preserves the same key and region hierarchy. It is not AGC-driven. The original `DSKY-LightingPreview.usdz` remains the all-lamps/all-segments material test.

`DSKY_LabelStrip_PROG/VERB/NOUN` and `DSKY_RegisterRule_*` are separate phosphor-backed meshes. Drive their light level with display power/brightness alongside active segments. The label text is dark, fixed geometry. Tapered segments retain the original A–G object names and indices. Lamp backgrounds can switch materials independently; shared authoring materials do not imply shared runtime state. Keep lamp text black in either state. Emission inputs are present in USDZ, but actual glow and scene illumination depend on the native renderer; neither automatic AGC binding nor a particular bloom effect is baked into USDZ.

## Warm backlight and diffuser

Each status/caution indicator now contains the existing `_Lens` background (the swappable emitting surface), a thin `_Diffuser` cover above it, and the opaque black `_Legend`. These remain under that indicator's transform. The diffuser uses USD Preview Surface opacity 0.12 and roughness 0.72 as a portable visual approximation; this is not a calibrated subsurface optical simulation. Preserve the cover when switching the background between unlit, white-on and amber-on materials. Twelve cells remain independently addressable; spare cells remain unbound.

`DSKY-BacklightPreview.usdz` is a static sample with PROG and TRACKER amber backgrounds enabled. The other annunciators are off. The yellow-green numeric sample remains static. Amber-on now has stronger emission so it reads as a luminous background rather than colored paint. Status white and caution yellow remain distinct.

`review/backlight-preview.png` uses dimmer external light plus a **Blender-only compositor halo** to demonstrate the intended soft optical appearance. The USDZ carries the emissive background and translucent diffuser, but not this compositor effect, point lights, or automatic AGC connections. Reproduce/tune the halo in the native renderer if desired; do not claim it comes from the exported mesh or that emission automatically lights adjacent surfaces. Test transparency sorting, readability of dark legends and brightness on Vision Pro before accepting the material treatment.

Exporter note: Blender 5.2 wrote the DITHERED material's constant alpha as opacity 1. `usd_pipeline.py` explicitly authors the diffuser's USD Preview Surface opacity as 0.12 (no alpha clip) before packaging. Validation checks that exported value and the number of independently amber-lit cells in every preview. This is necessary to keep the cover from hiding the underlying emitter in USD readers.

## Final delivery verification

The immutable backlight asset revision is `d5827948e6e288154e588b8608bda5fc4c6707ce`; subsequent handoff commits change documentation only. `validation.json` records 276 passed checks, including all four USDZs, exact key hierarchy/positions, emitter states, diffuser opacity, OpenUSD compliance and clean Blender reimport. `native-validation.json` records the neutral file loading in macOS RealityKit. RCP GUI, native shader appearance and Vision Pro input/hover remain untested.

- `DSKY.usdz` SHA-256: `e20a69864d4c7e0ff068172e0e672d9fbcc510c1dc4e97e4db0246fde08fbdfd`
- `DSKY-LightingPreview.usdz` SHA-256: `aef3d4115c206e8c7f3a7443f58b83d91617cdb45d55f50a4fe83a08eb9cfcdd`
- `DSKY-DisplayPreview.usdz` SHA-256: `c83926228af7e35d631724301c283e47ca12d2451600a04f70201d1bce8d8742`
- `DSKY-BacklightPreview.usdz` SHA-256: `8f266812ed719f48f63be2e3a0364fa2f08a5d07119b77224eeb617ec378888d`

Slot fit remains unqualified: 7.700 inches is mounting-thread pitch, not housing width. The current rear enclosure is provisional; `/DSKY_Mount` is the app face midpoint, not the historical seating shoulder. See `fit-interface.json` and `evidence/mount-fit-research.md` before defining a panel cutout. Geometry, source scripts and provenance stay in this component directory; extraction into a separate library is coordinator-owned.
