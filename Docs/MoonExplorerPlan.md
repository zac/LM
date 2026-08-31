# Moon Explorer plan: whole-Moon globe, map-style navigation, time-driven sun

Self-contained work plan for evolving the Lunar Explorer from an Apollo 11
site inspector into a whole-Moon experience — "Apple Maps for the Moon."
Read `Docs/LunarTerrainPipeline.md` (pipeline + fidelity contract) and
`Docs/TerrainRealismPlan.md` (in-flight realism workstreams A/B/C) before
starting; this document cross-references both.

**Vision:** open the Explorer and see the whole Moon as a globe. Pinch/drag
to orbit and zoom continuously from globe scale down to the 0.125 m Apollo 11
surface tiles. A SwiftUI control panel offers bookmarks (Apollo sites, famous
craters), selenographic lat/lon entry, search, debug toggles, and a sun
control that is either direct (azimuth/elevation) or driven by a real UTC
date/time through an ephemeris — so the terminator, and lighting at any site,
are astronomically correct.

## 0. Status board (update this when you land work)

| Workstream | State | Notes |
|---|---|---|
| W1 coordinates | **Done** | `LM/MoonCoordinateConverter.swift`: `LMSelenographicCoordinateSystem`, `LMSelenographicLocalFrame`, site projection, manifest integration. Tests: `LMTests/LMSelenographicCoordinateTests.swift`. |
| W1 ephemeris / time | **Done** | `LM/LMLunarEphemeris.swift`: subsolar + sub-Earth points, Moon-fixed directions, site horizon angles, Earth phase for earthshine. Tests: `LMTests/LMLunarEphemerisTests.swift`. Built analytically rather than as a SPICE-baked table — see §3. |
| W3 POI catalog / lat-lon entry / fly-to | Not started | Unblocked by W1. |
| W4 panel debug section | Not started | Capture-only diagnostics exist as launch flags; no runtime toggles yet. |
| W5 sun modes in the UI | Not started | The ephemeris behind it is done; nothing is wired to rendering yet. |
| W2 globe | Not started | Largest; do the Release profiling baseline first. |

Related, from `Docs/TerrainRealismPlan.md`: Workstream A (photo-seeded craters)
has landed its code path — `LM/LMLunarCraterCatalog.swift`, catalog seeding in
`LMLunarGeologyModel`, `Tools/TerrainGenerator/detect_craters.py` — but **no
catalog data has been generated, pinned, or loaded at runtime**, so it is inert
in the app today.

### Open finding: the pinned mission sun azimuth is wrong

Evaluating the new ephemeris at Apollo 11's touchdown
(1969-07-20 20:17:40 UTC, Tranquility Base) gives:

- elevation **10.69 degrees** — matching the manifest's pinned 10.77 and the
  mission-reported 10.8 within the model's tolerance, and
- azimuth **88.8 degrees** (Sun low in the *east*, local morning, climbing
  about 0.5 degrees per hour after a sunrise roughly 19 hours earlier).

The manifest pins **276.4 degrees**, which is the anti-solar direction; its own
note calls that value "azimuth approximated west-southwest". The elevation
match is what proves the sign convention: a subsolar point west of the site
would put the Sun *below* the horizon at that instant rather than 10.7 degrees
above it.

Consequence: every render to date has its shadows pointing the wrong way. The
LOD and seam work is unaffected (it is azimuth-agnostic), but mission lighting
is not currently mission-accurate. **Correcting the manifest is deliberately
left as a separate decision** because it moves every shadow in every existing
capture baseline; it should land together with W5 so the value becomes derived
from the ephemeris rather than re-typed. Until then
`LMTests/LMLunarEphemerisTests.swift` documents the discrepancy.

## 1. What exists today (read before designing)

- `LM/LunarExplorerScene.swift` / `LunarExplorerSession.swift` /
  `LunarExplorerView.swift`: a tabletop RealityKit presentation of the
  Apollo 11 terrain patch. `@Observable` session with presets
  (`orbit` 30 km / `regional` 7.5 km / `approach` 1.2 km / `terminal` 180 m /
  `landing` 40 m / `surface` 2 m altitude), focus offsets in site-local
  meters, heading/tilt, logarithmic zoom, orbit/pan navigation modes,
  procedural/neural detail mode, mission-shadow toggle, and a diagnostics
  struct (tile counts, finest spacing, generation timings).
- The SwiftUI controls window (`LunarExplorerControls`) already has pickers,
  sliders, and toggles — extend it, don't replace it.
- Terrain is **planar, site-centric ENU** around the Apollo 11
  retroreflector: near field 2 m posts over ~2 km, medium 32 m over
  16.384 km, far 512 m over 262 km (SLDEM2015-derived), plus progressive
  0.5 m / 0.125 m clipmap tiles near the surface. There is no global/spherical
  representation. (Investigate before building: how the far band treats
  curvature — the flight side treats altitude spherically, see project
  memory `lm-agc-altitude-is-spherical-not-terrain`.)
- The sun is a single fixed mission sun from the manifest
  (`sunDirectionENU`, rendered at 25,000 lux in `LM/LMTerrainWorld.swift`).
- Capture automation and diagnostics flags exist (see
  `Docs/TerrainRealismPlan.md` §2 and `Tools/CaptureLunarExplorerAB.sh`).

## 2. Contracts (inherited + new)

All contracts in `Docs/TerrainRealismPlan.md` §1 apply unchanged (measured
authority, determinism, appearance-only runtime neural, versioned/pinned
sources). New ones for this effort:

- **The globe never invents detail.** Every rendered globe texel/vertex comes
  from a pinned global product (LROC WAC mosaic, SLDEM2015/LOLA). Procedural
  sub-resolution detail stays confined to enhanced site patches where the
  existing contract governs it.
- **One coordinate authority.** All positioning flows through a single
  selenographic module (Workstream 1). No ad-hoc lat/lon math scattered in
  views.
- **Site patches remain authoritative where they exist.** At Apollo 11 (and
  future site packs) the globe hands off to the existing planar patch; the
  handoff must be seam-managed like every other LOD gate and validated with
  the same capture protocol.
- **Time-driven sun must be provenance-pinned.** Ephemeris data is generated
  offline from named NAIF/SPICE kernels with versions recorded in the
  manifest, same discipline as terrain sources.

## 3. Workstream 1 — selenographic coordinates and time foundation

**Status: done.** Kept as the specification of record; the notes below mark
where the implementation deliberately diverged.

Everything else depends on this. Build it first, as a small pure module with
exhaustive tests (no RealityKit imports).

1. **Frames.** Adopt the IAU Mean Earth/Polar axis (ME) frame, sphere radius
   1,737,400 m for rendering datum (LOLA products are radii; keep elevation =
   radius − 1,737,400 following the products' own conventions — verify against
   how `Tools/TerrainGenerator` already interprets SLDEM).
2. **Conversions.** lat/lon/height ↔ Moon-centered ME Cartesian ↔ the
   existing site-local ENU (the manifest pins the Apollo 11 LRRR anchor,
   ~0.6734°N, 23.4731°E — take the exact value from the manifest, don't
   re-type it). Round-trip tests to sub-millimeter at the site, and tests
   that the existing terrain frame alignment (`LMTerrainFrameAlignment`)
   agrees with the new module at the anchor.
3. **Precision.** CPU math in `Double` (codebase style). Rendering must be
   origin-relative: RealityKit positions are Float32, and a Moon-radius
   coordinate (1.7e6 m) has ~0.2 m float granularity — unacceptable at
   surface scale. Keep the current pattern: the world entity is repositioned
   so the focus is at the local origin; globe chunk meshes are built in
   chunk-local coordinates.
4. **Time → sun (and Earth) direction. — DONE, by a different route than
   specified.** The plan called for a SPICE-baked table with an analytic
   Meeus model as the cross-check. That order was inverted: `LMLunarEphemeris`
   evaluates the analytic series directly, which removes the kernel
   toolchain, the bundled table, and its interpolation error while meeting
   the stated accuracy target. A tabulated DE440 product can replace the
   internals behind the same API if sub-arcminute accuracy is ever needed.
   - Method: abbreviated ELP lunar terms (Meeus ch. 47), low-precision solar
     position (ch. 25), and the physical-ephemeris libration construction
     (ch. 53) evaluated for both the Earth and the Sun as seen from the Moon.
     Optical libration in full; physical libration (bounded at ~0.04°)
     omitted. Documented tolerance: `angularToleranceDegrees` = 0.1°.
   - Output is selenographic (ME frame) subsolar and sub-Earth points, so the
     coordinate authority from step 2 does every frame conversion. Nothing in
     the ephemeris knows about RealityKit or site frames.
   - **Validation anchor met, with a caveat:** at 1969-07-20 20:17:40 UTC the
     computed sun elevation at the Apollo 11 site reproduces the manifest's
     pinned value; the computed *azimuth* does not, because the pinned
     azimuth is wrong. See the open finding in §0.
   - Physical invariants are asserted rather than golden values: subsolar
     latitude inside the axial tilt, sub-Earth point inside the libration
     envelope, strictly westward terminator sweep at 12.19°/day, Sun overhead
     at its own subsolar point, and complementary Earth/Moon phases.
   - The sub-Earth direction and `earthIlluminatedFractionFromMoon` feed the
     earthshine light in the photographic grade
     (`Docs/TerrainRealismPlan.md` §4 B2) — same module, free win.

## 4. Workstream 2 — whole-Moon globe rendering

**Approach:** a chunked-LOD quad-sphere (cube-sphere quadtree), parallel to —
not replacing — the planar site clipmap. Each face quadtree node is a mesh
chunk built from the global DTM pyramid with the global reflectance pyramid
as its texture. Split/merge by screen-space error against the current zoom.
This is deliberately a second, simpler LOD system: the existing
`LMProgressiveTerrainPlanner` machinery stays untouched for site patches.

1. **Offline data pyramids** (extend `Tools/TerrainGenerator`):
   - Reflectance: LROC WAC global 643 nm normalized mosaic (~100 m/px full
     res). Full-res global is ~6-7 GB — too large to bundle whole. Build a
     tiled mip pyramid; **bundle** levels down to ~400-800 m/px globally
     (~100-400 MB, budget decision below) plus full 100 m/px only inside
     regions of interest (bookmark surroundings). Design the tile store so a
     future on-demand download pack can fill in full-res globally without
     format changes.
   - Elevation: SLDEM2015 128 ppd global (~237 m/post, ~2 GB raw) →
     tiled 16-bit pyramid, bundled to a chosen level (globe geometry needs
     far less than reflectance: ~1-2 km/post suffices above ~100 km
     altitude; finer levels only in ROI tiles). Poles: SLDEM lacks poles —
     fill from LOLA LDEM polar products; pin both.
   - All tiles content-addressed and pinned in the manifest (byte ranges or
     hashes), same discipline as existing sources.
   - **Budget targets (verify, don't trust):** ≤500 MB added bundle size
     total for the base globe; measure and get owner sign-off before raising.
2. **Runtime chunk system** (new files, e.g. `LM/LunarGlobe/*.swift`):
   quadtree residency by screen-space error; async chunk mesh build (reuse
   the generation-task/token pattern from `LunarExplorerScene`); crack
   suppression via skirts (simplest) or edge-index stitching; per-chunk
   normal generation from the DTM level actually used. Frustum + horizon
   culling (a globe hides half of itself).
3. **Materials:** same `terrainMaterial` path (sRGB/linear handling and the
   photographic-grade work all carry over). Terminator rendering comes free
   from the directional sun + normals; verify tone at globe scale against
   real photography (the crescent reference shots).
4. **Globe ↔ site patch handoff:** above a gate altitude (initial guess
   ~40-60 km, tune by eye) render globe only; below it at an enhanced site,
   the existing planar patch fades in exactly like today's LOD gates
   (`presentationBlend` pattern). The patch must be positioned via
   Workstream 1 so its ENU frame sits on the globe within one far-band post.
   Non-enhanced locations simply keep the globe's finest ROI level all the
   way down (it will look like ~100-200 m imagery — that's honest).
5. **Tabletop presentation:** globe scale ≈ 0.28 m radius at the default
   panel distance (fits the existing `presentationRoot` at −2.35 m); zoom
   continuously re-scales as today via `presentationScale` /
   `metersAcross`. The `orbit` preset becomes a true globe view; add a
   `globe` preset above it (whole disk visible).

## 5. Workstream 3 — map-style navigation and points of interest

1. **Gestures:** extend the existing orbit/pan/zoom (`setOrbit`, `pan`,
   `zoom(by:)`) to globe mode: orbit = rotate globe (lat/lon of the focus
   point changes), pan = great-circle drag, zoom = altitude change with
   automatic tilt easing (high altitude → top-down; low → the preset tilt
   curve that already exists). Inertia/damping to taste; keep
   `orbitAndPanStayInsideInspectionBounds`-style tests.
2. **Fly-to:** animated camera transitions (lat/lon/altitude/heading tuples
   with eased great-circle interpolation). Everything below uses fly-to.
3. **POI catalog:** bundled JSON (`LM/Terrain/MoonPOI.json` or similar),
   versioned, with fields: id, display name, category (apollo, crater, mare,
   mountain, spacecraft), lat, lon, suggested altitude + heading, blurb,
   source. Seed set:
   - Apollo 11–17 landing sites (take coordinates from NASA/LROC published
     site coordinates; A11 must equal the manifest anchor).
   - Surveyor / Luna / Chang'e / recent landers (optional second pass).
   - Famous features: Tycho, Copernicus, Aristarchus, Kepler, Plato,
     Clavius, Shackleton (south pole), Mare Tranquillitatis, Montes
     Apenninus, Vallis Schröteri, Hertzsprung and Vavilov (the Artemis II
     far-side photos that motivated this plan).
   - Verify every coordinate against the USGS Gazetteer of Planetary
     Nomenclature; record the source per entry.
4. **Search + lat/lon entry:** search field filters the catalog by name; a
   coordinate field accepts `lat, lon` in decimal degrees (N/E positive) and
   flies there. Show the current focus coordinate live in the panel (and a
   copy button) — this makes every debugging conversation about "where"
   precise.
5. **Site packs (forward-looking, don't build yet):** the Apollo 11 patch is
   the template for per-site enhanced packs (other Apollo sites have LROC
   NAC DTM/ortho products). The globe/POI/handoff design must not hard-code
   "there is exactly one enhanced site" — keep it a list.

## 6. Workstream 4 — editor / debug panel

Extend `LunarExplorerControls` (SwiftUI) with collapsible sections. Keep the
capture launch arguments working (CI/scripts rely on them); the panel toggles
the same underlying session state at runtime.

- **Navigate:** POI list grouped by category, search, lat/lon entry, current
  coordinate + altitude readout, fly-to history (back button).
- **Lighting:** time-driven by design (DECIDED 2026-08-30: the sun is
  movable and astronomically correct; this is a product feature, not a
  debug tool, because different missions must each get their real
  lighting). Mode picker — `date/time` (UTC date-time picker, "now" button,
  a scrub slider spanning ±15 days for terminator sweeps, and named mission
  presets that are just pinned instants: "Apollo 11 landing" =
  1969-07-20 20:17:40 UTC, later missions as site packs arrive), and
  `manual` (azimuth/elevation sliders, debug only). The Apollo 11 mission
  instant must render byte-identical to today's fixed manifest sun — that
  equivalence is the regression anchor. Shadow toggle stays.
  Photographic-grade toggle once TerrainRealismPlan B2 lands.
- **Debug:** runtime versions of the capture diagnostics — tile-tint
  residency map, constant reflectance, normal maps off, plus wireframe if
  cheap. Note: these currently affect material/bake creation at tile build
  time; a runtime toggle must invalidate and rebuild resident tiles (the
  `activateDetailMode` teardown path already shows how). Diagnostics HUD
  grows: globe chunk count/level histogram, texture-tile residency, detail
  cache hit rate and bytes (`LMTerrainDetailStreaming`), per-frame
  generation timings.
- **Capture:** a "save screenshot + state JSON" button that records the full
  session state (coordinates, time, toggles) so any visual report is
  reproducible from the panel alone.

## 7. Workstream 5 — sun from date/time: couplings to respect

Making the sun movable touches assumptions that are currently implicit:

- **Radiance-conserving LOD (TerrainRealismPlan B1) must be
  sun-parameterized — DECIDED 2026-08-30.** The movable, ephemeris-correct
  sun is a product requirement (multiple missions, each with its real
  lighting), so B1 must NOT bake fixed-sun compensation into tile albedo.
  Bake sun-independent per-tile statistics of the added relief octaves
  (slope variance / directional distribution per band) and evaluate the
  shading-compensation ratio for the current sun direction at material
  realization time; alternatively key the bake cache by quantized sun
  direction (bound the cache growth). TerrainRealismPlan §4 B1 carries the
  same requirement — keep the two documents in agreement.
- **Reflectance relightability:** the WAC mosaic and near-field proxy are
  photometrically *normalized*, so relighting them is legitimate; but they
  contain no opposition-surge or phase-angle behavior. Acceptable for this
  product; note it in the doc so nobody chases "the full Moon looks flat" as
  a bug (it genuinely will, without a phase-function model — optional future
  work: Hapke/lunar-Lambert weighting in the material).
- **Mission shadows** (`missionShadowDistance` heuristics) were tuned for a
  low fixed sun; re-check at high sun angles (short shadows, cheaper) and
  near-terminator (long shadows, expensive — may need clamping by sun
  elevation).
- **The A/B capture matrix** must pin lighting mode = `mission` for all
  existing comparisons, so historical baselines stay valid.

## 8. Sequencing

1. ~~**W1 coordinates + ephemeris**~~ — **done**; see §0.
2. **W3 partial:** POI catalog + lat/lon entry + fly-to *within the current
   262 km patch* (immediately useful for debugging; no globe needed —
   clamp/deny targets outside patch coverage with a clear message).
3. **W4 panel debug section** (runtime tile-tint/constant-reflectance/
   normal-map toggles + richer HUD) — small, high leverage for all other
   terrain work.
4. **W5 sun modes** on the current patch (date/time via W1 table + manual
   debug mode; B1 lands sun-parameterized per §7 — the two must not be
   built against a fixed-sun assumption anywhere).
5. **W2 globe** (largest: offline pyramids first, then chunk renderer, then
   handoff gate).
6. **W3 full:** globe navigation + full POI flying.

## 9. Risks / open questions (flag to owner, don't decide silently)

- **Bundle size** for global pyramids (§4.1 budgets) — needs sign-off.
- **Curvature registration** between the planar 262 km patch and the globe
  (how much the far band already accounts for; measurable at the handoff).
- ~~Whether `date/time` lighting ships user-facing or stays a debug tool~~ —
  **resolved 2026-08-30: user-facing.** The owner wants multiple missions
  with astronomically correct sun; B1 sun-parameterization (§7) is
  therefore mandatory, and the fixed manifest sun becomes a derived value
  (the ephemeris evaluated at the Apollo 11 mission instant) kept as a
  pinned regression anchor.
- **Performance on device:** globe chunks + site clipmap + Vision Pro
  Release budget; the existing outstanding Release profiling task
  (TerrainRealismPlan §6) should happen before the globe adds load, to have
  a baseline.

## 10. Validation

- Unit: coordinate round-trips; ephemeris vs Meeus cross-check; the
  Apollo 11 mission-sun anchor test; POI coordinates spot-checked against
  Gazetteer entries in-test (bundled expected values).
- Visual: extend `Tools/CaptureLunarExplorerAB.sh` with globe presets
  (full disk, terminator at a POI, zoom ladder globe→surface at Apollo 11)
  and lighting-mode columns. Use the tile-tint + statistics protocol from
  `Docs/TerrainRealismPlan.md` §7 for every handoff/seam claim.
- The zoom ladder capture (globe → surface, ~8 stops) is the acceptance
  artifact for the whole plan: every frame seam-free, every gate crossing
  smooth, coordinates displayed matching the target POI.

## 11. Key files

| Area | Where |
|---|---|
| Explorer scene / session / SwiftUI panel | `LM/LunarExplorerScene.swift`, `LM/LunarExplorerSession.swift`, `LM/LunarExplorerView.swift` |
| Site terrain bands, materials, sun, diagnostics flags | `LM/LMTerrainWorld.swift` |
| Site frame alignment (anchor for W1 tests) | `LMTerrainFrameAlignment`, `LM/LMTerrainManifest.swift`, `LM/Terrain/TerrainManifest.json` |
| Progressive site clipmap (leave intact) | `LM/LMProgressiveTerrain.swift`, `LM/Apollo11TerrainResource.swift` |
| Offline generation (extend for pyramids/ephemeris) | `Tools/TerrainGenerator/`, new `Tools/Ephemeris/` |
| New globe system (create) | `LM/LunarGlobe/` (suggested) |
| POI catalog (create) | `LM/Terrain/MoonPOI.json` (suggested) |
| Capture harness | `Tools/CaptureLunarExplorerAB.sh` |
| Companion plan | `Docs/TerrainRealismPlan.md` (esp. §4 B1/B2 couplings) |
