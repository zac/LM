# Terrain realism plan: sharper craters, photo-derived geometry, Artemis-style rendering

Self-contained work plan for the next phase of the Apollo 11 terrain pipeline.
It assumes no prior conversation context. Read
`Docs/LunarTerrainPipeline.md` first for the full pipeline description; this
document only summarizes what is needed to act.

Motivation: recent Artemis II far-side photography shows two things the
current renderer does not deliver. First, real crater rims are sharp; ours
render rounded ("curvy") because rim detail below ~4-6 m is missing from the
source DTM and our synthetic craters are placed by hash rather than where the
photos show craters. Second, the Artemis photographic aesthetic — a genuinely
dark charcoal surface, highlights protected, shadows crushed nearly black with
faint directional fill (earthshine) — reads far more like the real Moon than
our current flat-lifted look. Both are addressable within the existing
fidelity contract.

## 0. Status board (update this when you land work)

| Workstream | State | Notes |
|---|---|---|
| A — photo-seeded craters | **Integrated; visual QA pending** | The reviewed 1,200-entry catalog is pinned and live in render/contact geometry. Surface/landing A/B captures remain. |
| B1 — radiance-conserving LOD | **Done; measured neutral** | The current hierarchy-corrected handoff measures −0.16% calibrated, −0.12% photographic, and +0.79% with constant reflectance/no normal maps. A material gain would create a step, so the sun-independent statistics remain a validation guard rather than an applied tint. |
| B2 — photographic grade | **Done** | Opt-in `photographic` grade: exposure floor removed, ephemeris-driven earthshine fill scaled by Earth phase, exposed for highlights. Calibrated grade pixel-identical; lunar night renders. See `LMTerrainPresentationGrade`. |
| C — shape-from-shading DTM | Not started | Needs owner sign-off on the provenance question first. Now also slotted as Stage 4 material in `Docs/LandAnywhereMoonPlan.md`, which extends this plan's A/B1 machinery to global scale. |

**Workstream A, precisely where it stands.** The deterministic detector has
produced `LM/Terrain/apollo11-nac-craters-v1.json`: a conservative,
human-reviewed set of 1,200 correlations between 2 and 8 m within 900 m of the
landing origin. `TerrainManifest.json` schema v3 pins its SHA-256, detector
SHA-256, source IDs, acquisition-illumination parameters, thresholds, and
density cap. `Apollo11TerrainResource` verifies the file digest and embedded
provenance before attaching the catalog to the shared height field. The
default `LMProgressiveTerrainSampler` therefore feeds the same versioned
catalog to Explorer meshes, descent rendering, dust queries, and the landing
contact surface. The base geology version is now
`surveyor-degraded-microrelief-v3`; the runtime ID also includes the catalog
and detector versions.

Focused validation is green for the detector, catalog, manifest, measured-post
anchoring, Lunar Explorer, and terrain-relative landing/contact suites. The
remaining Workstream A acceptance item is visual: capture procedural and
neural `surface`/`landing` A/B pairs, verify the photographed crater positions
and sharper rims, and watch for false positives or excessive density. The
catalog begins at 2 m while `LMRegolithMicrotextureModel` ends at 0.20 m, so
there is currently no size-band overlap requiring a second reflectance halo.

**Workstream B1, precisely where it stands.** Each baked detail tile carries
a compact, sun-independent directional distribution of its exact tangent-space
micro normals. The statistic is preserved unchanged by the neural appearance
reconstructor, the byte-bounded cache contract, and final sampling-gutter
padding. Progressive mesh generation separately records the directional slopes
of the exact geomorphed height band introduced relative to the live parent.
Arbitrary-sun response and both handoffs are covered by focused tests. A fresh
2 m / 8 m capture set on 2026-09-01 segmented the actual terminal/landing edge
with `Tools/TerrainGenerator/measure_radiance.py`. The adjacent-band step was
−0.155% calibrated, −0.120% photographic, and +0.794% with constant
reflectance and normal maps off. The full-resolution touchdown distributions
independently predict a combined response ratio within 0.03% of flat. Those
measurements reject the earlier 5–6% compensation hypothesis for the current
renderer. No material multiplier was applied, no cache key became sun-dependent,
and granularity is unchanged. Keep the statistics: Stage 2's much wider global
LOD ladder must pass the same test and may need the originally designed
material-time correction.

**Cross-plan note.** The old 276.4-degree anti-solar manifest azimuth has been
replaced by the ephemeris touchdown direction (88.819 degrees azimuth,
10.689 degrees elevation). B1 and B2 now evaluate the same corrected Sun.

## 1. Non-negotiable contracts

These are the standing rules of this codebase. Violating any of them is a
plan failure, not a judgment call.

- **Measured terrain is authoritative.** Procedural detail adds only
  frequencies below the best available source resolution and never moves a
  measured sample. Same coordinate + same generator version = same result,
  always.
- **Procedural relief reaches the landing-gear contact surface** (deliberate;
  bounded to a 0.24 m residual, exactly zero at every measured LROC post).
  Rendered terrain and contact geometry must remain aligned — no vertical
  render offsets, ever.
- **The runtime neural path (`LunarTerrainSR`) is appearance-only.** It must
  never alter geometry, normals, contact, coordinates, or landing physics.
  The procedural path is the correctness baseline and must remain exactly
  reproducible.
- **`LMRegolithMicrotextureModel` stays strictly appearance-only** (never in
  the mesh or contact surface). Synthetic rocks stay non-colliding.
- **Offline source changes are allowed but must be versioned.** A new bundled
  DTM or a new generator crater-seeding scheme is a generator/manifest version
  bump with pinned provenance in `LM/Terrain/TerrainManifest.json`, not a
  silent behavior change.
- Every source input is pinned by PDS byte range in the manifest; new inputs
  (e.g. crater catalogs derived from the NAC ortho-images) must be pinned the
  same way.

## 2. Where the pipeline stands (as of 2026-09-01)

Summary of the measured investigations (visual diagnoses were deliberately
reopened when later controls contradicted them):

- The earlier close-surface card was a **grazing-sun geometry-shading step at
  residency-footprint perimeters**. Roughly 92% of that boundary luminance
  step survived the then-current constant-reflectance/no-normal control. The
  residency nesting fix below reduced that defect to under ±0.5 gray levels.
- A separate card-shaped defect remained in the final 2026-09-01 Surface
  ladder. This one survived removal of tangent-space normals, procedural
  reflectance modulation, mipmaps, and appearance collars, while a
  constant-reflectance control was clean. CPU-baked shared edges were exact.
  The cause was albedo registration: `CGImage` rows are north-to-south but
  RealityKit texture V is bottom-to-top, so every tile sampled vertically
  mirrored measured reflectance. Mapping the mesh's north row to V=1 removes
  the cards in the full production material. Tests now pin the UV orientation,
  exact north/south shared-edge bytes, and adjacent measured narrow bands.
- **Fixed:** residency nesting. `LMProgressiveTerrainPlanner` (see
  `coverageRadiiMeters(finestSpacing:)` in `LM/LMProgressiveTerrain.swift`)
  now makes each coarser active level enclose the finer footprint by at least
  its own morph collar (terminal coverage radius 16 → 32 m while the landing
  level is active). Local seam steps dropped from −4.3 to under ±0.5 gray
  levels. Guarded by test
  `coarserResidencyEnclosesFinerFootprintByItsOwnMorphCollar()`.
- **Resolved after the hierarchy/ownership corrections:** the earlier broad
  landing-footprint average suggested a ~5–6% LOD loss, but it compared
  different lunar features rather than adjacent samples at the handoff. The
  repeatable 2026-09-01 narrow-band measurement is under 1% in calibrated,
  photographic, and constant/no-normal controls. Whole-region means remain in
  the report for context, but are not an LOD acceptance metric.
- Capture-only diagnostics now exist (all opt-in launch arguments, all in
  `LM/LMTerrainWorld.swift`):
  - `--lunar-explorer-terrain-reflectance=constant` — flat 0.25 albedo,
    isolates geometry shading from reflectance.
  - `--lunar-explorer-normal-maps=off` — disables baked tangent-space normal
    maps.
  - `--lunar-explorer-tile-tint=id` — paints every progressive tile by level
    hue + grid parity; maps any rendered rectangle to a concrete tile.
- A/B capture harness: `Tools/CaptureLunarExplorerAB.sh` (simulator UDID used
  recently: `8F38C0E7-6366-4DAC-9372-DCF6F9151DCB`).

Current lighting/material constants that matter to this plan
(`LM/LMTerrainWorld.swift`): mission sun 25,000 lux (real lunar surface
sunlight is ~133,000 lux); every terrain material carries an
illumination-independent emissive floor `regolithExposureFloor = 0.08`
(reflectance texture × 0.08 as emissive). The floor uniformly lifts shadows;
it both creates the current flat look and *hides part of the LOD shading
mismatch* — see the dependency note in §6.

## 3. Workstream A — photo-seeded crater placement (recommended first)

**Goal:** sharp, correctly-located rims for craters that are visible in the
0.5 m NAC ortho-imagery but rounded or absent in the 2 m DTM (effective
resolution ~4-6 m after photogrammetric low-pass and bilinear interpolation).

**Idea:** keep the existing deterministic parametric crater morphology
(`LMLunarGeologyModel` bowls/rims with a `sharpness` parameter) but drive
crater *placement* from the photograph instead of (or blended with) hash
candidates. The photo says where the crater is and how big; the model says
what shape a crater of that size/freshness is; the anchoring contract keeps
measured posts fixed.

Steps:

1. **Offline crater detection** in `Tools/TerrainGenerator` (or a sibling
   tool): detect craters in the bundled/near-field NAC albedo. Classical
   detection (shadow/highlight pairing under the known sun azimuth + Hough or
   template matching) is preferred over ML for determinism and auditability;
   if ML is used, its output must be frozen into a versioned catalog, not run
   at build time nondeterministically. Output: a catalog of
   (east, north, diameter, freshness/sharpness estimate, confidence),
   in terrain coordinates, checked into `LM/Terrain/` and pinned in the
   manifest with the generator version.
2. **Deterministic seeding:** extend `LMLunarGeologyModel` so cataloged
   craters replace hash candidates within their footprint (suppress hash
   candidates that overlap a cataloged crater; keep hash candidates
   elsewhere so unphotographed/sub-detection-limit statistics stay on the
   Surveyor size-frequency slope). The residual stays bounded (0.24 m cap,
   zero at measured posts) via the existing anchoring. This changes contact
   geometry — that is allowed (procedural relief already reaches contact) but
   it is a generator version bump; bump the seed/version constant so caches
   and tests can't mix old and new realizations.
3. **Consistency check with the DTM:** where the DTM already shows the
   (rounded) crater, the catalog crater's parametric depth must be reconciled
   so combined relief doesn't double-dip (e.g. subtract the DTM's smoothed
   crater signal within the catalog crater's footprint before adding the
   parametric shape, or fit depth so the anchored result matches DTM posts —
   they are zero-residual constraints anyway, so the anchoring largely
   handles this; verify on the largest cataloged craters).
4. **Microtexture/albedo coupling:** `LMRegolithMicrotextureModel`'s
   reflectance haloes should use the same catalog for craters in its size
   band overlap, so bright haloes sit on the actual craters.

**Tests/acceptance:**
- Determinism: same catalog + version → byte-identical bakes (extend the
  existing determinism tests).
- Measured posts unmoved: existing `measuredPostsRemainExactAndProceduralDetailIsBounded`
  style invariants must keep passing.
- Visual: A/B captures at the `surface` and `landing` presets; cataloged
  craters must appear at their photographed positions with visibly sharper
  rims than the pre-change captures. Compare against
  `/tmp/LunarExplorer-after-nesting-procedural.png` (2026-08-30 baseline) or
  regenerate baselines with the harness.
- Landing physics: run the focused progressive-terrain and landing-surface
  test suites in `LMTests/LMTests.swift` (`ProgressiveLunarTerrainTests`);
  the gear/contact tests must pass with the new generator version.

## 4. Workstream B — radiance-conserving LOD, then the "photographic" mode

Two coupled pieces, in this order.

### B1. Radiance-conserving LOD (prerequisite)

**Historical problem statement:** an early broad-footprint comparison appeared
to show each finer level darkening mean shading ~5–6% at the mission's grazing
sun. The current adjacent-edge measurement rejects that hypothesis after the
residency, ownership, and hierarchy fixes.

**Approach:** compensate the fine tile's realized albedo by the expected
mean shading of its *added* relief octaves under the current sun, so mean
radiance is conserved across LOD levels.

**DECIDED 2026-08-30 — the sun is movable.** `Docs/MoonExplorerPlan.md`
makes an ephemeris-driven, user-facing date/time sun a product requirement
(multiple missions, each with its real lighting). Therefore do NOT bake
fixed-sun compensation into tile albedo. Structure it as:
- The baker already computes exact micro-relief slopes for the normal map.
  For the mesh-band octaves a tile adds relative to its parent
  (`samplingWeight` already defines exactly which frequencies those are),
  bake **sun-independent per-tile statistics** (per-band slope variance /
  directional slope distribution) alongside the textures.
- Evaluate the compensation ratio (added-relief shading / flat shading,
  clamped to a bounded range) **for the current sun direction at material
  realization time**, from those statistics. Fallback option if per-texel
  fidelity is needed: key the detail cache
  (`LMTerrainDetailStreaming.swift`) by quantized sun direction and rebake
  on large sun moves — bound the cache growth if so.
- The ephemeris has since landed (`LM/LMLunarEphemeris.swift`), so "the
  current sun" is available directly as
  `LMLunarEphemeris.sunAngles(at:site:)` for any instant. Note that the
  manifest's pinned azimuth is wrong (§0), so drive compensation from the
  ephemeris rather than from `manifest.sun`.
- The neural mode consumes the same compensated procedural bake path as its
  fallback/baseline; verify the neural/procedural A/B RMSE stays in family.

**Acceptance (passed 2026-09-01):** the tile-tint segmented narrow band at the
actual landing/terminal boundary is under 1.5% in both grades and in the
constant-reflectance/no-normal control. Whole-region means and high-pass SD
are still emitted to catch broader regressions, but do not compare like lunar
features. Captures: `/private/tmp/LandAnywhere-B1-before-tile-tint-calibrated.png`,
`/private/tmp/LandAnywhere-B1-before-calibrated.png`,
`/private/tmp/LandAnywhere-B1-before-photographic.png`, and
`/private/tmp/LandAnywhere-B1-before-constant-no-normals.png`. No geometry,
contact, albedo, material, calibrated baseline, or cache behavior changed.

### B2. Photographic presentation mode (Artemis-style)

**Goal:** an optional presentation-only mode that renders the Moon the way a
modern high-DR camera (or a dark-adapted eye) sees it: dark charcoal surface,
highlights protected, shadows nearly black with faint cool directional fill.

Levers, all in `LM/LMTerrainWorld.swift` unless noted:

1. **Replace the flat emissive floor with earthshine.** Remove (or reduce to
   near zero, in this mode) `regolithExposureFloor` and add a very dim
   directional fill light from Earth's direction — taken from the ephemeris
   table's sub-Earth point (`Docs/MoonExplorerPlan.md` Workstream 1) at the
   current scene time, since the sun is time-driven by decision (Earth sits
   high and nearly fixed over Tranquility Base, wandering only a few degrees
   with libration). Slightly blue-white, roughly 4 orders of magnitude below
   the sun; earthshine intensity should also scale with Earth's phase as
   seen from the Moon (opposite the lunar phase — full Earth over a new-Moon
   terminator), which the same table provides implicitly via the sun/Earth
   geometry. Shadows become directional and faint instead of uniformly
   lifted.
2. **Expose for highlights.** Raise sun illuminance from 25,000 lux toward
   the physical ~133,000 and let tone mapping roll off; Vision Pro has real
   EDR headroom. Tune so the sunlit surface reads dark gray (the Moon's
   albedo is ~7-12%), not white.
3. **Longer shadow distances** at low sun (`missionShadowDistance` currently
   clamps for performance) — the drama of terminator photos is long shadows.
   Profile on device before raising the clamp permanently.
4. **Neutral-dark tint** for the monochrome 643 nm reflectance proxy; avoid
   the warm lift of Apollo film scans.

**Constraints:** presentation-only. It must not change geometry, contact,
the calibrated baseline mode, or the neural/procedural comparison captures.
Implement as a launch argument + explorer/session setting (e.g.
`--lunar-explorer-grade=photographic`), default off, and add a column to the
A/B harness so both grades are captured. RealityKit on visionOS has no custom
post-processing chain in immersive spaces — do all of this with lights,
exposure, and material values, not screen-space effects.

**Acceptance:** side-by-side captures at `surface`, `landing`, `terminal`
presets in both grades; the photographic grade should show crushed-but-not-
empty shadows (earthshine detail visible on the dark side of relief),
no highlight clipping on sunlit slopes, and no new LOD banding (B1 done
first). Get a human eyeball on it before declaring it done — this one is
aesthetic.

## 5. Workstream C — shape-from-shading DTM refinement (longer term)

**Goal:** refine the 2 m DTM toward the 0.5 m resolution of the NAC
ortho-imagery using photoclinometry, recovering real (not parametric) rim
sharpness and small-feature morphology.

- Tooling: NASA Ames Stereo Pipeline's `sfs` tool is built for exactly this
  (LROC NAC + known sun vector + low-frequency constraint to the existing
  DTM). Run offline; do NOT build this into the app.
- Output: a refined DTM bundled as a **new versioned measured-quality
  source** in `LM/Terrain/` with full provenance (input image IDs, ASP
  version, parameters) pinned in the manifest. The runtime remains
  deterministic; the runtime neural path remains appearance-only. Note
  explicitly in the manifest/docs that this source is photo-derived, not
  direct stereo measurement — the project owner has final say on whether it
  is labeled "measured."
- Downstream effects to handle: the procedural geology's
  `minimumRenderableDiameter`/octave bands key off source spacing; with a
  0.5 m source the 0.5 m progressive level becomes redundant and the
  residual/anchoring constants need re-derivation. Contact geometry changes.
  Workstream A's catalog craters must be reconciled (a refined DTM may make
  many of them unnecessary — prefer the SfS surface where it exists).
- This is the heaviest workstream and partially supersedes A. Do A first
  anyway: it is cheap, and its catalog doubles as validation data for SfS
  output.

## 6. Sequencing and dependencies

1. **A** (photo-seeded craters) — independent, biggest sharpness-per-effort.
2. **B1** (radiance-conserving LOD) — independent of A; required before B2.
3. **B2** (photographic grade) — after B1. Benefits from A (sharp rims cast
   the dramatic shadows).
4. **C** (SfS) — after A lands and only with project-owner sign-off on the
   provenance question; reconcile with A on completion.

Also still outstanding from the previous phase (do not lose track):
full orbit-to-surface LOD-gate captures, and physical Vision Pro **Release**
performance profiling (Debug tile generation is already slow; the 24-tile
fine corridor exceeds the 32 MB detail-cache working set by design — see
`LMTerrainDetailStreaming.swift`). The terrain milestone is NOT complete
until those pass.

## 7. Validation protocol (use for every workstream)

- Build/test destination:
  `platform=visionOS Simulator,id=8F38C0E7-6366-4DAC-9372-DCF6F9151DCB`.
- Focused tests: `ProgressiveLunarTerrainTests` in `LMTests/LMTests.swift`
  (boundary morph, shared-edge detail, parent-triangle replacement, residency
  nesting), `LMTerrainDetailStreamingTests`, `LunarExplorerTests`.
- Captures: launch via `xcrun simctl launch --terminate-running-process
  <udid> io.positron.LM --lunar-explorer --lunar-explorer-preset=surface
  --lunar-explorer-altitude=2 --lunar-explorer-meters-across=8
  --lunar-explorer-detail=procedural --lunar-explorer-capture [flags]`,
  wait ≥90 s for Debug tiles to settle, `simctl io <udid> screenshot`.
  Full matrix: `Tools/CaptureLunarExplorerAB.sh`.
- Quantify, don't eyeball: segment regions with the tile-tint capture, then
  compare per-region mean luminance and local-contrast (high-pass sd) across
  boundaries, and measure narrow-band steps across specific edges. The
  2026-08-30 session used exactly this and it repeatedly overturned visual
  impressions.
- Baselines from 2026-08-30 (regenerate if stale): before
  `/tmp/LunarExplorer-parent-replacement-procedural.png`, after-nesting
  `/tmp/LunarExplorer-after-nesting-procedural.png`, residency maps
  `/tmp/LunarExplorer-tile-tint-*.png`.

## 8. Key files and symbols

| Area | Where |
|---|---|
| Progressive planner, levels, residency, morph | `LM/LMProgressiveTerrain.swift` (`LMProgressiveTerrainPlanner`, `coverageRadiiMeters`, `renderedElevation` morph at `distanceToEdge`/`morphWidth`) |
| Geology (mesh-band craters, contact-reaching) | `LM/LMProgressiveTerrain.swift` (`LMLunarGeologyModel`) |
| Tile mesh build, parent-quad removal, tangents | `LM/Apollo11TerrainResource.swift` |
| Appearance bake (albedo/normal, samplingWeight, collars) | `LM/LMTerrainDetailTexture.swift` (`LMTerrainTileDetailBaker`, `LMRegolithMicrotextureModel`, `LMMeasuredAlbedoField`) |
| Materials, sun, emissive floor, diagnostics flags | `LM/LMTerrainWorld.swift` |
| Detail pipeline + LRU cache (32 MB, keyed by model version + edges) | `LM/LMTerrainDetailStreaming.swift` |
| Neural appearance generator (appearance-only) | `LM/LMCoreMLTerrainDetailGenerator.swift`, `LM/LunarTerrainSR.mlpackage/`, `Tools/NeuralTerrain/` |
| Explorer scene / residency requests / presets | `LM/LunarExplorerScene.swift`, `LM/LunarExplorerSession.swift` |
| Offline generation & manifest | `Tools/TerrainGenerator/`, `LM/Terrain/TerrainManifest.json` |
| Contract documentation | `Docs/LunarTerrainPipeline.md` |
| Tests | `LMTests/LMTests.swift`, `LMTests/LMTerrainDetailStreamingTests.swift`, `LMTests/LunarExplorerTests.swift` |
