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
| Stage 1 globe | **Done in Simulator** | Complete offline 16/64 ppd WAC globe, ME orientation, Explorer `globe` preset, ephemeris terminator, pinned LOLA-derived ME normal field, radiance-matched globe-to-site handoff, and the final globe-to-surface ladder are green. Continuous hand-gesture comfort remains owner hardware validation on physical Vision Pro; it is not an implementation blocker for Stage 2. |
| Stage 2 re-anchorable terrain | **In progress** | §4. Release baseline, source catalog, floating Explorer anchor, and the first streamed elevation consumer are implemented. Global source resolution/amplification, rendered contact, and Explorer navigation are implemented with visual and mission-integration gates open; see `Stage2GlobalTerrainValidation.md`. The owner approved the source-scaled residual contract and up to 32 MiB for the offline elevation base on 2026-09-04. |
| Stage 3 mushy-band quality | Not started | §5. |
| Stage 4 site packs | Not started | §4. |
| Neural track N1 multi-site retrain | Not started | §6. Cheap; do early. |
| Neural track N2 teacher–student | Not started | §6. |
| Neural track N3 geology conditioning | Not started | §6. Lands with Stage 2. |

The Explorer navigation/presentation follow-up is recorded in
`MoonExplorerExperience.md`: a bounded mixed-space globe, explicit immersive
terrain entry, native place browser, sunlight controls and saved views. It
shares this terrain pipeline and retains all capture and provenance contracts.

The texture/import follow-up is recorded in
`MoonExplorerTextureAndPublication.md`. Source pixel dimensions are not GPU
residency dimensions: the current Simulator imports the 23,040 × 11,520
64 ppd raster as a 5,760 × 2,880 texture. A 15.38 MiB prepared color companion
matches the fixed globe/handoff images and awaits a separate 16 MiB owner
budget approval; the original source remains unchanged. Terrain ownership
preparation moves ahead of atomic publication, with frame-budget and physical
Vision Pro gates still open.

The September 6 startup and repeated-navigation profiling follow-up is in
`MoonExplorerPerformance.md`. It attributes the approximately 1.6 GiB startup
peak to the 64 ppd texture load and records the bounded navigation soak,
capture-stage acknowledgement protocol and remaining performance gates.
The worker preparation follow-up removes approximately 65 ms of synchronous
base-grid work per surface entry from the main actor. Its 86 focused tests and
all eleven byte-identical Apollo captures pass. Repeat-cycle hitch maxima fall
but hitch counts and retained footprint increase; overall performance acceptance
remains open rather than being inferred from the scheduling change.

## 1. Non-negotiable contracts (inherited, with one evolution)

All contracts in `Docs/TerrainRealismPlan.md` §1 apply: measured terrain
authoritative, determinism (same coordinate + same generator version = same
result), runtime neural is appearance-only, offline source changes are
versioned and pinned, every source input pinned by product/byte-range/hash.

**Owner-approved 2026-09-04:** the bounded-residual rule scales with the
authoritative elevation source. At Apollo 11 the procedural residual is capped at
0.24 m against a 2 m source. Against a 118 m source, honest sub-resolution
relief includes 50 m craters that are 10 m deep. The cap is
`0.12 × source post spacing`, stored per elevation source in the manifest, and
the contract language changes from "bounded correction" to
"plausible synthesis anchored to truth." The invariants that survive
unchanged: exactly zero at every measured post, deterministic, versioned,
and contact = rendered. Apollo 11 therefore remains at 0.24 m and its terrain
assets must stay byte-identical. The UI must expose provenance (a "measured
floor: X m" diagnostic) so nobody mistakes synthesized terrain for surveyed
truth.

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
  These are source-family capabilities, not current pinned runtime coverage.
  The catalog currently pins two Apollo-latitude SLDEM strips and the complete
  16 ppd LOLA base. Outside a supported fine strip, the offline measured floor
  is about 1,895 m. Item 4 must derive and pin bounded finer chunks before
  claiming 59–237 m coverage elsewhere. The existing 205,148,160-byte 128 ppd
  strip exceeds the new 128 MiB cache; it needs smaller pinned slabs for runtime
  use rather than an implicit cache-budget increase.
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
- **Measured globe-tier budget decision (2026-08-31, resolved 2026-09-01).**
  The current Release Simulator app is 334.9 MiB and is the owner-accepted
  baseline; the checked-in terrain plus RealityKit source assets are 235.1
  MiB. Scaling the committed 16 ppd PNG by pixel count estimated a full 64 ppd
  lossless PNG at 264.1 MiB, which would put the Release app near 599 MiB. The
  actual generated RGBA PNG is 223.8 MiB; its byte-identical one-channel
  grayscale representation is 122.5 MiB. JPEG XL quality 95, encoded by
  `cjxl 0.12.0` at effort 7, is 72.6 MiB and therefore clears the owner's
  approximately 80 MiB exception gate. It is pinned as the bundled offline
  64 ppd tier; the 16 ppd PNG remains the deterministic capture and fallback
  base. Against the lossless 64 ppd PNG, fixed Simulator captures measure
  64.75 dB PSNR / 0.0085% mean absolute error at whole-globe scale and 64.39
  dB / 0.0090% in the 320 km globe-to-orbit overlap, with no visible codec or
  tile seam. This explicitly flips the earlier stream-only decision while
  retaining its budget boundary: any further bundled addition requires owner
  sign-off. The Stage 1 close-out generic visionOS arm64 Release app is 406.5
  MiB allocated (416,272 KiB; 405.9 MiB summed file payload), including the
  byte-identical 76,112,646-byte JXL. A settled
  visionOS 26.5 Simulator launch decoded and displayed the explicit 64 ppd
  tier at `/private/tmp/LandAnywhere-JXL-64ppd-runtime-verified.png`; the same
  asset and digest passed a generic visionOS arm64 Release build. Production
  load attempts 64 ppd first, logs any decode failure, and falls back to the
  pinned 16 ppd texture instead of failing the globe.
- **Streaming is deferred to Stage 2.** The complete 64 ppd appearance map is
  bundled, so Stage 1 has no remote tile consumer. Do not keep a speculative
  loader or cache alive in the app. Build the PDS HTTP byte-range loader,
  per-tile digest verification, persistent bounded LRU, and offline prefetch
  with Stage 2's first streamed elevation slab. That implementation must use
  the real source resolver and decoded elevation product in its tests rather
  than an otherwise unused generic path.
- **Owner-approved Stage 2 elevation budget, 2026-09-04:** up to 32 MiB of
  additional bundled data for the global offline elevation base. The prepared
  candidate is the already pinned LOLA `LDEM_16` V3.1 raw image, 33,177,600
  bytes or 31.640625 MiB. Its source and label digests were verified against
  the catalog. Lossless zlib measured 28.621368 MiB and round-tripped exactly;
  the raw form avoids adding a codec for a 3.019257 MiB saving. This approval
  covers the elevation base and provenance, not further texture tiers.

## 4. The stages

### Stage 1 — Globe (fly everywhere, look)

Progress landed 2026-08-31: `GlobalLunarMosaicGenerator` validates the exact
source byte count, SHA-256, attached PDS label, projection, dimensions, sample
type, and longitude convention before producing the committed 5,760×2,880
sRGB texture and provenance JSON. Manifest schema 6 pins that output and its
source. `LMLunarGlobeResource` builds a tessellated sphere through the shared
ME coordinate authority, centers Apollo 11 without a guessed rotation, and
uses the baked-shading mosaic as unlit map color. The Explorer now has a
whole-Moon preset and an explicit first presentation gate.

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

The generator now also pins the 33,177,600-byte LOLA `LDEM_16` V3.1 image and
5,121-byte label, rotates its 0...360° east cylindrical grid into the shared
-180...+180° ME convention, differentiates only height above the 1,737,400 m
reference sphere, and emits a 5,760×2,880 signed ME-vector normal PNG. A
five-degree polar reliability taper removes the cylindrical coordinate
singularity without altering any measured site geometry. At 1/16-resolution
measurement, radial-normal dot product was 0.9980 median (0.9262 p01); the
first/last longitude columns averaged 0.9830 dot, within ordinary adjacent
terrain variation, and both sampled cap rows stayed within 0.001 of their
expected polar z direction. Runtime downsamples that field once and uses it
only inside the existing unlit terminator multiplier. The final settled
Simulator frame is
`/tmp/LandAnywhere-Stage1-lola-normal-terminator-final.png`. Against the
analytic-normal touchdown capture, LOLA relief changed 82,470 of 8,294,400
pixels (0.994285%); changed channels moved 3.8816/255 on average with a
22/255 maximum. The rendered near-side geography remains registered and no
normal-induced wrap or polar band is visible.

The discrete 350 km presentation switch is now a measured 330–120 km
handoff. From 330–240 km the globe smoothly ramps to 1.4× presentation scale
before the site appears. From 240–120 km the globe and regional layer share
that exact screen scale while the globe opacity dissolves during the first
half and the regional camera eases into the existing Orbit presentation
during the second. The regional layer is projected onto the exact eye ray
through the coordinate authority's Apollo 11 globe point. Waiting to reveal
it until its finite 262 km square covers the view prevents a card edge;
matching scale prevents the earlier translucent double image.

Registration is explicit rather than hidden: the normalized center-ray
residual is below `1e-6` in the runtime test (zero before floating-point
rounding, therefore zero pixels before rasterization). Scale is intentionally
not physical during the dissolve: both layers use 1.4× overscan because a
physically scaled 262 km patch is only about 7.5% of the Moon's diameter and
produced a black coverage gap. It is a presentation bridge, not a claim that
the global and regional products have feature-by-feature scale parity. The
overscan eases back to 1× between Orbit and Regional, after the ordinary
finite site extent is safely outside the view. Settled 64 ppd Simulator
captures for the final measured implementation are:

- `/private/tmp/LandAnywhere-Stage1-crossfade-240km-64ppd-validated.png` —
  globe-side endpoint;
- `/private/tmp/LandAnywhere-Stage1-crossfade-210km-64ppd-validated.png` —
  registered overlap; and
- `/private/tmp/LandAnywhere-Stage1-crossfade-120km-64ppd-validated.png` —
  site-side Orbit endpoint.

Every listed capture settled for at least 90 seconds. No sampled frame shows
a coverage gap, sphere/plane intersection, overlap card edge, roll, or
double-render artifact. The exact coordinate-authority center ray remains
below `1e-6` normalized residual. Continuous hand-gesture comfort still needs
physical Vision Pro validation.

The initial overlap still contained a tonal defect. Capture-only layer
isolation at identical 210 km framing with the bundled 64 ppd JXL measured
central mean linear luminance of 0.02351 for the baked WAC globe and 0.13449
for the live site: the globe was 82.52% darker, an empirical 5.72x ratio. An
extended-linear unlit tint now ramps from 1x to 5.70x over the existing
330–240 km pre-handoff, before the site is visible. The corrected isolated
globe measured 0.13398, -0.376% from the site.

RealityKit's subtree-opacity path exposed a separate compositing loss:
complementary globe/site opacity produced a 22% mid-fade dip in linear
luminance. The site now dissolves over an opaque globe backplate; the globe
is removed only after the site is fully opaque. A bounded 10% sinusoidal
globe compensation, zero at both endpoints, cancels the remaining transparent
path loss. The final automatic 210 km overlap measures 0.13395, just -0.403%
from the site endpoint. Site materials, terrain lighting, contact, and both
presentation grades remain unchanged. Measurement captures:

- `/private/tmp/LandAnywhere-handoff-210km-64ppd-globe-unmatched.png` — unmatched 64 ppd JXL globe;
- `/private/tmp/LandAnywhere-handoff-210km-site-only.png` — matched-scale site;
- `/private/tmp/LandAnywhere-handoff-210km-64ppd-globe-matched.png` — corrected 64 ppd JXL globe;
- `/private/tmp/LandAnywhere-handoff-210km-64ppd-radiance-final.png` — final automatic overlap.

The same pass fixed a distinct near-surface ownership defect. Progressive
children used to remove parent triangles while still transparent or before
their asynchronous bake completed, revealing the black immersive background.
The scene now separates residency from geometric ownership and publishes a
complete requested generation atomically; the measured NAC base is masked
only after all replacement tiles are ready. Explorer also stopped inventing a
six-second camera velocity, reducing the 24.5 m Debug Simulator request from
31 fine plus eight parent tiles (about 48.6 seconds cold) to nine fine plus one
parent tile (about 19.1 seconds cold), a 60.8% reduction and a 20 MiB detail
working set rather than 78 MiB. Captures
`/private/tmp/LandAnywhere-probe-24m-atomic-focused.png` and
`/private/tmp/LandAnywhere-probe-39m-atomic-settled.png` confirm the black
holes are gone at both fine-detail opacity gates.

The apparent near-surface radiance blocker was also remeasured after the
hierarchy and ownership corrections. The earlier 5–6% figure compared broad,
geologically different footprints. Adjacent 8–30 px bands at the actual
terminal/landing edge measure -0.155% calibrated, -0.120% photographic, and
+0.794% with constant reflectance and normal maps disabled. Full-resolution
touchdown normal distributions independently predict a 0.03% response change.
Applying the proposed material gain would therefore manufacture a seam; no
site material or cache key changed. The repeatable protocol and captures are
recorded in `Docs/TerrainRealismPlan.md` Workstream B1.

The final Surface ladder exposed one more, independent rectangular-tile
defect. CPU bakes were byte-identical on shared edges and adjacent measured
8-texel bands differed by only 0.17% east/west and 0.66% north/south, but the
rendered tiles still looked like cards with tangent-space normals,
microtexture modulation, mipmaps, and appearance collars independently
disabled. A constant-reflectance control was clean. The root cause was
coordinate convention: baked `CGImage` rows run north-to-south while
RealityKit texture V runs bottom-to-top, so each tile displayed its measured
reflectance vertically mirrored. The progressive mesh now maps its north row
to V=1. The production material capture
`/private/tmp/LandAnywhere-surface-v-flipped-production.png` is continuous,
and tests pin both north/south edge bytes and the north-at-texture-top UV
contract.

Stage 1's committed-build acceptance artifact is
`/private/tmp/LandAnywhere-Stage1-64ppd-accepted-2026-09-01/`. Its
`ladder.tsv` pins all eleven captures from the 64 ppd globe through 2 m,
0.5 m, 0.125 m, both close relief-blend boundaries, and the 2 m-above-ground
Surface view. Every accepted frame settled for at least 90 seconds and passed
the harness's live-process and monochrome-scene checks. The contact sheet and
full-resolution frames show no texture-wrap seam, coverage gap, globe/site
double render, tile card, or LOD handoff seam. Physical Vision Pro comfort is
explicit owner hardware testing and remains the only Stage 1 follow-up.

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

0. **Release performance baseline — done in Simulator 2026-09-04:** the
   existing eleven-stop Apollo 11 ladder is recorded before Stage 2 adds
   source resolution, transport, or wider amplification work. Measurements
   and caveats are in §7. Physical Vision Pro profiling remains separate.
1. **Source catalog — done 2026-09-04:** evolve the manifest from one site's
   fixed bands into a catalog of pinned sources with coverage extents, roles,
   post spacing, and the per-source residual cap approved under §1. Apollo 11
   is the first catalog entry; exact Stage 1 asset hashes guard its unchanged loaded bytes,
   and Explorer reports its 2 m measured floor.
2. **Floating anchor, implemented and measured in Simulator 2026-09-04:**
   `LMLunarFloatingOrigin` uses a 4,096 m three-dimensional
   focus-to-anchor distance, including vertical travel. The earlier 25–50 km
   proposal confused coordinate precision with planar validity. A 25 km arc
   already departs from its tangent plane by 179.86 m; moving an origin cannot
   correct that shape. Global source geometry must retain spherical positions
   when the resolver lands. Apollo 11 retains its existing planar geometry.
   Float32 steps are 0.48828125 mm at 4,096 m, 1.953125 mm at 25 km, and
   3.90625 mm at 50 km. The smaller trigger bounds focus-coordinate precision;
   distant fine meshes still need their own source-local origins.

   A change of spherical ENU includes rotation and translation. The Explorer
   moves the immutable source subtree into the active ENU and compensates the
   presentation frame in the same main-actor update. It recomputes transforms
   from canonical Double coordinates rather than accumulating Float deltas.
   Terrain heights, normals, UVs, tile IDs, cache keys, contact samples, and
   pending bake tasks do not depend on the floating origin. The initial
   consumer retained the 900 m navigation limit. The production global UX now
   permits a 20 km local window inside its immutable prefetched region, as
   described in item 6; the capture probe exercises the actual re-anchor
   trigger independently of that navigation limit.
3. **Streaming transport and cache, implemented in Simulator 2026-09-04:**
   `LMLunarElevationStore` fetches fixed-record PDS byte ranges, validates
   status/range/size before bounded body consumption, verifies SHA-256 before
   atomic publication, and retries transient failures at most three times.
   Its persistent 128 MiB content-addressed LRU supports offline reads and
   region prefetch that resumes at verified slabs. Format conversion belongs
   to `LMLunarElevationGrid`, independent of transport.

   The first real consumer is a capture-only curved elevation patch, using
   the pinned 59.2 m SLDEM strip or the bundled LOLA global base. It displays
   constant reflectance with no residual or contact claim. The raw base plus
   provenance label is 31.645509 MiB, within the approved 32 MiB. Production
   band selection, morphing, and contact are described in items 4 and 5.
4. **Source resolver and amplification, implemented with visual gates open:** given an anchor, assemble the band
   stack from available pinned sources: streamed SLDEM/LOLA for geometry,
   normalized WAC where available for reflectance, and NAC site packs where
   present. Extend today's 0.5 m/0.125 m progressive levels upward, such as
   128/32/8/2 m, so each adds its octave below the local measured floor and
   stays anchored at that source's posts under the §1 cap. Extend the geology
   model's crater diameter range to match. Implementation and numerical evidence
   are in `Stage2GlobalTerrainValidation.md`. The transition follow-up fixes
   stepped-footprint collar discontinuities at oblique headings. Nominal rays
   attribute one suspected foreground intrusion to terrain about 7 km away;
   that diagnosis does not close visual acceptance. The arrival follow-up now
   interpolates geometry and uploaded appearance on a common-refinement surface,
   with GPU-tested contact agreement. The full highland motion replay removes
   the recorded abrupt fine-detail arrival and transient publication flash,
   and restores byte-identical settled pixels. The final matched highland
   replay samples 713.8 MiB versus 256.8 MiB for the atomic control, so arrival memory
   and hitch costs remain open performance gates. Distant footprint joins and
   arbitrary-site handoff radiance also remain open; see the detailed evidence
   and physical-device limitations in `Stage2GlobalTerrainValidation.md`.

   A second-region mare control exposed a one-frame mesh-publication gap. The
   final path retains the identical opaque starting surface during a 100 ms
   registration interval, with cancellation and re-anchor coverage, before
   interpolation begins. The full mare repeat removes that gap and restores
   byte-identical settled pixels. This extends visual coverage without closing
   the performance gates above.

   The allocation follow-up replaces duplicate full CPU endpoint meshes with
   shared compact height/normal arrays and packs transient GPU attributes while
   retaining Float32 precision. Copied source textures retain only the level
   sampled by the blend; rendered output mip chains remain complete. Fresh
   instrumented controls show that five-second samples can miss arrival peaks
   above 1 GiB, so both phase samples and the original frame-window measurements
   must accompany comparisons. Detailed runs and remaining performance gates
   are recorded in `Stage2GlobalTerrainValidation.md`.
5. **Contact everywhere, implementation validated; mission integration open:**
   `LMTerrainLandingSurface` retains the exact rendered resolver triangles.
   Global gear drops pass at mare and highland anchors. Inspection showed
   spherical altitude was insufficient: AGC initialization, plant and LR basis
   also needed an explicit site context, now implemented on the authorized
   `terrain-anchor-guidance` AGC branch. Arbitrary-site cockpit wiring and
   atomic publication now have two complete Release mission captures: the
   mare settles intact with a hard-landing classification; the highland
   crashes at 16.14° vehicle tilt relative to the contact normal below the
   guidance datum. That recording did not separately retain terrain slope. Neither result
   is relabelled as a soft landing. All 116,500 audited footpad samples match
   the published mesh, and both recordings pass decoding and replay checks.
   The streaming follow-up removes near-ground readiness waits on both checked
   routes: the fresh Mare control paused for 422.187 seconds; final flights
   have zero coverage pauses and no missing/mismatched audited contact. An
   80-tile predictive budget, stable residency and ownership-only remasking
   reduce repeated work. Terrain publication is held at contact while the
   landing dynamics continue. All 22 Release tests pass; both final mission
   recordings pass replay checks, and the eleven-stop Apollo images remain
   byte-identical to item 0. Short publication hitches and allocation variation
   remain, along with distant coverage/faceting and an intact highland landing.
   See `Stage2CockpitStreaming.md` for measured controls, the rejected larger
   prefetch budget, capture bookkeeping correction, and physical-device gates.

   The September 5 diagnostic follow-up separates first-contact terrain
   normal/slope from vehicle tilt, moves capture export off the main actor and
   bounds JSON export memory. Final Mare remains intact with 51,996 exact
   audited samples and zero coverage pauses. Its worst frame falls from
   750.86 to 175.23 ms, while maximum publication wait and lifetime footprint
   rise to 105.418 ms and 777.160 MiB; those gates remain open. Transient
   transitions reach 113 tiles/99 dynamic meshes despite the 80-tile prediction
   cap, so the next allocation budget must include the morph union and texture
   payload. Highland diagnostic rays find a 512 m grid at 23.9 km; test denser
   distant interpolation only against that expanded budget. Do not label the
   historical 15.84-degree contact tilt as terrain slope. See
   `Stage2TerrainDiagnostics.md` for evidence and `ArtemisFlybyRealism.md`
   for the photographic reference controls.

   The low-Sun banding follow-up fixes a source-ownership defect: a clamped
   peer-strip halo could overwrite native coverage, moving measured posts and
   extruding a boundary row into stripes. Resolver v2 restricts halo blending
   to strictly finer sources above the native owner. Its combined-strip test
   is exact at posts and fractional coordinates in both strip orders. A
   separate shading correction blends collar slopes once, and consistent
   neutral-normal encoding removes the fine/coarse brightness step. See
   `Stage2TerrainBanding.md` for the failing controls, regression measurements,
   final captures and remaining visual/device limits. The source-data,
   procedural cap, rendered-contact and Apollo contracts remain unchanged.

   The lifecycle follow-up passes 15 Release Simulator tests, including exact
   P63 restart state, cancelled loads, and GPU/contact publication. The final
   eleven-stop Apollo capture is byte-identical to item 0. Settled pacing is
   unchanged, while cold-frame/memory improvements coexist with slower fine
   generation ranges; the detailed report retains those regressions.
   See `Stage2GlobalTerrainValidation.md`; local drops and retargeted sphere
   descents do not substitute for that acceptance.

   Cockpit integration prerequisite, 2026-09-05: the session stages contact
   synchronously and serializes full physics steps with global mesh/contact
   publication through `LMTerrainSimulationGate`. GPU morph completion is
   included in the cockpit publication boundary. The Explorer retains its
   existing publication path. `/tmp/LM-Cockpit-Publication-Tests.xcresult`
   passes the two ordering/cancellation tests and eight existing arrival tests
   on visionOS Simulator. The test runner omitted its requested Release flag,
   so this is Debug evidence; Release capture validation remains required.
   AGC's existing gear integration is recorded separately as `4a1aeb4` after
   14 isolated gear tests passed. The mission evidence above extends this
   prerequisite without closing the remaining visual and performance gates.
6. **Explorer UX, implemented with acceptance gaps:** coordinate entry/copy,
   eased great-circle fly-to, an 18-entry sourced POI catalog, measured-floor
   disclosure, history, cached-only reload and region download/pause controls.
   Global local pan remains bounded to the prefetched 20 km window. The product
   browser now supports continuous globe dragging, explicit immersive entry,
   saved views, and sunlight controls; see `MoonExplorerExperience.md`. Product
   navigation uses fades instead of automatic camera travel, while inspection
   launches retain the great-circle path. `MoonExplorerHIGReview.md` records
   adjustable initial-viewer placement, larger controls/text, and the flag
   quality pass. `MoonExplorerOverhaul.md` records native tabs/search, a
   Globe/Surface ornament, mission sheets, all-site markers and a measured
   attachment-alignment correction; the Apollo flag drawing is retained.
   `MoonExplorerVisualPolish.md` supersedes that browser layout with full-width
   search, grouped place cards, stronger contrast and a compact destination
   action after the owner rejected the default controls' visual result.
   Full panel interaction coverage and physical gesture comfort
   remain open. See `Stage2GlobalTerrainValidation.md` for terrain failures.
7. Reuse the planner, morph collars, residency nesting, per-tile bake,
   detail cache and static materials. The recorded atomic generation swap
   exposed an additional rendering requirement: continuous arrival needs one
   transient common-refinement surface whose GPU vertices and CPU contact share
   the displayed weight. The arrival follow-up therefore adds a bounded GPU
   interpolation path for geometry and uploaded appearance; it restores the
   existing static resources at completion. This revises the original assumption
   that anchor/source plumbing alone was sufficient. Source generation, measured
   posts, residual limits, contact agreement and Apollo 11 invariance remain
   controlling contracts. See `Stage2GlobalTerrainValidation.md` for rejected
   prototypes, tests and capture evidence.

### Stage 3 — Mushy-band quality (see §5)

**Future calibrated color layer.** High-resolution morphology stays a single
reflectance channel. Add color later as a separate, lower-resolution
multispectral layer that can show broad basalt composition and optical
maturity without changing relief detail. Candidate source families are LROC
WAC multispectral color, Kaguya Multiband Imager, and Clementine UVVIS. Pin
the selected products, calibration, registration, and derived texture just
like geometry sources. Never fuse lossy chroma into high-resolution
morphology, elevation, or normal maps, and never let it affect contact.

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

**Stage 2 item 0 Release baseline, 2026-09-04.** This closes the Simulator
attribution prerequisite before Stage 2 adds load. It does not close the
physical Vision Pro performance, thermal, or comfort gate retained by the
companion plans.

The run used Xcode 26.6 (17F113), macOS 26.5.1, the xrOS 26.5 Apple Vision Pro
Simulator `8F38C0E7-6366-4DAC-9372-DCF6F9151DCB`, and an optimized `Release`
build at `c950d46` plus the launch-flagged measurement probe added with this
baseline. `Tools/CaptureLunarExplorerZoomLadder.sh` ran each existing stop for
20 seconds with `LUNAR_CAPTURE_PROFILE=1`. The first five-second window covers
resource loading; the final window is the settled measurement below. The
display link advertised 11.11 ms but the Simulator delivered a stable 60 Hz
cadence, so the probe counts hitches against the slower observed cadence. The
`physical` column is the process's Mach physical footprint, not device memory
pressure.

| Stop | Progressive completion records | Completion range | Settled frame mean / p95 | Settled max / missed | Settled physical |
|---|---:|---:|---:|---:|---:|
| Globe | 0 | — | 16.67 / 16.67 ms | 16.67 ms / 0 | 312.2 MiB |
| Global detail | 0 | — | 16.67 / 16.67 ms | 16.67 ms / 0 | 312.2 MiB |
| Crossfade | 0 | — | 16.67 / 16.67 ms | 16.67 ms / 0 | 312.0 MiB |
| Orbit | 0 | — | 16.50 / 16.67 ms | 22.22 ms / 0 | 313.1 MiB |
| Regional | 0 | — | 16.67 / 16.67 ms | 16.67 ms / 0 | 311.9 MiB |
| Approach, 2 m | 0 | — | 16.67 / 16.67 ms | 16.67 ms / 0 | 311.5 MiB |
| Terminal, 0.5 m | 8 | 252–356 ms | 16.67 / 16.67 ms | 22.22 ms / 0 | 336.5 MiB |
| Landing, 0.125 m | 33 | 1,471–2,043 ms | 16.67 / 16.67 ms | 16.67 ms / 0 | 380.8 MiB |
| Relief blend start | 32 | 1,334–1,815 ms | 16.67 / 16.67 ms | 22.22 ms / 0 | 370.6 MiB |
| Relief blend end | 32 | 1,390–1,882 ms | 16.67 / 16.67 ms | 16.67 ms / 0 | 377.4 MiB |
| Surface | 32 | 1,351–1,819 ms | 16.67 / 16.67 ms | 16.67 ms / 0 | 368.6 MiB |

The cold resource-loading windows still hitch. The worst observed single
callback was 643.77 ms at the relief-blend-end stop, and the transient physical
footprint peaked at 406.5 MiB during the 0.125 m landing stop. All fine tiles
completed before the final window. The two instrumented passes produced
byte-identical screenshots at all eleven stops. Against the earlier unprofiled
Stage 1 acceptance ladder, the first ten stops are byte-identical; Surface has
normalized RMSE 0.0000633 after the shorter 20-second settle. Raw logs,
screenshots, hashes, and `performance.tsv` are in
`/private/tmp/LM-Stage2-Release-Baseline-2026-09-04-v2/`. Instruments attached
to the Simulator process but did not finalize a usable RealityKit, game, or
Time Profiler trace, so this baseline uses the launch-flagged `CADisplayLink`
and Mach sampler. A physical Vision Pro Release run still has to measure true
90 Hz frame pacing, memory pressure, thermals, and gesture comfort.

**Measurement correction, 2026-09-05.** The table's physical footprint values and
the reported 406.5 MiB maximum are five-second observations, not a kernel
high-water bound. Arrival profiling now adds the kernel lifetime peak and
phase-boundary samples. Global Explorer and Apollo captures expose a separate
startup peak near 1.6 GiB. Retain the original sampling metric for
comparison, but do not use it alone to claim a memory budget passes. Simulator
Metal allocation counters return zero and cannot establish device GPU pressure.

## 8. Validation

### Stage 2 item 2 evidence, 2026-09-04

The seven floating-anchor test methods pass, including four RealityKit site
cases. Five hundred canonical-coordinate transitions through Apollo, a
highland location, both polar regions, and the antimeridian have a maximum
Double round-trip error of `2.1234e-10 m`. Independent neighboring source
frames agree on shared positions within `1e-6 m`. The worst measured Float
hierarchy transition is `0.503542 mm`, below the 1 mm test limit. At Apollo the
same test measures `0.000238419 mm`. Near-pole regression tests also cover the
old `asin(z/r)` precision loss; `atan2(z,hypot(x,y))` keeps round trips below
`1e-8 m` even within centimeters of a pole.

The optimized Simulator app builds successfully. Both eleven-stop ladders at
`/tmp/LM-Stage2-Anchor-Ladder/` and
`/tmp/LM-Stage2-Anchor-Ladder-Final/` are byte-identical to item 0 at every stop.
The first pass retains 16.67 ms settled p95 with no missed callbacks throughout.
Fine-tile completion ranges are 282–369 ms at Terminal, 1,485–1,937 ms at
Landing, and 1,451–2,324 ms at Surface. Surface physical footprint is 343.3 MiB
versus item 0's 368.6 MiB; this is Simulator process footprint, not device
memory pressure. The later pass has unstable cadence and completion times up
to 3,892 ms; the subsequent baseline-test launch failed with Simulator Mach
error -308 and a dead service. These later timings are retained, not presented
as evidence of stable performance. The capture harness now attributes records
only to accepted launch PIDs, excluding an observed stale process record.

The stationary re-anchor artifact is `/tmp/LM-Stage2-Anchor-Probe/`. Endpoints
settle for at least 90 seconds, and ten consecutive transition captures span
the trigger. The actual trigger retains 32 resident tiles, has zero pending
bakes, and causes no tile regeneration. Its containing five-second frame
window has 16.67 ms maximum and zero missed callbacks. Normalized image RMSE
across the coordinate change is 0.000197233; mean absolute channel change is
0.003002 on a 0–255 scale. The largest mean change among horizontal and
vertical 8-pixel bands is 0.001927%. The settled endpoint matches the first
post-trigger frame exactly. No coverage hole, card edge, or new seam is visible.

The broader run has 97 passes and one failure in 98 test methods. The failure,
`SourceBackedTerrainTileTests.explorerLandingTileMissionSunShadingVariationNeedsNoPerTileGain`,
also reproduces alone. Its synthetic six-second Explorer corridor and
per-tile 2% shading assertion are outside the changed coordinate path; no
terrain correction or relaxed bound was applied. Full results and console
output are preserved in `/tmp/LM-Stage2-Anchor-Validation/`.
The sampling investigation below resolves this failure without changing the
renderer or either radiance limit.

Physical Vision Pro still has to validate 90 Hz pacing, memory pressure,
thermals, gesture comfort, and continuous re-anchoring. Item 2 does not claim
global source coverage, curved Apollo geometry, new navigation, or arbitrary
contact; those remain the following items.

### Stage 2 item 3 evidence, 2026-09-04

Ten elevation tests pass in the visionOS 26.5 Simulator. They cover actual
bundled-source and label hashes, exact measured posts, pixel registration and
units, antimeridian/polar continuity, deterministic curved geometry, persistent
offline replay, corruption repair, bounded LRU eviction, response validation,
interrupted region resume, coalesced requests, cancellation, and diagnostic
launch gating. Results and console output are in
`/tmp/LM-Stage2-Elevation-Validation/`. An independent public PDS request returns
HTTP 206 for bytes `1370787840-1396869119/1415577600`, exactly 26,081,280 bytes,
matching the catalog SHA-256. Independent NumPy decoding at 0.67°N, 25°E gives
−2,087.100150585175 m above the ME datum.

The Release build succeeds. Its Simulator bundle occupies 448,428 KiB,
31.851563 MiB more than item 2 including executable growth. The new data itself
is 33,182,721 bytes, or 31.645509 MiB. Every one of the 11 pre-existing terrain
assets still matches `c950d46` byte for byte.

The initial three-case capture is `/tmp/LM-Stage2-Elevation-Live/`. The final
four-case run is `/tmp/LM-Stage2-Elevation-Final/`, with the cache explicitly
isolated and restored. Cold SLDEM load is 2,696 ms; persistent offline replay is
156 ms; the global base at 42°S, 120°E is 103 ms; an offline cache miss at the
SLDEM coordinate falls back to LOLA in 268 ms. The streamed and offline images
are byte-identical across both runs. All final settled callback windows have
16.67 ms p95 and maximum, with zero missed callbacks. Settled process footprints
are 91.9–99.4 MiB. Startup still hitches, with maxima of 123–249 ms in the final
run; this does not establish device performance.

The normal Apollo control at `/tmp/LM-Stage2-Elevation-Apollo-Control/` covers
Globe, Terminal, Landing, and Surface after 90 seconds each. All four screenshots
are byte-identical to item 0. All settled windows retain 16.67 ms p95/maximum
and zero missed callbacks. Terminal completes in 221–277 ms, Landing in
1,357–1,719 ms, and Surface in 1,165–1,805 ms. Settled physical footprints are
304.5, 330.0, 368.2, and 347.7 MiB respectively, compared with item 0's 312.2,
336.5, 380.8, and 368.6 MiB. This controlled run shows no Simulator regression;
the earlier unstable item 2 timings remain recorded above.

The measured-only preview visibly retains its finite patch boundary and its
coarse-source interpolation. These captures validate the elevation consumer,
offline behavior, and provenance. They are not the whole-plan seamless zoom
ladder or arbitrary-location landing acceptance. The broader item 2 radiance
test failure is retained above as the starting point of the separate sampling
investigation below.

### Radiance validation follow-up, 2026-09-04

The old per-tile shading test sampled 49 points in a 6 m central square of
each 16 m tile. It reported a 0.957490 parent/child ratio for one tile. Replacing
its invented contact-gradient normals with the actual mesh normals and using
the current Explorer corridor still gave 0.957530. Those stale inputs did not
explain the failure.

Integrating the complete tile at 0.125 m spacing gives ratios from 0.997837150
to 1.000703642 across all 24 landing tiles, with mean 0.999996728. Repeating
the integration at 0.25 m changes a ratio by at most 0.000148156, or 0.014816
percentage points. The test now uses the generated normals, the actual mesh
triangle interpolation, the mission ephemeris, and the complete tile area.
It retains the 2% per-tile and 0.5% ensemble limits and adds a 0.1 percentage
point convergence limit. No per-tile gain or renderer change was made.

This corrects a biased estimate of mean tile shading. It does not replace
the narrow-band image acceptance for local seams, nor claim that every small
patch must have the same shading at every LOD. The diagnostic failures and
passing integration result are preserved in
`/tmp/LM-Stage2-Radiance-Validation/`.

The final visionOS 26.5 Simulator run passes all 108 tests across ten suites:
elevation, floating origin, globe, selenographic coordinates, detail streaming,
Explorer, progressive terrain, source-backed tiles, terrain-relative descent,
and landing. There are no remaining failures in that run. Its complete summary
and console are `/tmp/LM-Stage2-Final-Validation/tests.txt` and
`/tmp/LM-Stage2-Final-Validation/tests-console.txt`. Xcode MCP timed out before
returning the longer tests; the completed Xcode result artifacts supply the
reported counts.

### Whole-plan acceptance

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
