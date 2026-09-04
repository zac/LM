# Lunar terrain pipeline

## Fidelity contract

Measured terrain is authoritative. Below the best available source resolution,
procedural detail is plausible synthesis anchored to truth: it must never move
a measured sample. The same absolute lunar coordinate and generator version
must always produce the same result.

Procedural relief is no longer visual-only. `LMLunarGeologyModel` shape now
reaches the landing-gear contact surface, so the ground the crew can see is the
ground the footpads touch. This is a deliberate change from the earlier
conservative contract and is bounded by the same rules: the residual is
deterministic, capped per elevation source at `0.12 × source post spacing`, and
exactly zero at every measured post, so no synthesized feature can move a
measured one. Apollo 11's 2 m LROC source therefore retains its existing
0.24 m cap. Appearance-only detail —
`LMRegolithMicrotextureModel`, described below — remains strictly outside both
the mesh and the contact surface. The synthesized rock fragments also remain
non-colliding: they are explicitly not surveyed coordinates and must not decide
a landing.

The current Apollo 11 vertical slice combines the LROC
`NAC_DTM_APOLLO11` v1.9 product, two registered 0.5 m NAC orthorectified
observations, the LROC WAC empirical normalized 643 nm reflectance mosaic,
and LOLA/SELENE `SLDEM2015` V2.0. All eight source inputs and their exact PDS
byte ranges are pinned in
`LM/Terrain/TerrainManifest.json`:

- **Near field:** 1,025 × 1,025 posts at 2 m spacing, centered on the Apollo 11
  retroreflector coordinate. These samples drive rendered geometry, local
  surface-height queries, dust placement, and terminal procedural refinement.
- **Medium field:** 513 × 513 render posts at 32 m spacing over 16.384 km,
  constrained by the native 512-pixel/degree SLDEM2015 product (about 59.2 m
  per source post at the equator). A 1.024 km collar fades only the SLDEM
  vertical bias so its inner boundary exactly matches the measured NAC tile.
  The 32 m grid is interpolation density, not a claim of 32 m source detail.
- **Far field:** 513 × 513 render posts at 512 m spacing over 262.144 km,
  sampled from the global 128-pixel/degree SLDEM2015 product (about 236.9 m
  per source post). A 16.384 km bias collar registers its inner boundary to
  the medium field. This covers the geometric horizon throughout P64-P66.
- **Terminal residual:** below 250 m altitude, a deterministic 0.5 m grid adds
  bounded sub-resolution morphology. Below 60 m, a nested 0.125 m landing tile
  preloads craterlets down to 0.25 m diameter. Each level contributes only its
  new spatial band and morphs that band to the actual rendered parent through
  an edge collar. Parent and child boundaries therefore remain identical even
  where their tile edges coincide.
- **Close-range appearance:** each fine clipmap tile bakes its own small
  albedo and tangent-space normal texture addressed by tile-local UVs.
  `LMRegolithMicrotextureModel` supplies the 1-20 cm band that neither the
  0.125 m geometry nor the 0.5 m NAC texture can express: centimetre clods,
  small fragments, and 2-20 cm craterlets on the same Surveyor size-frequency
  slope, bounded to 1.5 cm of relief. The albedo texture is the measured
  reflectance resampled for the tile and multiplied by bounded micro-contrast
  around 1, so the source stays the reference rather than being replaced.
  Both fade to nothing through the tile's outer collar, matching the geometry's
  edge morph. RealityKit's PBR materials expose one texture-coordinate buffer,
  which is why the tile carries its own reflectance slice instead of sharing
  the near-field atlas with a second world-scaled detail map.
- **Appearance:** the WAC empirical mosaic supplies photometrically normalized
  broad reflectance at about 99.7 m/pixel in the near and medium bands and
  473.8 m/pixel in the far band. The near texture adds only bounded,
  exposure-normalized high-frequency contrast from the two registered 0.5 m
  NAC observations. That residual is strongest around the landing-site origin
  and fades radially to zero at the first near-tile edge. This preserves almost
  all NAC detail throughout the terminal landing area without exposing a square
  source footprint in regional views. The far WAC band is registered to the
  medium boundary. Textures encode a
  linear 643 nm reflectance proxy as sRGB; mission lighting and mesh normals
  remain dynamic in RealityKit. Source-backed terrain has exactly one
  mission-oriented directional light at 10.77 degrees elevation, exposed at
  25,000 RealityKit lux to retain relief without clipping the black-sky
  composition. A bounded texture-derived floor prevents fully shadowed texels
  from quantizing to black without replacing the low-Sun PBR response.
  Diagnostic hillshade is never surface color.

The runtime coordinate convention is +X north, +Y up, and -Z east. The cockpit
stays fixed around the wearer while the lunar world receives the inverse
vehicle pose at 1:1 scale.

### Floating Explorer coordinates

The Explorer keeps source geometry in its original site frame and places that
subtree inside `LMLunarFloatingOrigin`'s active spherical ENU. A 4,096 m
three-dimensional focus drift triggers a new anchor. Both source-to-anchor and
anchor-to-view rigid transforms are computed from canonical Double coordinates
and applied together; rotations include normals and lights. Re-anchoring never
regenerates heights, materials, tile plans, or contact. Float32 focus-coordinate
spacing is at most 0.48828125 mm at the trigger. This is a focus bound, not a
precision guarantee for distant vertices. New fine source meshes must be
chunk-local before Float conversion.

This coordinate operation preserves Apollo's planar geometry exactly in real
arithmetic. It does not bend Apollo onto the datum sphere or extend its source
coverage. The global resolver must author spherical geometry separately. Lunar
Cartesian-to-latitude conversion uses `atan2(z, hypot(x,y))`; the old `asin(z/r)`
lost up to 3 cm in a measured near-pole round trip.

`Tools/CaptureLunarExplorerReanchor.sh` holds a Surface view in a frame offset
by 4.2 km, then releases the production trigger after 100 seconds. It captures
settled endpoints, consecutive transition frames, residency logs, and frame
timings without changing the camera focus or source data.

## Pinned elevation transport and offline base

`LMLunarElevationStore` fetches the catalog's complete, fixed-record SLDEM
slabs over HTTPS. It requires HTTP 206 with the exact byte range and total
product size before reading the body. A response cannot exceed the pinned
byte count, and a complete SHA-256 check precedes atomic publication. The
128 MiB content-addressed disk cache verifies every hit, repairs corruption,
coalesces concurrent requests, and evicts least-recently-used slabs. Transient
transport failures get at most three attempts. Region prefetch resumes at
verified slabs; it rejects a region larger than its disk budget. Offline mode
cannot issue a network request.

`LMLunarElevationGrid` owns format conversion. SLDEM2015 V2.0 float32 samples
are kilometers above the 1,737,400 m datum. LOLA LDEM_16 V3.1 int16 samples
are half meters above that same datum. Both use pixel-center registration.
Bilinear interpolation returns each measured post exactly. The global base
wraps longitude; each unmeasured half-post polar cap converges to the mean of
its nearest measured row, retaining that row's exact samples.

The bundled raw LOLA image and its label occupy 31.645509 MiB within the
owner's 32 MiB approval. They are copied verbatim from the already pinned
source, independent of the existing Apollo height maps and globe normal map.
The global measured floor remains about 1,895 m per post.

The first runtime consumer is the capture-only measured elevation preview.
`--lunar-explorer-capture --lunar-explorer-elevation-preview=0.67,25` renders
a curved 16.384 km patch from the pinned 59.2 m SLDEM slab. Add
`--lunar-explorer-elevation-offline` to require cache reuse. Outside that
slab, or on a transfer failure, it renders the complete patch from the bundled
base. Source identity, measured floor, load duration, and any fallback reason
are logged. Its 128 m render spacing and constant gray material are diagnostic;
it does not claim full SLDEM resolution, normalized reflectance, procedural
amplification, or landing contact. The following resolver item must connect
the production band stack and contact to these same decoded sources.

`Tools/CaptureLunarElevation.sh` captures a cold streamed source, offline
replay, global-base coverage, and an offline cache miss after source readiness
plus 90 seconds of settling. It isolates the elevation cache and restores the
original cache on exit. Streamed and offline captures must be byte-identical.
The normal Apollo Explorer path does not load this base or open the elevation
cache.

## Global map-scale Moon

The first land-anywhere tier is a pinned 16-pixel-per-degree LROC WAC global
morphologic mosaic. `GlobalLunarMosaicGenerator` validates the complete source
file and its attached PDS label before converting little-endian PC_REAL
reflectance to a fixed-transfer sRGB PNG. Manifest schema 6 records the source,
generator, projection, datum radius, texture dimensions, and generated-file
hash. The same tool verifies the 16 ppd global LOLA `LDEM_16` image and label,
then derives a detrended ME-frame normal field from elevation above the pinned
reference sphere. The raw PDS products remain in the ignored generator cache;
the app bundles only the reproducible texture, normal field, and provenance
sidecar.

`LMLunarGlobeResource` creates its sphere in the same Mean Earth/Polar-axis
coordinate authority used by the landing terrain. The mesh display basis is
centered on Apollo 11 for the initial Explorer view, with east to the right and
north up. Because morphologic WAC already contains illumination, the runtime
uses it as unlit map color rather than applying the movable mission sun a
second time. A black unlit shell applies the session ephemeris terminator as a
brightness multiplier. Its 512×256 dynamic mask samples the LOLA-derived
normal field, so map-scale relief perturbs only the terminator and never
becomes a second lighting pass. The current whole-Moon-to-site gate is
deliberately discrete; the crossfade and budget-gated 64-pixel-per-degree tier
remain Stage 1 work in `Docs/LandAnywhereMoonPlan.md`.

## Coordinate-frame alignment

The terrain and Luminary do not share an origin. The measured terrain products
remain centered on the Apollo 11 retroreflector at 0.673433° N, 23.473113° E,
while the AGC navigation state is local to Luminary's reference landing site.
Using `state.positionMeters` directly as terrain north/east would therefore put
the nominal P66 contact about 930 m away from the real landing site.

`LMTerrainFrameAlignment` makes that translation explicit. The generated
manifest pins Eagle at 0.67408° N, 23.47297° E from JPL D-32296 table 5-1. In
the terrain tangent plane that is 19.619 m north and 4.336 m west of the
manifest origin. The bundled contact-gated P66 trajectory's nominal touchdown
maps to Eagle, and any live north/east deviation is preserved exactly. This is
a visual georeference only: it does not modify the AGC, vehicle dynamics,
guidance state, altitude, or attitude.

Surface-height queries, the inverse lunar-world transform, progressive LOD
focus, and descent-engine dust all consume the aligned terrain position. A
fixture regression test prevents regenerated P66 data from silently moving the
calibration point.

## Synthesized terminal geology

`LMLunarGeologyModel` replaces generic value noise with deterministic crater
morphology. Its cumulative diameter distribution uses the Surveyor steady-state
small-crater exponent of -2; generated diameters are restricted to 0.22–1.2 m,
inside the published Surveyor 0.13–3 m observational range and below the 2 m
LROC geometry posts. Profiles include age-dependent bowls, elliptical forms,
broken raised rims, and weak directional ejecta. Apollo 11 site reporting
constrains the qualitative context: the immediate landing region was relatively
free of rocks but covered with craters from roughly 100 ft to less than 1 ft.

Below 1.2 m, feature coordinates, crater ages, ellipticity, rim breakup, and
ejecta remain synthesized and are not claimed as measured Apollo 11 features.
From 2–8 m, the frozen `apollo11-nac-craters-v1.json` catalog places parametric
craters at high-confidence correlations in the registered 0.5 m NAC composite;
the photograph supplies position and scale while the geology model supplies
bounded morphology. Hash candidates overlapping those entries are suppressed.
The geometry is versioned by
`surveyor-degraded-microrelief-v3+apollo11-near-field-nac-craters-v1@nac-parametric-correlation-v1`.
A bilinear post-anchoring correction keeps the residual continuous across
measured cell boundaries and exactly zero at every LROC post. The visual
residual is smoothly bounded by the active source's manifest parameter; for
the 2 m Apollo 11 source that remains 0.24 m.

Primary morphology constraints:

- https://www.usgs.gov/publications/physical-characteristics-lunar-regolith-determined-surveyor-television-observations
- https://www.usgs.gov/publications/observations-lunar-regolith-and-earth-television-camera-surveyor-7
- https://ntrs.nasa.gov/api/citations/19700000726/downloads/19700000726.pdf

The lunar world is placed at its true relief around a fixed datum taken under
Eagle. It is no longer pinned to whatever is directly beneath the vehicle, which
used to slide the entire moon vertically as the LM crossed relief and made every
touchdown land on a flat plane regardless of what was drawn under it.

The terminal planner retains both the tile under the LM and the tile at a
six-second velocity projection. This normally prefetches one neighboring
0.125 m tile before a 16 m boundary crossing. The coarser parent remains
resident throughout. Each stable tile ID owns its generation task and token;
request churn cancels only obsolete IDs and cannot repeatedly restart a still
required under-vehicle tile. Cancellation or slow generation therefore
degrades detail rather than exposing a coverage hole.

### Neural appearance reconstruction

Fine-tile albedo can pass through `LunarTerrainSR`, a compact 4x Core ML
model, after the deterministic procedural bake. The model consumes one
128 x 128 reflectance plane and reconstructs a 512 x 512 plane. Runtime then
subtracts the model's matching bilinear base and applies only its bounded
learned residual to the complete 512 x 512 procedural albedo. The model can
therefore add its learned frequency band without replacing measured or
deterministic microtexture that was lost in the 128 x 128 input. The current
procedural normal map remains authoritative. A smooth outer collar reduces the
learned residual to zero on all four tile edges, so neighboring tiles cannot
open a neural seam.

Core ML output decoding follows the multi-array's runtime scalar type rather
than assuming its declared compute precision. Predictions are also checked
against the architecture's +/-0.12 residual bound; a silently corrupt backend
result is treated as a prediction failure. The xrOS Simulator uses CPU-only
inference because its GPU path was observed logging an incompatible MPSGraph
backend and returning a zero-like tensor without throwing. Vision Pro builds
retain `.all` compute units. Model loading, invalid output, or prediction
failure falls back to the complete procedural tile, and cancellation remains
owned by the stable tile request in the scene.

The bundled `lunar-terrain-sr-nac-v2` model has 88,993 parameters and occupies
about 204 KB as a Core ML package. Training uses the two repository-pinned,
registered 0.5 m NAC observations. Their independent exposures are normalized
before averaging, then low-resolution inputs are produced by 4x area
downsampling and 8-bit quantization. The western 75 percent of the valid source
footprint is used for training and the eastern 25 percent for validation.
Export is quality-gated against bilinear scaling.

The accepted 5,000-step run improved held-out PSNR from 37.736 dB to 39.829 dB
(+2.093 dB) and reduced gradient error from 0.013253 to 0.012265 across 12
geographically held-out crops. Direct Core ML prediction on the development
Mac measured about 845 ms on first compile/load and 1.8-2.4 ms once warm, so
terrain loading prewarms the model concurrently. Complete debug-Simulator tile
time also includes the procedural 512 x 512 bake and Swift pixel conversion;
it must not be reported as neural inference latency.

Generated appearance tiles use a 32 MB byte-bounded LRU cache keyed by model
version, tile ID, tile size, and sample spacing. A 512 x 512 albedo-plus-normal
entry costs about 2 MB, retaining only the local working set rather than a
global reconstructed texture pyramid. Replacing model weights through a new
model ID invalidates old entries without changing terrain residency.

### Source-constrained rock fragments

`LMLunarRockFieldModel` adds a deterministic visual fragment layer versioned as
`apollo11-source-constrained-rock-field-v1`. NASA SP-214 reports that Eagle's
immediate region was relatively free of rocks, while a field several hundred
feet north contained boulders a meter or larger across. It also records rocks
resting on the surface, partly buried, and exposed nearly flush with the soil.

The runtime therefore protects a 25 m radius around Eagle from invented rocks,
places only sparse sub-meter fragments from 25 to 105 m, and synthesizes a
broad meter-class field 90 to 180 m north. The primary report does not survey
individual coordinates, so none of these fragment positions are presented as
mapped Apollo 11 rocks. Six shared faceted meshes, bounded burial, pose, and
reflectance variation supply silhouettes and low-Sun shadows without repeated
smooth spheres. Rock bases sample the measured 2 m NAC height field. They have
no collision component and cannot change contact, guidance, or landing outcome.
Meter-class boulders remain visible throughout P64; sub-meter fragments pass a
bounded altitude/detail gate and progressively appear below roughly 400 m to
avoid distant sub-pixel shimmer.

Primary constraint:

- https://ntrs.nasa.gov/api/citations/19700000726/downloads/19700000726.pdf

## Landing gear and terrain-relative contact

`LMLandingGear` in LMCore replaces the previous point-against-a-sphere contact
test with a four-leg crushable-strut model, and `LMTerrainContactSurface`
supplies the ground it touches.

- **Contact surface.** `LMTerrainContactSurfaceBuilder` evaluates the same
  clipmap surface that generates tile meshes — same plans, same edge morphs,
  same bounded procedural relief — over a patch around the vehicle at the
  finest rendered spacing, below 60 m altitude. Interpolating that patch
  reproduces the rendered mesh rather than approximating it, because the mesh
  is itself a linear interpolation of samples on the same grid. The gear solver
  queries the surface thousands of times per frame across its contact
  substeps, which the recursive evaluator cannot sustain live. Heights are
  referenced to the terrain under Eagle, so a nominal descent still touches
  down at guidance altitude zero while local relief is preserved exactly.
- **Geometry.** Published LM dimensions fix the 31 ft footpad-to-footpad
  spread, the 37 in footpads, the 68 in lunar-contact probes on the three legs
  other than the forward ladder leg, and the roughly 32 in of crushable
  primary-strut stroke. Touchdown CG height above the footpad plane, strut
  cant, and honeycomb crush load are *derived* from those dimensions plus the
  Apollo 12 velocity envelope already in `LMLandingContactCriteria`, and
  `LMLandingGearGeometry.modelingStatus` says so. The simulation's position
  vector is the vehicle reference that reads guidance altitude, which for a
  lander is the uncompressed footpad plane; gear reactions resolve about the
  center of mass above it, so tip-over depends on the real ratio of gear spread
  to CG height (about 43 degrees).
- **Energy path.** The footpad meets elastic-plastic regolith: load up to a
  bearing limit of about 13 kPa over the pad, then a plastic print capped at
  12 cm, then compacted soil. Beyond that the primary strut's honeycomb holds a
  near-constant crush load and strokes as far as it must. A 0.5 m/s arrival
  leaves a few centimeters of print and no stroke, matching Apollo; a 3 m/s
  arrival crushes about half the available stroke.
- **Settling.** The vehicle is no longer frozen at first contact. It keeps
  integrating on its gear, on a fixed 2 ms contact substep the flight loop's
  1/15 s delta cannot support, until every footpad is quiescent. That is what
  produces the small rebound off the elastic part of the pad, the rock onto the
  downhill legs of a slope, the skid arrested by regolith friction, and the
  difference between a soft arrival and one that visibly crushes honeycomb.
- **Failure.** A landing is lost when a primary strut runs out of honeycomb,
  when the vehicle rotates past its footpad support polygon, or when touchdown
  rates and tilt are outside the rated envelope. The cockpit failure cue names
  which one.

Generation costs, optimized build, visionOS simulator, per background task:
the 64 m / 0.5 m tile takes about 9 ms of mesh and 81 ms of texture bake, the
16 m / 0.125 m tile about 24 ms and 55 ms, and a contact patch about 55 ms.
Resident baked textures are about 2 MB per fine tile, plus one 17 MB CPU copy
of the measured near-field reflectance shared by all of them.

Two simplifications are deliberate and recorded here rather than hidden. The
footpad is a point against the pad-averaged surface normal, not a 0.94 m disc,
so a vehicle straddling a ridge can rest on two legs where a real pad footprint
would catch a third. And the gear solver integrates in the site tangent plane,
which over the final few meters differs from the moon-fixed arc by far less
than the honeycomb stroke it is resolving.

## Reproduction

`Tools/NeuralTerrain/train.py` trains and exports the compact appearance model.
With the two pinned NAC slabs in `Tools/TerrainGenerator/cache`, run:

```sh
uv run --with-requirements Tools/NeuralTerrain/requirements.txt \
  python Tools/NeuralTerrain/train.py \
  --steps 5000 --batch-size 4 --features 24 --blocks 4 \
  --validation-crops 12 \
  --output-dir Tools/NeuralTerrain/output/nac-production \
  --export-coreml LM/LunarTerrainSR.mlpackage
```

The ignored output directory receives the checkpoint, metrics JSON, and a
four-panel held-out preview. Core ML export is refused unless PSNR gains at
least 0.5 dB over bilinear and gradient error also improves. Validate the
committed model, accepted metrics, tensor contract, and weights hash with
`Tools/NeuralTerrain/validate.py` before changing the runtime model ID.

`Tools/TerrainGenerator` verifies the 118 MB NAC GeoTIFF by byte count and
SHA-256. It also verifies two contiguous SLDEM2015 geometry slabs, two 69 MB
NAC orthophoto slabs, an 18 MB 304-pixel/degree WAC slab, and north/south
64-pixel/degree WAC slabs fetched by exact HTTP byte range. The committed PDS
labels are independently cross-checked, and the manifest records full source
sizes and MD5 values where published, byte offsets, slab SHA-256 values, and
the generator hash. Manifest schema v3 additionally pins the photo-derived
crater catalog and detector hashes, source IDs, detector thresholds, and the
source-observation illumination used for template correlation. The app checks
the catalog digest and embedded provenance before it can affect rendering or
contact.
With identical inputs, every committed runtime terrain asset and manifest is
byte-for-byte reproducible.

All nested meshes use power-of-two-plus-one grids with shared boundary lines:
2,048 m, 16,384 m, and 262,144 m. Outer tiles punch exact square holes for
their inner tiles. Height values on each shared boundary are identical before
quantization, preventing overlaps, gaps, and vertical steps.
Measured and progressive triangles use upward-facing geometric winding that is
regression-tested against their vertex normals, allowing RealityKit's default
back-face culling without creating a black nadir coverage hole.

## Next fidelity layers

1. Characterize the two NAC observations' photometric response more precisely,
   or replace their exposure-normalized residual with a calibrated NAC mosaic
   if one becomes available. Keep WAC as the absolute reflectance reference.
2. Stream nested tiles around the vehicle with crack-free edge morphing rather
   than keeping the full near-field mesh resident.
3. Move dense terrain updates to RealityKit `LowLevelMesh` and Metal compute
   after measuring the current CPU mesh path on Vision Pro. The same compute
   pass can bake the per-tile detail textures, which are now the larger half of
   tile generation.
4. Replace the qualitatively constrained northern boulder field with surveyed
   photogrammetric/LROC fragment coordinates when a versioned point dataset is
   available, retaining the synthesized distribution only as a fallback.
5. Validate the rendered surface, rock silhouettes, and terrain-relative
   contact across the complete P64-to-contact trajectory, including
   tile-generation time and visible edge transitions on Vision Pro.
6. Give the footpad its real 0.94 m footprint in the contact solver, and source
   the derived gear values — CG height, strut cant, honeycomb crush load — from
   a landing-gear report rather than deriving them from the velocity envelope.
7. Build the contact patch from the tile meshes that were already generated
   instead of re-evaluating the surface, once tile residency can be relied on
   to cover the gear span.

The terrain milestone is complete only when an Apollo 11 descent can move from
high altitude to contact without coverage gaps, coordinate drift, visible LOD
popping, or a frame-time/comfort regression on Vision Pro.

For rapid simulator validation, launch with
`--terminal-descent-cockpit --cockpit-start-p65`. This retains the real bundled
P65 checkpoint and live Luminary/contact path while reaching the 0.5 m and
0.125 m LOD thresholds without replaying the full P64 approach.

## Lunar Explorer validation

The visionOS app also exposes a terrain-only Lunar Explorer. It renders the
same measured bands, reflectance textures, procedural geology, rock field,
mission sun, and progressive tiles as terminal descent, but removes the LM
cockpit from the inspection path. Virtual altitude selects production LOD;
view width changes only presentation scale, so zooming cannot silently request
a finer mesh and hide a transition defect.

The normal app entry point is **Lunar Explorer** in the powered-descent toolbar
or **Explore Apollo 11 terrain** in the main menu. For repeatable Simulator
captures, launch with:

```text
--lunar-explorer --lunar-explorer-preset=landing
```

Supported presets are `orbit`, `regional`, `approach`, `terminal`, `landing`,
and `surface`. Optional arguments select `--lunar-explorer-focus=eagle` or
`--lunar-explorer-focus=northBoulderField`, and
`--lunar-explorer-navigation=orbit` or `pan`.
Use `--lunar-explorer-detail=procedural` or
`--lunar-explorer-detail=neural` to force matched A/B captures through the
production tile pipeline. `automatic` remains the default. The controls window
offers the same selector; switching modes cancels obsolete generation, removes
the previous appearance tiles, and retains a separate model-versioned cache for
each mode. Geometry, normals, rocks, contact, coordinates, lighting, altitude,
and framing do not change.
Use `--lunar-explorer-altitude=<meters>` and
`--lunar-explorer-meters-across=<meters>` to override a preset after it is
applied. Numeric overrides are clamped to the interactive Explorer limits and
are independent of argument order, which makes paired captures immediately
above and below each production LOD gate repeatable.
Add `--lunar-explorer-capture` to hide the controls window after it has opened
the same production immersive scene. This avoids visionOS compositor focus blur
over the terrain without introducing a separate capture renderer.
Launch configuration is applied before restorable windows are constructed, and
an Explorer controls window restored by visionOS reopens the requested
immersive space. Repeatable captures therefore do not require deleting the app
between presets.

`Tools/CaptureLunarExplorerAB.sh` captures both appearance implementations at
0.5 m above and below the 2,500 m, 250 m, and 60 m production LOD gates, both
ends of the 40-25 m landing-presentation blend, and an 8 m surface close-up.
The 250 m, 60 m, and presentation-blend pairs use an 8 m close framing so their
sub-meter geometry contributes multiple pixels instead of disappearing inside
a wide context view. The 2,500 m gate remains a regional framing and is
expected to be a no-op with the current 2 m measured source: the policy already
has the requested spacing, so it correctly creates no redundant overlay.
The script records exact image hashes and ImageMagick RMSE for every registered
procedural/neural pair, and also records above/below RMSE so a supposedly
exercised sub-meter gate cannot silently produce two identical frames:

```sh
Tools/CaptureLunarExplorerAB.sh \
  <vision-pro-simulator-udid> \
  <derived-data-path>/Build/Products/Debug-xrsimulator/LM.app \
  Artifacts/LunarExplorerAB
```

The default capture wait is 30 seconds because an unoptimized Debug simulator
may need to realize the complete nine-tile landing safety footprint. It can be raised
with `LUNAR_CAPTURE_WAIT_SECONDS` on a slower machine. It should not be lowered
until Explorer diagnostics show every requested tile is resident; the script
intentionally compares the production asynchronous path rather than a private
synchronous renderer.

Set `LUNAR_CAPTURE_FILTER` to a comma-separated list such as
`terminal-below,surface` when a change only affects selected gates. Filtered
runs keep the same registered camera states and metrics but skip unrelated
transitions.

Each acceptance pass should check the named preset, active/requested tile
counts, finest mesh spacing, generation time, band boundaries, rock transition,
and stable framing while switching altitude independently from view width.

The first regional pass exposed the square 2.048 km NAC high-frequency
reflectance footprint against the 16.384 km WAC band even though geometry and
boundary pixels were registered. Explicit mipmaps, trilinear filtering, and
anisotropic sampling ruled out texture minification as the cause. The source
conditioner now weights only the NAC high-pass residual with a landing-centered
radial smoothstep: full detail remains around Eagle, while the result has
returned to the WAC parent before reaching the first tile edge or its corners.
The measured 2 m near mesh also geomorphs its outer render collar radially into
the measured 32 m parent's bilinear height and normals. This leaves the source
assets untouched and preserves full detail around Eagle, while making every
rendered child-edge vertex meet the parent surface between coarse posts. It
removes both remaining rectangular cues after the reflectance fix: the abrupt
normal-frequency change and sub-post cracks along the T-junction. A repeatable
`regional` Simulator capture no longer outlines the NAC crop, and the
corresponding tests check retained center detail plus the exact radial parent
handoff for height and normals.

The follow-up `landing` pass still loads both progressive levels and reports
0.125 m as the finest mesh. Stage instrumentation showed that the original
debug-Simulator build spent about 1.7 seconds on mesh generation, 2.9 seconds
on the appearance bake, and only 8 ms realizing the RealityKit resources. Mesh
and appearance now run concurrently, and the baker resolves each shared
craterlet field once for relief and reflectance instead of walking it twice per
texel. A clean repeatable landing capture completed its latest tile in 2.110
seconds (837 ms mesh, 2.090 seconds bake, 7 ms GPU), about 53% below the first
4.5-second measurement while using the measured grayscale NAC reflectance and
without changing texture resolution or the surface/contact geometry.
The first neural surface A/B exposed a destructive integration error: replacing
the full-resolution procedural tile with the model reconstruction visibly
smoothed the surface. Residual composition now preserves procedural gradient
energy and mean luminance in tests. A registered 8 m debug-Simulator pair after
that correction had normalized full-frame RMSE 0.00048 and no visible framing,
geometry, or tone shift. This proves the neural pass is non-destructive, not
that its gain is yet perceptually worthwhile. The complete gate matrix and
Release profiling on Vision Pro remain the acceptance measurements.
Additional row-strip parallelism was rejected
after measurement: requested tiles already generate concurrently, and the
extra workers starved their mesh tasks and
raised elapsed time. The full Vision Pro comfort/performance pass is still
required before device acceptance.

Close framing exposed a second residency problem that wide gate captures could
not show: Eagle lies only 4.34 m from a 64 m terminal-tile edge and within one
gear footprint of two 16 m landing-tile edges. The planner now keeps a 16 m
safety radius around the landing focus. At Eagle that is two terminal tiles and
a bounded 3x3 set of nine landing tiles, about 18 MB of cached albedo-plus-normal
bytes for the finest level. Progressive tile materials fade opacity through
the same outer smoothstep collar as geometry and procedural appearance. A
transparent child reads depth but does not write it, allowing the measured
parent underneath to contribute to the crossfade instead of being occluded by
a partly transparent rectangular card. The shared opacity texture is cached by
resolution and footprint-edge mask rather than rebuilt for every resident tile.
The 2,500 m pair remains exactly identical as expected from the already-resident
2 m source.

An aggressive close view then exposed a broad same-level cross where adjacent
child tiles independently returned to their parent. Each plan now records only
the edges that meet a coarser level after the planner combines the current and
prefetched footprints. Geometry morphing, procedural relief and reflectance,
neural residuals, opacity, and cache identity all use that same perimeter mask.
The scene replaces tiles only after their revised entities are ready, so a
changing footprint cannot leave a temporary hole. Shared-edge vertices and
normals also sample the same measured surface. The full registered matrix no
longer shows the cross; its updated procedural transition RMSE is 0.01976 at
the terminal gate and 0.02298 at the landing gate.

Tile textures now sample the exact world boundary at UV 0 and UV 1, making
procedural albedo and normals byte-identical across same-level neighbors. The
neural residual returns to the procedural result through a four-pixel inference
collar. Procedural microtexture is band-limited by texel footprint and approaches
the next coarser representable frequency through the footprint perimeter. The
geometry, albedo, normal, and opacity handoff now spans the complete outer tile:
the edge shared with an interior same-level tile remains fully resolved and the
outside edge reaches the exact parent. This removed the half-tile detail shelf
visible in the oblique surface preset, although the finite close-range footprint
is still perceptible enough that it remains open visual work.

A settled registered 60.5 m versus 59.5 m capture is pixel-identical within
each appearance mode, proving that preloading the landing tiles does not create
a visible residency pop. Settled procedural-to-neural normalized RMSE was
0.000803405 at 24.5 m and is 0.000832818 in the latest 2 m surface capture. The
surface difference remains localized to fine texture rather than rocks,
silhouettes, or framing. A 12-second Debug capture caught an incomplete child
set and is invalid acceptance evidence; 30 seconds is the current repeatable
Simulator baseline.

The checked-in model validator currently reports 88,993 parameters and a
2.093 dB held-out PSNR gain. The repeatable Core ML conversion benchmark reduced
the Swift reconstruction stage from roughly 143 ms to roughly 65 ms with the
same `e72ae97ae4bdb582` output checksum. Those numbers are conversion timings,
not tile latency: a Debug Simulator tile also includes the procedural 512x512
bake, mesh generation, resource realization, and simulator overhead. Tests
cover footprint ownership, prefetch unions, shared geometry and texture edges,
cache invalidation, fallback, neural edge restoration, and presentation/contact
alignment. A moving Vision Pro Release descent still has to establish frame-time,
generation latency, memory, thermal, and comfort budgets, and the remaining
close-range footprint cue must be removed before this phase is accepted.
