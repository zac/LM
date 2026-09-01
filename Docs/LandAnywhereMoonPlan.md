# Land-anywhere Moon: global terrain, procedural amplification, neural texture

Self-contained work plan. It assumes no prior conversation context. Read
`Docs/LunarTerrainPipeline.md` (pipeline + fidelity contract) first;
`Docs/TerrainRealismPlan.md` and `Docs/MoonExplorerPlan.md` are the two
in-flight companion plans this one extends. This document **supersedes
MoonExplorerPlan Workstream W2 (globe)** — the globe is Stage 1 here, a
milestone of a larger architecture rather than a standalone feature.

**Vision:** fly anywhere on the Moon, zoom from a whole-disk globe down to
the surface, tilt into the craters, scrub the sun through real dates — and
land. Everywhere. Terrain is real where we have measurements, procedurally
amplified below the measured floor into plausible, deterministic,
contact-capable surface, with fine texture synthesized on device by compact
neural models instead of shipped.

**Feasibility, in one paragraph.** This is the existing Apollo 11 stack with
the anchor generalized and the amplification band widened. The current
pipeline amplifies a 2 m measured source to 0.125 m (16x) with deterministic,
Surveyor-constrained crater statistics anchored exactly at measured posts;
land-anywhere amplifies 59–237 m global sources to ~0.1 m (500–2000x) with
the same machinery. The Moon cooperates: below a few hundred metres
wavelength the surface is in cratering equilibrium — statistically
homogeneous, self-similar, governed by a measured size-frequency law — so
synthesis below the measured floor samples a distribution the real Moon
obeys. The three genuinely hard parts are §5 (mushy band), §4 stage 2
(re-anchoring), and honest handling of the widened fiction band (§2).

## 0. Status board (update when you land work)

| Piece | State | Notes |
|---|---|---|
| Coordinate authority (any lat/lon ↔ ME frame ↔ site ENU) | **Done** | `LM/MoonCoordinateConverter.swift`, tested. |
| Lunar ephemeris (sun/Earth for any instant, any site) | **Done** | `LM/LMLunarEphemeris.swift`, tested; mission sun corrected and tied to it. |
| Elevation-tracking sun exposure | **Done** | `LMTerrainWorld.missionSunIlluminance(elevationDegrees:grade:)`; mission render pixel-identical. |
| Photographic tone grade + earthshine | **Done** | Opt-in; calibrated grade pixel-identical. |
| Global mosaic fetch/parse proven | **Done** | Source-validating 16 ppd generator, pinned PNG + provenance sidecar, and manifest schema v4 landed. |
| Stage 1 globe | **In progress** | 16 ppd unlit WAC sphere, ME orientation, Explorer `globe` preset, and ephemeris terminator multiplier landed. 64 ppd, elevation normal, lat/lon navigation, and globe-to-site crossfade remain. |
| Stage 2 re-anchorable terrain | Not started | §4. The land-anywhere milestone. |
| Stage 3 mushy-band quality | Not started | §5. |
| Stage 4 site packs | Not started | §4. |
| Neural track N1 multi-site retrain | Not started | §6. Cheap; do early. |
| Neural track N2 teacher–student | Not started | §6. |
| Neural track N3 geology conditioning | Not started | §6. Lands with Stage 2. |

## 1. Non-negotiable contracts (inherited, with one evolution)

All contracts in `Docs/TerrainRealismPlan.md` §1 apply: measured terrain
authoritative, determinism (same coordinate + same generator version = same
result), runtime neural is appearance-only, offline source changes are
versioned and pinned, every source input pinned by product/byte-range/hash.

**One contract evolves and needs owner sign-off before Stage 2 ships:** the
bounded-residual rule. At Apollo 11 the procedural residual is capped at
0.24 m against a 2 m source. Against a 118 m source, honest sub-resolution
relief includes 50 m craters that are 10 m deep. The cap must scale with
source spacing (proposal: cap ≈ 0.12 × source spacing, matching the current
ratio), and the contract language changes from "bounded correction" to
"plausible synthesis anchored to truth." The invariants that survive
unchanged: exactly zero at every measured post, deterministic, versioned,
and contact = rendered. The UI should expose provenance (a "measured floor:
X m" diagnostic) so nobody mistakes synthesized terrain for surveyed truth.

## 2. What "plausible" means here (set expectations in code review, not after)

- Above the local measured floor (59–237 m globally; 2 m at Apollo 11):
  real, from pinned sources.
- Below it: statistically correct fiction — crater populations on the
  measured size-frequency law, deterministic per coordinate, permanent
  across sessions. A specific synthesized 40 m crater is not really there;
  its population statistics are.
- Landing physics runs on this synthesis (contact = rendered, as today).
  That is the point — but it means a crash into a synthesized crater is a
  crash into fiction. Fine for a simulator; say so in the product.

## 3. Data: sources, sizes, and the streaming model

Verified this session (2026-08-31):

- **PDS is reachable and the fetch machinery exists.** The terrain
  generator already fetches pinned byte-range slabs; the same discipline
  extends to global products.
- **WAC_GLOBAL_E000N0000_016P v1.3** (LROC WAC morphologic mosaic, global,
  equirectangular, 16 px/deg = 1.9 km/px, 5760×2880, PC_REAL 32-bit,
  attached PDS3 label, 23040-byte label record): 66,378,240 bytes, SHA-256
  `c75a49b48df0d1d8afad8f25e58332599e8383e4967424ffbb0ba38b0808b2b6`, at
  `https://pds.lroc.im-ldi.com/data/LRO-L-LROC-5-RDR-V1.0/LROLRC_2001/DATA/BDR/WAC_GLOBAL/`.
  The production converter accepts 16,313,894 finite [0, 1) reflectance
  samples, replaces 274,906 source no-data samples with the fixed display
  floor, and measures a valid-sample mean of 0.04633. A 64 ppd sibling
  (474 m/px) exists at ~1.06 GB.
- **The morphologic caveat:** WAC_GLOBAL is deliberately imaged at 53–70°
  incidence — **shading is baked in**. Lighting it with our movable sun
  double-shades. The photometrically normalized WAC_EMP 643 nm series (what
  the near field uses) has **no global product** — tiles only, several
  hundred MB to ~1 GB for global coverage.
  **Decision (recommended, owner may override):** ship morphologic for the
  globe now, rendered as an unlit/ambient *map* at globe scale — honest, and
  what map products do — behind a texture interface that can take an EMP
  mosaic later. Physically-lit terrain begins where the amplified terrain
  system takes over (Stage 2), which uses normalized reflectance as today.
- **Elevation:** SLDEM2015 512 ppd (59 m/post, ±60° lat, ~33 GB full) and
  128 ppd (237 m/post, global-ish, ~2.8 GB); LOLA LDEM fills the poles.
  Nobody bundles these whole: the offline generator produces tiled,
  content-hashed pyramids; the app bundles a coarse base and streams/caches
  finer tiles on demand, every tile pinned.
- **`moon.usdz` (repo root) — assessed, do not build on it.** 4096²
  equirectangular diffuse (~2.7 km/px, almost certainly the morphologic
  mosaic, unpinned) and a 4096² normal map that is **unusable** (elevation
  leaking into normal channels — green/yellow bias across the southern
  highlands — plus polar banding). Its one good idea is the architecture:
  textured sphere + texture swap by zoom, which Stage 1 adopts with pinned
  data and a generated normal map.
- **Fine texture is generated, not shipped.** A global NAC-like texture at
  2 m/px is ~10^13 pixels — terabytes; no codec ships it. See §6.
- Budget targets (verify, get sign-off before exceeding): ≤300 MB bundled
  base; streamed tiles cached with an LRU cap; everything hash-pinned.

## 4. The stages

### Stage 1 — Globe (fly everywhere, look)

Progress landed 2026-08-31: `GlobalLunarMosaicGenerator` validates the exact
source byte count, SHA-256, attached PDS label, projection, dimensions, sample
type, and longitude convention before producing the committed 5,760×2,880
sRGB texture and provenance JSON. Manifest schema 4 pins that output and its
source. `LMLunarGlobeResource` builds a tessellated sphere through the shared
ME coordinate authority, centers Apollo 11 without a guessed rotation, and
uses the baked-shading mosaic as unlit map color. The Explorer now has a
whole-Moon preset and an explicit first presentation gate. That gate is a
temporary discrete switch: it is not the Stage 1 handoff acceptance until the
measured globe-to-site crossfade is implemented and visually captured.

Simulator validation on the pinned 26.5 Vision Pro destination held the globe
stable beyond 90 seconds, confirmed the Apollo-centered near-side geography,
and inspected both poles plus the back-side texture wrap. That pass found and
fixed a duplicated-seam UV normalization error. At the temporary 350 km gate,
the globe and site widths now differ by 9 pixels in a 3,840-pixel capture, but
the site's planar projection remains visibly discontinuous; that measured
failure is the baseline the required crossfade must replace rather than hide.

The globe terminator is a separate black unlit shell whose opacity is
`1 - multiplier`, not a directional material light. At Apollo 11 touchdown it
changed 29.2% of the visible disk pixels (mean 11.9/255 and maximum 24/255
darkening among changed pixels); seven days later the ephemeris moved that
terminator off the same visible half and the capture there was pixel-identical
to the pre-terminator globe. This preserves the WAC product's baked relief
while making the session date legible at map scale.

A textured sphere with LOD texture swap — deliberately not a chunked
quad-sphere; at globe scale a sphere mesh + good textures is enough, and
Stage 2 owns close terrain.

1. Offline (extend `Tools/TerrainGenerator` or a sibling subcommand):
   convert WAC_GLOBAL 16 ppd (and 64 ppd for the zoom tier) to textures;
   generate a **normal map from LOLA/SLDEM elevation** (proper detrended
   gradient in the ME frame — this replaces the usdz's broken one); pin
   everything in the manifest (new `globe` section, schema bump).
2. Runtime (`LM/LunarGlobe/` suggested): sphere entity at ME orientation
   through `LMSelenographicCoordinateSystem`; radius 1,737,400 m scaled to
   the tabletop; unlit/ambient map material (§3 decision); texture tier by
   `metersAcross`. Explorer gains a `globe` preset above `orbit`;
   orbit/pan/zoom generalize to lat/lon navigation (see MoonExplorerPlan
   W3 for gestures/POI — that workstream lands naturally here).
3. Globe → site handoff v1: below a gate altitude over Apollo 11, crossfade
   to the existing patch (the `presentationBlend` pattern). Elsewhere, the
   globe is the floor until Stage 2.
4. Position the whole thing with the coordinate authority; light *the sky*
   (terminator on the globe from the ephemeris subsolar point) even while
   the surface texture stays a map — a subtle day/night darkening multiplier
   is honest and looks right, full double-shading is not.

### Stage 2 — Re-anchorable terrain (the land-anywhere milestone)

Generalize the site stack from "Apollo 11, planar ENU, 2 m NAC" to "any
anchor, floating tangent frame, whatever sources cover it."

1. **Floating anchor:** a local ENU tangent frame under the vehicle/focus,
   re-anchored when the focus drifts beyond ~25–50 km (planar validity), via
   `LMSelenographicLocalFrame`. Re-anchoring is a coordinate translation of
   resident tiles, not a visual event; design it seam-free like every LOD
   gate and validate with the capture protocol.
2. **Source resolver:** given an anchor, assemble the band stack from
   available pinned sources — streamed SLDEM/LOLA tiles for geometry, WAC
   (normalized where available) for reflectance, NAC site packs where they
   exist (Stage 4). The manifest becomes a catalog of sources + coverage
   rather than one site's fixed bands.
3. **Widen the amplification ladder:** today's progressive levels run
   0.5 m/0.125 m below a 2 m source. Extend upward (e.g. 128/32/8/2 m
   levels — the planner's `Level` list already sketches this) so each level
   adds its octave of crater statistics below the local measured floor,
   anchored at that source's posts, residual cap scaled per §1. The
   geology model needs its crater diameter range extended to match
   (currently 0.22–1.2 m geometry + 2–8 m catalog).
4. **Contact everywhere:** `LMTerrainLandingSurface` builds from the same
   resolver, so descent works at any anchor. The AGC/LR side already treats
   altitude spherically (see project memory).
5. Reuse, don't rebuild: planner, morph collars, residency nesting,
   per-tile bake, detail cache, capture diagnostics all generalize. The
   work is plumbing anchors and sources through them, not new rendering.

### Stage 3 — Mushy-band quality (see §5)

### Stage 4 — Site packs

The offline generator, given any lat/lon with LROC NAC DTM/ortho coverage
(dozens of published sites: all Apollos, Surveyors, science targets),
produces a pinned enhancement pack = today's Apollo 11 near field at another
site. Favorite destinations graduate from plausible to measured. The Stage 2
source resolver makes this a data drop, not a code change. (SfS refinement —
TerrainRealismPlan Workstream C — slots in here for sites without published
DTMs, same offline provenance rules.)

## 5. The mushy band (the real R&D risk)

Features 1–4x the local post spacing are half-resolved in the source: a
300 m crater in 118 m data is present but melted. Below the posts we invent
cleanly; well above them the data is sharp; in between, everything looks
like wax unless sharpened. This is the Apollo 11 "curvy crater" problem at
global scale, and it sits in exactly the size band a pilot looks at on
final approach.

Attack in order:
1. **Detection-conditioned sharpening** — TerrainRealismPlan Workstream A's
   detector generalized: detect craters in WAC imagery (100 m/px resolves
   craters ≥ ~300 m), catalog them (offline, versioned, pinned — but now as
   a *generated tile product* per region, not one hand-reviewed file), and
   let the geology model deepen/sharpen the measured bump parametrically.
   Learn from A's QA findings: cap-truncation and template size bias were
   real problems; fix the detector's size-frequency calibration before
   scaling it up.
2. **Statistical rim sharpening** — where no detection fires, condition on
   the measured surface itself (curvature maxima → rim enhancement within
   the residual budget). Cheaper, riskier visually; A/B it.
3. **Offline neural DTM super-resolution** (MADNet-style, imagery-
   conditioned) as a versioned source product — never runtime. Needs the
   same provenance sign-off as SfS.

Acceptance for any of these: the zoom ladder (§8) shows no melted band, and
measured posts remain exact.

## 6. Neural track (texture is generated, not shipped)

Current state, verified: `LM/LunarTerrainSR.mlpackage` — 89K params, 204 KB,
4x single-channel SR (128²→512²), residual-over-bilinear, +2.09 dB over
bilinear on held-out NAC, single-site (Apollo 11) training, ~ms-scale
per-tile inference (latency test in `LMTerrainDetailStreamingTests`).
Trainer: `Tools/NeuralTerrain/` (corpus rules, geographic split, export
gates, `accepted-metrics.json`). Runtime seam: `LMCoreMLTerrainDetailGenerator`
+ `LMTerrainDetailStreaming` — appearance-only, exact procedural fallback,
model version in the cache key. **Keep all of that; it is the hard part and
it is done.**

- **N1 — Multi-site retrain (do early, independent of everything):** train
  the *current* architecture on NAC DTM/ortho pairs from many sites (mare,
  highlands, ejecta). Pin the corpus (product IDs + hashes) in
  `accepted-metrics.json` like terrain sources. Kills single-site
  brittleness for a day's work.
- **N2 — Teacher–student generative upgrade:** large adversarial/diffusion
  teacher offline, distilled to a compact student (1–5 M params, 2–10 MB,
  ANE-friendly). The current L1/gradient loss is right for 4x fidelity and
  wrong for hallucination ratios — it will produce mush; the perceptual/
  adversarial loss is what makes invented texture crisp. Keep the export
  gates: held-out metrics must beat the shipped model or export refuses.
- **N3 — Geology-conditioned generation (lands with Stage 2):** change the
  input contract from "low-res albedo" to "coarse WAC patch + the tile's
  own baked relief/normals + crater mask from `LMLunarGeologyModel` + a
  coordinate-hash noise seed." The model paints bright rims and ejecta on
  the craters the geometry actually has — that coupling is what makes
  synthesized texture read as terrain, and the hash seed keeps it
  deterministic (same coordinate, same texture, forever).
- **N4 — Biome conditioning:** mare/highland/maturity channels derived from
  WAC products; probably extra input channels, not a new model.
- **Hard line:** no runtime neural geometry. Elevation SR is §5.3, offline,
  versioned, opt-in provenance.
- Sizing sanity: texture gap to bridge is ~100 m → 2 m-class appearance;
  geometry relief and procedural microtexture carry structure below ~2 m
  already. Tiles arrive at a few per second; a 5 M-param student has two
  orders of magnitude of latency headroom.
- Boring sidebar that still matters: for data we *do* ship, modern codecs
  (ASTC/JPEG-XL) are 10–20x with zero ML risk. Neural is for what we don't
  ship.

## 7. Sequencing

1. **Stage 1 globe** + **N1 retrain** (independent, parallel-friendly).
2. **Stage 2 re-anchorable terrain** — the milestone. Gate: residual-cap
   contract sign-off (§1) first. Fold in MoonExplorerPlan W3 (POI/fly-to)
   and W4 (debug panel) as its UX face.
3. **Stage 3 mushy band** + **N2/N3** (they meet: N3's crater mask comes
   from the same catalogs Stage 3 builds).
4. **Stage 4 site packs**, then TerrainRealismPlan B1 radiance-conserving
   LOD re-validated at global scale.

Standing prerequisite from the other plans, still outstanding: **Vision Pro
Release profiling** — do it before Stage 2 adds load, so regressions are
attributable.

## 8. Validation

- The capture protocol from `Docs/TerrainRealismPlan.md` §7 (tile-tint
  segmentation, per-region statistics, narrow-band edge steps; measure,
  don't eyeball — visual impressions were overturned repeatedly).
- **The acceptance artifact for the whole plan is a zoom ladder**: globe →
  surface at (a) Apollo 11, (b) an arbitrary mare point, (c) an arbitrary
  highland point, ~8 stops each, every frame seam-free, no melted band, sun
  correct for the scrubbed date. Automate it in
  `Tools/CaptureLunarExplorerAB.sh`.
- Determinism: same anchor + same versions → byte-identical tiles (extend
  existing tests). Measured posts exact at every source (existing invariant,
  now per-source).
- A landing at an arbitrary anchor completes with contact = rendered
  (generalize `TerrainRelativeLandingTests`).
- Neural: export gates in the trainer; runtime A/B RMSE vs procedural per
  preset; model version in every cache key (test exists).

## 9. Key files

| Area | Where |
|---|---|
| Coordinate authority / ephemeris | `LM/MoonCoordinateConverter.swift`, `LM/LMLunarEphemeris.swift` |
| Site terrain stack to generalize | `LM/LMProgressiveTerrain.swift`, `LM/Apollo11TerrainResource.swift`, `LM/LMTerrainWorld.swift`, `LM/LMTerrainLandingSurface.swift` |
| Appearance bake + streaming + neural seam | `LM/LMTerrainDetailTexture.swift`, `LM/LMTerrainDetailStreaming.swift`, `LM/LMCoreMLTerrainDetailGenerator.swift` |
| Neural trainer + corpus rules | `Tools/NeuralTerrain/` |
| Offline generation + manifest (extend for globe/pyramids/resolver) | `Tools/TerrainGenerator/`, `LM/Terrain/TerrainManifest.json`, `LM/LMTerrainManifest.swift` |
| Crater catalog (template for detection products) | `LM/LMLunarCraterCatalog.swift`, `Tools/TerrainGenerator/detect_craters.py` |
| Explorer UX | `LM/LunarExplorerScene.swift`, `LM/LunarExplorerSession.swift`, `LM/LunarExplorerView.swift` |
| New globe system (create) | `LM/LunarGlobe/` (suggested) |
| Companion plans | `Docs/TerrainRealismPlan.md`, `Docs/MoonExplorerPlan.md`, `Docs/LunarTerrainPipeline.md` |
