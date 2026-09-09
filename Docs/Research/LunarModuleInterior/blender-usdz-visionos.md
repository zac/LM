# Blender, USDZ, and native visionOS authoring research

Research date: 2026-09-08. Repository baseline: `89ecb0fe`. This is a proposed production contract and a read-only integration review. No Blender model, USDZ export, app modification, or device validation was performed.

## Recommended division of responsibility

Confirmed flight-dynamics choice: use the existing LMCore library. AGC owns guidance-computer execution; LMCore owns vehicle dynamics and the simulation integration; RealityKit owns visual presentation and interaction with the authored asset. Drive cabin/world motion and flight instruments from simulation snapshots. Any local interaction physics for handles or props must not become a competing spacecraft dynamics model.

This matches the current [PoweredDescentSession](../../../LM/PoweredDescentSession.swift:94), which holds an `LMSimulationRuntime` and exposes vehicle state and commands from its snapshots. Extend those existing connections when binding imported controls. Additional spacecraft systems still need their implementation coverage checked individually; choosing LMCore does not imply every historical subsystem is already simulated.

User-confirmed requirement: the cockpit runs on Zac's existing AGC implementation. Preserve the existing AGC/LMCore runtime as the source of computer and vehicle behavior. USDZ is the visual asset loaded by the native application; it does not contain or execute the Swift AGC runtime.

The verified current input/output route is:

```text
Imported key or control -> native RealityKit interaction binding
  -> existing PoweredDescentSession / AGC / LMCore input path
  -> simulation snapshot
  -> imported display, indicator and moving-part updates
```

[TerminalDescentCockpitView.swift](../../../LM/TerminalDescentCockpitView.swift:377) already resolves physical keys and calls `session.sendDSKYKey`; its update path applies `session.dsky` to the station. [PoweredDescentSession.swift](../../../LM/PoweredDescentSession.swift:496) handles key dispatch, including PRO's separate press/release behavior. [DSKYSnapshot.swift](/Users/zac/Projects/personal/lm/AGC/Sources/AGC/DSKYSnapshot.swift:3) defines the existing key codes. Bind the new asset to these interfaces rather than duplicating DSKY interpretation, flashing, program execution or annunciation logic.

The current session loads Luminary 099. A later-mission panel detail is a visual substitution and does not authorize a flight-software change. Electrical power, ECS, communications, mechanical latches and the separate AGS/DEDA interface require their own documented owners and implementation status. Keep unavailable system behavior explicit while using the existing simulation wherever it already supplies that behavior.

Acceptance for the first imported DSKY: operate its physical keys through the existing session and verify the same AGC snapshot reaches its displayed digits and lamps. Include PRO release/cancellation. This proves an end-to-end connection to the user's computer implementation; an independently scripted display demonstration does not satisfy it.

Author the cabin, instrument housings, labels, independently moving parts, and calibration datums in Blender. Export a self-contained USDZ. Let native RealityKit and the existing simulation own input handling, switch state, instrument readings, and animation transforms. Preserve a source `.blend`, source textures, an inspectable USD export, and an export-settings record alongside the delivery asset.

A model that opens correctly in a preview application is only a geometry/material milestone. Its switches still need application bindings and interaction testing. Apple documents renderer-specific USD support and recommends checking RealityKit content in Reality Composer Pro or on device. Apple also recommends metallic-workflow PBR and distinguishes structural `usdchecker` validation from visual/behavioral validation. [Apple: Creating USD files for Apple devices](https://developer.apple.com/documentation/usd/creating-usd-files-for-apple-devices)

## Existing integration points and a consequential gap

The current checkout already expects `ApolloLMCabin.usdz` in the main bundle. [LMCockpitAssetContract.swift](../../../LM/LMCockpitAssetContract.swift:5) loads it with `Entity(contentsOf:)`, verifies required names, checks root world scale against identity, and compares selected calibration transforms. Its coordinate convention is meters, +X toward the LMP/right, +Y overhead, -Z forward.

Required names currently include:

```text
LM_Cabin
Cabin_Shell  Cabin_Deck  Forward_Hatch
CDR_Eye  CDR_Window_Inner  CDR_Window_Outer  LPD_Inner  LPD_Outer
Panel_1  Panel_2  Panel_3  Panel_4  Panel_5  Panel_6
CDR_Glareshield  LMP_Glareshield
FDAI_Mount  DSKY_Mount  DSKY_Face  DSKY_Display_Mount
ACA_Pivot  ROD_Pivot  ATT_HOLD_Pivot
DSKY_Key_<suffix> for each of the 19 keys
```

Generate key names from [LMDSKYGeometry.swift](../../../LM/LMDSKYGeometry.swift:103), including `PLUS`, `MINUS`, `KEY_REL`, `ENTR`, `CLR`, and `RSET`. Do not infer spelling from the printed legends. The geometry source identifies outline drawing 2003956 Rev B and assembly 2003994-091, and distinguishes controlled envelope dimensions from digitized key centers. Its provenance needs the same treatment as other historical measurements.

The current validator allows 3 mm position and 0.25 degree normal differences for specified optical and mount datums. Reconstructed station surfaces allow 15 mm and 1 degree. These are existing software acceptance thresholds, not evidence of historical accuracy. Do not force a stronger primary-source measurement to agree silently with reconstructed geometry; reconcile the datum definition first.

**Imported controls are not currently rebound.** [loadArtistCabinIfAvailable](../../../LM/LMCommanderStationScene.swift:645) attaches the imported cabin and disables `proceduralCabin`. ACA, ROD, attitude mode, DSKY, and the live FDAI are built elsewhere under `cabinFrame` and remain separate. [Gesture handlers](../../../LM/TerminalDescentCockpitView.swift:310) and visual updates continue to use those procedural entity references. Imported names passing validation do not establish working input. Detailed imported control meshes could overlap the existing controls. The parent assignments are explicit: [DSKY assembly](../../../LM/LMCommanderStationScene.swift:1441), [ACA](../../../LM/LMCommanderStationScene.swift:1688), [ROD](../../../LM/LMCommanderStationScene.swift:1712), and [attitude mode](../../../LM/LMCommanderStationScene.swift:1728) are children of `cabinFrame`, so disabling their sibling `proceduralCabin` leaves them enabled. [DSKY key lookup](../../../LM/LMCommanderStationScene.swift:1608) compares entity identity against the procedural key dictionary while walking parents; matching an imported key name alone cannot satisfy it.

Before delivery, choose one integration approach explicitly. Recommended: retain simulation behavior but bind it to imported visual pivots and separate app-created hit targets. A transitional alternative is to use exported datums and static housings while retaining procedural moving parts. This requires an explicit visibility policy; dummy nodes alone do not define which renderer owns each part.

## Geometry and transforms

The following are proposed authoring rules, not claims that Blender exports every setting identically across releases.

| Item | Proposed contract | Reason and verification |
|---|---|---|
| Units | Real meters; USD `metersPerUnit = 1` | USD falls back to 0.01 when unauthored. Check transformed dimensions as well as metadata. |
| Orientation | USD Y-up, forward -Z, right +X | Matches the application. Verify with labeled axis markers and asymmetric cabin features. |
| Root | One `LM_Cabin`, identity scale, declared origin | Compare child transforms relative to the imported root used by the validator. Avoid hidden export wrappers changing the datum basis. |
| Moving part | Dedicated transform parent at actual hinge/shaft/ball center, mesh below it | Runtime rotation/translation must preserve housing and panel position. |
| Static geometry | Join compatible fixed pieces where profiling supports it | Preserve boundaries needed for material changes, instrument animation, and source traceability. |
| Naming | Stable ASCII names, unique across the asset | Existing lookup uses names. Avoid accidental `.001` suffixes and import-generated ambiguity. |
| Calibration | Dedicated nonrendering transforms; visible temporary calibration mesh in test exports | Confirm the exporter preserves required empty transforms. Do not assume viewport-hidden helpers survive export. |

USD uses stage-wide linear-unit metadata; scale transforms can change the effective dimensions. USD also defines a right-handed coordinate system with a stage-wide Y or Z up axis. These declarations need consistent geometry, not just edited metadata. [OpenUSD: Linear units](https://openusd.org/release/api/group___usd_geom_linear_units__group.html), [OpenUSD: Up axis](https://openusd.org/23.02/api/group___usd_geom_up_axis__group.html)

Blender's official USD documentation describes exporting `.usdz` packages with texture dependencies and approximating Principled BSDF through USD Preview Surface. Blender 4.4 release notes explicitly document unit controls and the parent-Xform merge option. Record the actual installed Blender version and freeze a tested export preset before production. Direct fetches of the English manual returned access errors during this research; the official indexed manual and release notes supplied the verified settings. [Blender USD manual](https://docs.blender.org/manual/en/latest/files/import_export/usd.html), [Blender 4.4 pipeline release notes](https://developer.blender.org/docs/release_notes/4.4/pipeline_assets_io/)

## Proposed hierarchy extension

Keep existing required names. Add independently addressable moving parts and separate interaction proxies, with these names treated as proposals until the app binder exists:

```text
LM_Cabin
  Panel_1
    Control_<stable_id>
      Control_<stable_id>_Housing
      Control_<stable_id>_Pivot
        Control_<stable_id>_MovingMesh
      Control_<stable_id>_Legend
      Control_<stable_id>_Indicator
  FDAI_Mount
    FDAI_FixedBezel
    FDAI_BallPivot
      FDAI_BallMesh
    FDAI_RateNeedle_<axis>
    FDAI_ErrorNeedle_<axis>
  DSKY_Mount
    DSKY_Face
    DSKY_Display_Mount
    DSKY_Key_VERB
      DSKY_Key_VERB_Mesh
```

Create hit targets in code or a separately identified subtree. Do not make them visible cabin geometry. All exported entity names should remain globally unique within the cabin, including decorative children. The schematic `<stable_id>` and `<axis>` placeholders must expand to concrete unique values. Record full paths in the manifest as well; this does not change the current name-based validator.

Proposed DSKY parenting decision: make `DSKY_Face`, `DSKY_Display_Mount`, and all 19 `DSKY_Key_*` nodes direct children of `DSKY_Mount`, as shown above and as the current procedural DSKY does. `DSKY_Face` is the fixed face mesh, not the assembly root. Keycap meshes belong under their respective key transforms. Do not parent keys under `DSKY_Face` or directly under `LM_Cabin` in the production contract. The current validator searches recursively by name and does not enforce these parent relationships, so passing it is insufficient to confirm this hierarchy. The future binder should verify parent paths and transform bases explicitly.

A sidecar manifest should record each stable control ID, exact node path, panel number, printed legend, source citation/page/photo region, mission applicability, measurement confidence, neutral transform, motion axis, detent/state list, permitted travel, spring return, guard dependency, indicator relationship, and simulator binding status. Use `unverified` for unknown travel or circuit behavior. Do not assign a functioning simulation effect merely because a switch can animate.

The current FDAI implementation already separates the ball from fixed markers. [buildPhysicalFDAI](../../../LM/LMCommanderStationScene.swift:1539) loads the ball and attaches fixed reference markers separately; [FDAIPanel.swift](../../../LM/FDAIPanel.swift:22) contains attitude conversion. Preserve that distinction. The bezel, indices, ball, and independently driven needles must not share a single rotating mesh.

## Materials, labels, and displays

Recommended initial material path: texture-backed metallic/roughness PBR compatible with USD Preview Surface. Bake unsupported procedural shading into textures where needed. Keep engraved/printed legends sharply readable at actual viewing distance. Preserve original image references separately from cleaned texture artwork so retouching cannot masquerade as evidence.

Model silhouettes, switch guards, protrusions, edges, and recesses that affect hand clearance or close stereo viewing. Use texture detail for small fixed markings when it holds up on device. Determine texture resolution from measured label readability and memory usage; no universal polygon or texture budget is established here.

Keep indicator lenses and display regions independently addressable. Reserve DSKY display geometry for live content; a baked photograph cannot show changing readouts. Treat luminous digits, warning lamps, and exterior daylight as separate lighting problems. Test normals, UVs, roughness, label contrast, emissive intensity, and transparent window panes in the actual renderer. Use a small representative panel to qualify the material pipeline before texturing the whole cabin.

## Interaction constraints

RealityKit input targets need both `InputTargetComponent` and collision shapes. Apple documents that input configuration can inherit down a hierarchy; the hit shape defines where interaction occurs. Collision filters can disable physics collisions while retaining input targets. Prefer simple purpose-built shapes to detailed mesh collision for controls. [Apple: InputTargetComponent](https://developer.apple.com/documentation/realitykit/inputtargetcomponent)

Add hover feedback to selectable controls and route gestures to the intended entity. Apple demonstrates this with SwiftUI gestures on `RealityView`. [Apple: Responding to gestures on an entity](https://developer.apple.com/documentation/realitykit/responding-to-gestures-on-an-entity)

Historical switch spacing will conflict with comfortable eye targeting in some areas. Apple's guidance is at least 60 points of space per precise target, approximately 2.5 degrees or 4.4 cm at one meter for fixed-scale 3D objects. This is interaction guidance, not a reason to enlarge the historical mesh silently. [Apple WWDC25: Design hover interactions for visionOS](https://developer.apple.com/videos/play/wwdc2025/303/)

Recommended tests include direct interaction near the panel, nonoverlapping indirect targets, and an optional native enlarged control view for dense banks. Test neighboring switches together; enlarging every collision shape can make selection ambiguous. Guards, pull-to-unlock actions, momentary switches, and rotary detents need explicit state machines. A general free-object manipulation gesture is not an adequate control model. Verify release and cancellation return spring-loaded controls to their documented state.

## Validation plan for the first representative panel

1. Build an untextured sample containing one guarded toggle, one rotary, a momentary key, an indicator, an instrument pivot, and calibration markers. Establish physical dimensions and source confidence before detailing.
2. Export using a recorded Blender version/preset. Inspect names, hierarchy, transformed dimensions, stage metadata, materials, and packaged texture paths. Reimport to a clean scene to catch missing dependencies.
3. Run the available OpenUSD structural checker and inspect supported flags for that installed version. Check current Apple renderer support before adopting advanced USD features. A file-format pass does not prove app behavior.
4. Load through `LMCockpitAssetContract.validate`; inspect root wrappers, name uniqueness, and all datum results. Add checks for duplicate names, pivot transforms, and moving-part identity in the future binder.
5. Wire the sample controls to a test state model. Verify detents, limits, guard order, momentary release, cancellation, correct entity targeting, and no duplicate procedural geometry.
6. Inspect in Reality Composer Pro, the app simulator, and an actual Vision Pro. Device checks must cover seated/standing reach, both hands, label reading, neighboring target mistakes, window depth, and close inspection. Simulator success alone cannot establish eye/hand usability.
7. Measure loading, memory, frame timing, and interaction reliability with the rest of the cabin and terrain active. Set asset budgets from those measurements. Record device, OS, tool versions, asset hash, and app commit for every acceptance run.

Open questions before modeling the complete cabin: exact mission configuration, resolved physical datum set, app ownership of imported controls, full LMP/right-wall coverage beyond the current six-panel contract, dense-control interaction mode, and the minimum supported visionOS/toolchain versions. Each should become an explicit decision in the model manifest.
