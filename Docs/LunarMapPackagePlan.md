# LunarMap package plan: one Moon renderer for two apps

Self-contained work plan. `LandAnywhereMoonPlan.md` remains the controlling
plan for terrain behavior; this document changes only where code lives and how
it is linked. All terrain, source, residual, contact and Apollo capture
contracts stay in force, and the extraction must be invisible to every
existing capture. Written 2026-09-07 against `7d2ee75` plus the withheld
A–E candidates; whichever of those land first, this plan applies on top.

**Goal:** the Moon map, terrain engine and Explorer product become a Swift
package, `LunarMap`, consumed by two apps: a new standalone **Moon** app and
the existing **LM** lunar-lander app. One renderer, one set of pinned assets,
one test suite, two thin app shells.

## 0. Status board (update when you land work)

| Step | State | Notes |
|---|---|---|
| 1 Package skeleton and file moves | Withheld on `lunar-map/step-1`; stopped by owner | Runtime `3e94add` on `89ecb0f`. Tests, Apollo, contracts and journey pass. Fresh soak peak exceeds gate by 1.563 MiB; warm-highland incomplete. See stop checkpoint in `LunarMapPackage.md`. |
| 2 Decouple the six seams | Development complete, `f1f9767` | Release build and 45 focused tests pass; long qualification deferred by owner |
| 3 Moon app target | Development complete on `lunar-map/step-3` | Release build and ordinary launch pass; both-ID tool tests pass; visual/performance qualification deferred |
| 4 Tests and tools move into the package | Not started | §4 |
| 5 Optional: `LunarMapCore` split for macOS-hosted tests | Not started | §4 |
| 6 Later: sibling repository split | Not started | §7 |
| Baseline P64 test exemption | Owner accepted | `p64PROAndACAChangeLuminaryLandingTarget` fails unchanged on control with the same AGC state; handed to cockpit owner; no changes to that test or AGC |

## 1. What exists today (refreshed 2026-09-08 after B)

- One Xcode project, `LM.xcodeproj`, two native targets: `LM` (app,
  `io.positron.LM`, visionOS 2.2, Swift language mode 5) and `LMTests`
  (app-hosted, `@testable import LM`). The `LM/` and `LMTests/` folders are
  `PBXFileSystemSynchronizedRootGroup`s: every file inside them is in the
  target; files moved out leave the target with no project edit.
- Two files are explicit references outside the synchronized folder, at the
  repo root: `LMTerrainSimulationGate.swift` (terrain publication gate, used
  by the map engine) and `LMLunarCockpitTerrain.swift` (cockpit consumer of
  the map engine).
- Local package `../AGC` (sibling repository) provides `AGC` (the Luminary
  emulator) and `LMCore` (`LMVector3D`, `LMQuaternion`, landing gear,
  `LMLandingSurfaceModel`). `LMCore` depends on `AGC`.
- Local package `Packages/RealityKitContent` is used only by cockpit and
  vehicle code, never by map code.
- Map resources live in `LM/Terrain` (177,473,236 bytes, 169.25 MiB; including the 76 MB 64 ppd JPEG
  XL and the pinned LDEM_16 base), plus `LM/LunarTerrainSR.mlpackage` and
  `LM/LunarTerrainMorph.metal`. `Tools/TerrainGenerator` writes to
  `LM/Terrain` by default.
- The `LM/` Swift inventory has 13 files reading `ProcessInfo`, including
  `LunarGlobe/LMLunarGlobeResource.swift`; the separate repo-root cockpit
  file has one additional read and remains in LM. Eight of those `LM/`
  files belong to the package inventory. There are 15 `"io.positron.LM"`
  literals across `LM/` and the root cockpit file, 12 in package-bound code.
  `LM/` has 21 `bundle: Bundle = .main` defaults, 16 in package-bound code;
  the package morph renderer also loads the default Metal library from `.main`.
- `LMTests/` contains **25 Swift files**, verified against the post-B tree,
  rather than the anticipated 24. `LunarExplorerPortalTests.swift` and
  `LunarExplorerHeightFieldPickerTests.swift` are present; the removed triangle
  tests do not have a standalone file. The exact list is retained in
  `/tmp/LM-LunarMap-2026-09-08/inventory-raw.json`.
- Capture tools hard-code the LM identifier and default app path. In addition
  to capture scripts, `MeasureMoonExplorerRuns.py`,
  `RunMoonExplorerComparison.sh`, `CaptureMoonExplorerColdHighland.sh` and
  `TestMoonExplorerMeasurements.py` must support `LUNAR_BUNDLE_ID` with
  `io.positron.LM` as the default. This preserves LM invocations while allowing
  the Moon app's container and log subsystem.
- `LMLunarTerrainTiming` (phase timing used by `PoweredDescentSession`) lives
  inside `LunarExplorerPerformanceProbe.swift`.

### Dependency direction, measured

Map code depends on `LMCore` for `LMVector3D`, `LMQuaternion` and the landing
gear in exactly these files: `LMTerrainManifest`, `LMTerrainWorld`,
`LMWorldMapper`, `LMTerrainLandingSurface`, `LMLunarLandingRehearsal`,
`LMLunarRockField`, `LunarExplorerScene`, `LunarExplorerSitePack`. No map
file imports `AGC`, `RealityKitContent`, or any cockpit type.

The cockpit depends on the map through `LMCommanderStationScene`
(`LMTerrainWorld`, `Apollo11TerrainResource`, `LMProgressiveTerrainPlanner`,
`LMProgressiveTerrainSurfaceSampler`, `LMTerrainDetailPolicy`,
`LMTerrainFrameAlignment`, `LMLunarTerrainRegion`, `LMLunarElevationStore`,
`LMLunarRockFieldResource`, `LMLunarRockFieldModel`,
`LMSelenographicCoordinate`), `LMLunarCockpitTerrain`
(`LMLunarTerrainPresentation`, `LMTerrainSimulationGate`),
`PoweredDescentSession` (`LMLunarTerrainTiming`, `LMTerrainSimulationGate`),
`TerminalDescentCockpitView` (`LunarExplorerPerformanceProbe`) and
`MainMenuViewModel` (`LunarExplorerSession`, `LMLunarNavigation.parse`).

The Explorer UI depends on the LM app in two files: `LunarExplorerView.swift`
(both its root view and its `LunarExplorerControlsWindow` wrapper read
`MainMenuViewModel`; the wrapper also opens the cockpit space and stops the
descent session) and `LunarExplorerButton`. The root view only obtains the
existing Explorer session from that environment value.

## 2. Package design

One package, in-repo, at `Packages/LunarMap`, next to `RealityKitContent`.
`swift-tools-version: 6.0`, `swiftLanguageModes: [.v5]` to match the app's
language mode, `platforms: [.visionOS("2.2")]`. Dependency on `../../../AGC`
for `LMCore` only.

| Target | Kind | Contents | Depends on |
|---|---|---|---|
| `LunarMap` | library | coordinates, ephemeris, sources, height fields, planner, mesher, morph, presentation, globe, appearance, rocks, contact, gate, timing; all pinned resources, the Metal kernels and the Core ML model | `LMCore`, RealityKit, Metal, CoreML |
| `LunarMapExplorer` | library | the Explorer product: session, scene, camera, gestures, browser, markers, saved views, probes | `LunarMap`, SwiftUI, ARKit |
| `LunarMapTests` | test | every map test moved from `LMTests` | `LunarMap`, `LunarMapExplorer` |

Access levels: use the `package` access modifier for everything shared
between `LunarMap` and `LunarMapExplorer`, and `public` only for what the two
apps and `LMLunarCockpitTerrain` consume (the list in §1). Do not blanket
`public` the engine; the compiler tells you the exact surface.

The first package compilation confirms two ownership corrections: the
height-field picker is consumed by `LMTerrainWorld` and belongs in the
engine. The unchanged `finerOwners` helper moves from `LunarExplorerScene`
to `LMLunarTerrainPresentation`, retaining MainActor isolation, because
both the engine and Explorer call it. This removes a circular dependency
without changing either calculation.

### File inventory

`LunarMap/Sources/LunarMap` (from `LM/` unless noted):

- Coordinates and time: `MoonCoordinateConverter`, `LMLunarEphemeris`.
- Sources and catalogs: `LMTerrainManifest`, `LMLunarElevationCatalog`,
  `LMLunarElevationGrid`, `LMLunarElevationStore`, `LMLunarElevationPreview`,
  `LMLunarTerrainRegion`, `LMLunarTerrainResolver`, `LMLunarCraterCatalog`,
  `LMLunarNavigation` (POI catalog and great-circle math).
- Height fields, planning, meshing: `LMTerrainHeightField`,
  `LMTerrainHeightMap`, `LMProgressiveTerrain`, `LMTerrainMeshBuilder`,
  `Apollo11TerrainResource`, `LMLunarTerrainMeshSnapshot`,
  `LMLunarTerrainMorph`, `LMLunarTerrainMorphRenderer`,
  `LMLunarTerrainPresentation`, `LunarExplorerHeightFieldPicker`,
  `LMTerrainSimulationGate` (repo root).
- Appearance: `LMTerrainWorld`, `LMWorldMapper`, `LMTerrainDetailTexture`,
  `LMTerrainDetailStreaming`, `LMCoreMLTerrainDetailGenerator`,
  `LMLunarRockField`.
- Frames: `LMLunarFloatingOrigin`, `LMLunarAnchoredPlacement`.
- Globe: `LunarGlobe/LMLunarGlobeResource`, `LMLunarGlobeImagery`,
  `LMLunarImageryPyramid`, `LMLunarImageryTileStore`.
- Contact: `LMTerrainLandingSurface`, `LMLunarLandingRehearsal`.
- Diagnostics: `LunarExplorerPerformanceProbe` renamed
  `LMLunarTerrainDiagnostics` (frame probe plus `LMLunarTerrainTiming`).
- Resources: `Resources/Terrain/*` (all of `LM/Terrain`),
  `Resources/LunarTerrainSR.mlpackage`, and `LunarTerrainMorph.metal` as a
  source file (SwiftPM compiles it into the target's `default.metallib`).

`LunarMap/Sources/LunarMapExplorer`:
`LunarExplorerSession`, `LunarExplorerLibrary`, `LunarExplorerScene`,
`LunarExplorerView` (without `LunarExplorerControlsWindow`),
`LunarExplorerBrowser`, `LunarExplorerCamera`, `LunarExplorerPinchGeometry`,
`LunarExplorerSceneSnapshot`, `LunarExplorerSitePack`,
`LunarExplorerPortalGeometry` (landed with B),
`LunarExplorerMapGeometry`, `LunarExplorerPlaceMarker`,
`LunarExplorerPlaceDetails`, `LunarExplorerPlacementPanel`,
`LunarExplorerExperienceProbe`.

Stays in the LM app: `LMApp`, `MainMenuView`, `MainMenuViewModel`,
`LunarExplorerButton`, `LunarExplorerControlsWindow` (moved into its own file),
`LMLunarCockpitTerrain` (repo root), `LMCockpitWorldMapper`, every cockpit,
descent, DSKY, FDAI, vehicle and AGC file, `ImmersiveView`, `MoonScene`,
`Luminary099.bin`, and the `RealityKitContent` dependency.

Tests moving to `LunarMapTests`: every `LMTests` file except
`LMCockpitImmersionPolicyTests`, `LMLunarCockpitMissionTests`,
`LMLunarCockpitRestartTests`, `LMLunarCockpitStreamingTests` and `LMTests`.
`LMTerrainSimulationGateTests` moves with the gate. `LMTests.swift` also
contains map cases and suites, including frame statistics, source-backed
terrain, progressive terrain and detail textures. Split those cases into
package test files with `git mv` history for the moved content; retain cockpit
and descent-session cases in LM. If a moved test exercises
`LMLunarCockpitTerrain`, split that case back into `LMTests`.

## 3. The six seams to cut

1. **Resource bundle.** Every `bundle: Bundle = .main` default in map code
   becomes `bundle: Bundle = LunarMap.resources`, a `public static let`
   equal to `Bundle.module`. `LMLunarTerrainMorphRenderer` uses
   `device.makeDefaultLibrary(bundle: LunarMap.resources)`. Resource lookup
   passes `subdirectory: "Terrain"` where files now live in that folder.
   Keep the `.pngdata` extension on the P3 companion; SwiftPM `.copy` does
   not run the PNG optimizer, but the extension still documents the intent.
2. **Launch options.** Add `public struct LunarMapLaunchOptions` in
   `LunarMap`, constructed from `[String]` by the host app and passed to
   `LunarExplorerSession.configure(options:)`, `LMLunarTerrainTiming`, the
   probes, `LMTerrainWorld` and `LMLunarGlobeResource`. It carries every
   `--lunar-explorer-*`, `--lunar-globe-*` and profile flag that map code
   reads today; the ordered argument payload is retained so the existing session and
   capture parsers keep their exact precedence and duplicate-argument behavior.
   Profiling enablement is parsed once at construction. No map file calls `ProcessInfo.processInfo.arguments`
   afterwards.
3. **Log subsystem.** `public enum LunarMapLog { public static var subsystem }`
   defaults to `"io.positron.LM"` so existing `log stream` predicates and
   `Tools/Summarize*.py` keep matching; each app sets it at launch to its own
   bundle identifier. All 12 package-bound literals route through it; the three cockpit literals remain host-owned.
4. **Global mutable state.** `LMTerrainWorld.presentationGrade` and the
   static texture caches stay static (both apps are single-scene) but become
   `package`-scoped with a comment naming them as process-wide state.
5. **Explorer host actions.** `LunarExplorerControls` takes a
   `public struct LunarExplorerHostActions` with optional closures
   (`landInCockpit`, `close`) and a display name for the cockpit action. The
   LM app supplies them from its `LunarExplorerControlsWindow`; the Moon app
   supplies `close` only. `MainMenuViewModel` is never referenced from the
   package.
6. **Timing for the cockpit.** `LMLunarTerrainTiming` and
   `LMTerrainSimulationGate` become `public`, since
   `PoweredDescentSession` and `LMLunarCockpitTerrain` call them.

## 4. Steps and gates

**Owner development/integration decision, 2026-09-08:** finish steps 2–4 and
integrate the package into `terrain-realism-and-explorer`. Long capture,
soak and benchmark qualification is deferred and must stay explicitly listed
as outstanding. The previous soak peak failure remains recorded; it is not
reclassified as a pass. Use Release builds, focused tests and source/resource
audits for this development run. No new terrain behavior, step 5 or sibling
repository split is authorized by this change of priority.

**Test gate, owner restatement 2026-09-08:** each package step must preserve
the complete baseline control pass/fail set using the same AGC checkout
state. A changed outcome in either direction stops the step. Pre-existing
failures do not block extraction, but list each by name with unchanged-control
evidence. The sole exempted failure is
`PoweredDescentCheckpointSessionTests.p64PROAndACAChangeLuminaryLandingTarget`.
The control at `89ecb0f` has 316 passes and this one failure. AGC is at
`166b5860f19ea5a4ced0b0d6d36b4e779d530935`, with an uncommitted modification to
`Sources/LMCore/LMAGCPadLoad.swift`; the failure belongs to the cockpit owner.
This supersedes the earlier all-tests-pass wording in this plan.

Before step 1, create the acceptance baseline from the current build:
the eleven Apollo ladder PNGs, the seven-stage portal journey, the five-cycle
restore soak and the highland warm dive, all captured with the existing
scripts, plus the executable's Release performance tables. Every step below
is judged against these with the noise-aware rule in
`MoonExplorerOneZoom.md` (three control runs establish the spread; a step
uses only the named peak/hitch/callback gates, including the callback
ten-percent margin; settled mean/p99/max are ≤16.70 ms with zero misses).

1. **Package skeleton and file moves.** Create `Packages/LunarMap` with the
   manifest above. `git mv` the inventory in §2 (history must survive; use
   moves, never copy-and-delete). Remove the moved `LMTerrainSimulationGate.swift` repo-root reference
   from `project.pbxproj`; retain `LMLunarCockpitTerrain.swift`, which stays
   in the app at the repo root. Add the package to the LM target's dependencies and
   `import LunarMap` / `import LunarMapExplorer` where the compiler asks.
   Apply `package`/`public` from compiler errors only. Do not change
   behavior. Apply resource/log seams 1 and 3. The compiler-confirmed
   dependency corrections above also require moving the unchanged overlap
   helper and keeping the picker in the engine. Bring the mechanical host
   wrapper split into this step: keep the wrapper and its callbacks in LM,
   and pass the same existing session into `LunarExplorerView`. This corrects
   the original step ordering; it does not change launch behavior or introduce
   HostActions or launch options early. Compiler-required type annotations
   may disambiguate the existing capture-probe expression without changing
   its arithmetic or evaluation order; record that diagnostic and verify
   the same capture behavior.
   *Gate:* LM app builds Release; all 25 test files preserve the baseline outcome set in their current
   home (`LMTests` may `@testable import LunarMap` temporarily); eleven
   Apollo PNGs byte-identical; journey, soak and highland dive match the
   baseline visually and within the noise floor. Confirm the Metal kernels
   load from the package bundle and the Core ML model compiles from the
   package (`LunarTerrainSR.mlmodelc` present in the package bundle).
2. **Decouple the remaining seams** (2, 4, 5, 6). The mechanical
   `LunarExplorerControlsWindow` split is already required by step 1. Introduce
   `LunarMapLaunchOptions` and `LunarExplorerHostActions`. Retire every
   `ProcessInfo` read in the package.
   *Gate:* as step 1, plus `grep ProcessInfo Packages/LunarMap/Sources`
   returns nothing, and `grep MainMenuViewModel Packages/LunarMap` returns
   nothing.
3. **Moon app target.** Add a native target `Moon` (`io.positron.Moon`,
   folder `Moon/`, synchronized group) with `MoonApp.swift` (a
   `WindowGroup` hosting `LunarExplorerControls`, an `ImmersiveSpace` hosting
   `LunarExplorerView` with `.mixed`, `.progressive`, `.full`), a `MoonModel`
   owning one `LunarExplorerSession` and the space state, an `Info.plist`
   with the scene manifest, app icon placeholders, and the same automatic
   signing team. It depends on `LunarMap` and `LunarMapExplorer` only; it
   must not link `AGC`, `RealityKitContent` or any cockpit file. Configure
   `LunarMapLog.subsystem` to `io.positron.Moon` at launch.
   Parametrize the capture scripts: `LUNAR_BUNDLE_ID` (default
   `io.positron.LM`) replaces the hard-coded identifier in
   `get_app_container` and the `log stream` predicate.
   *Gate:* the Moon app runs the seven-stage portal journey and five-cycle
   soak with inspected images matching the LM app's; the eleven Apollo ladder
   PNGs captured from the Moon app are byte-identical to the baseline (the
   capture launch arguments must work in both apps); Release size of
   `Moon.app` reported; LM app gates from step 1 still pass.
4. **Tests and tools into the package.** Move the map tests to
   `LunarMapTests` with `@testable import LunarMap`; resource loading in tests
   uses `LunarMap.resources`. Run them with
   `xcodebuild test -scheme LunarMap -destination 'platform=visionOS Simulator,id=8F38C0E7-…'`.
   If a RealityKit-dependent test cannot run unhosted, keep that test in an
   app-hosted bundle in the Moon target and say which.
   Owner clarification: move map-only suites from `LMTests.swift` verbatim
   into files named after each suite. Change only imports and `Bundle.main`
   to `LunarMap.resources` within the moved blocks. Preserve every remaining
   cockpit/AGC test, especially the exempted P64 case, byte-identically apart
   from removed map blocks; record moved suites and show the residual diff.
   Point `Tools/TerrainGenerator` and `pin_lola_strips.py` at
   `Packages/LunarMap/Sources/LunarMap/Resources/Terrain`. Update
   `Docs/LunarTerrainPipeline.md` paths.
   *Gate:* same complete baseline test count and pass/fail set are preserved; no test remains that imports `LM` for map
   behavior; generator dry run writes to the new path.
5. **Optional: `LunarMapCore`.** Split the RealityKit-free files
   (coordinates, ephemeris, grids, catalogs, store, resolver, planner, morph
   math, floating origin, navigation) into a `LunarMapCore` target with
   `platforms` including macOS, so its tests run with `swift test` on the
   Mac in seconds instead of the Simulator. Membership is decided by
   compiling for macOS; files that import UIKit for `UIColor` or `CGImage`
   stay in `LunarMap` or get a two-line shim. Only do this after steps 1–4
   are landed and green.

## 5. Contracts

- Eleven Apollo PNGs byte-identical from both apps; pinned resource hashes
  unchanged; no terrain data, residual caps, contact geometry, source
  ordering or AGC changes. Moves are `git mv`.
- Capture launch arguments and `Tools/` scripts keep working for the LM app
  throughout; the Moon app gains them in step 3.
- The five protected method bodies in `protected-functions.json` stay
  text-identical apart from access-modifier keywords.
- Do not touch the two Xcode scheme-user files or
  `Packages/RealityKitContent` xcuserdata.
- One focused commit per step, repo commit style, no attribution lines.
  Update this status board and append a `Docs/LunarMapPackage.md` report per
  step: what moved, executable SHA-256 for both apps, test counts, the
  matched performance tables, inspected images, and what remains open.

## 6. Decisions for the owner

1. **`LMCore` dependency.** `LunarMap` needs `LMVector3D`, `LMQuaternion`
   and the landing gear from `LMCore`, and `LMCore` depends on `AGC`, so the
   Moon app links the AGC emulator without using it. Recommendation: accept
   for now (dead code, no runtime cost) and later split a `LMGeometry`
   product out of `LMCore` without the `AGC` dependency, moving the contact
   and rehearsal files into a `LunarMapLanding` target that keeps `LMCore`.
2. **Package location.** In-repo `Packages/LunarMap` first (atomic moves,
   one project). A sibling repository like `../AGC` is a later
   `git subtree split` once the API stops churning (§7).
3. **Bundle size.** Both apps ship the 169 MB pinned assets. On-demand
   resources or a downloadable 64 ppd tier is a separate decision; nothing
   here changes what is bundled.
4. **Log subsystem default.** Keeping `io.positron.LM` as the package default
   preserves every script and summarizer; each app overrides it. Confirm.

## 7. Later: sibling repository

When the Moon app is stable, `git subtree split --prefix=Packages/LunarMap`
produces a standalone repository with history; both apps then reference it
as a local sibling like `../AGC`, and later by version tag. The
`TerrainGenerator` and `NeuralTerrain` tools move with it, since they
produce its resources. Not part of this plan's gates.

## 8. Handoff prompt

```text
Execute Docs/LunarMapPackagePlan.md steps 1–4 in order, one commit per step,
starting from the current head of terrain-realism-and-explorer. Read
Docs/LandAnywhereMoonPlan.md §1–2 and Docs/MoonExplorerOneZoom.md's
noise-aware performance rule first. Before step 1, capture the acceptance
baseline named in §4 with the existing Tools scripts and freeze that build.
Use git mv for every move. Apply access modifiers from compiler errors only,
package-scoped between LunarMap and LunarMapExplorer, public only for the
consumer list in §1. Behavior does not change in any step; if a step needs a
behavior change to build, stop and report. After step 3, the Moon app must
reproduce the eleven Apollo ladder PNGs byte-identical using the same capture
arguments. Record evidence under /tmp/LM-LunarMap-<date>/ and write
Docs/LunarMapPackage.md per §5. Decisions in §6 are taken as recommended
unless the owner says otherwise. Do not start step 5 or §7.
```
