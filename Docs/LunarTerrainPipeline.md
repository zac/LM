# Lunar terrain pipeline

## Fidelity contract

Measured terrain is authoritative. Procedural detail may add only frequencies
below the best available source resolution and must never move a measured
sample. The same absolute lunar coordinate and generator version must always
produce the same result.

Procedural relief is no longer visual-only. `LMLunarGeologyModel` shape now
reaches the landing-gear contact surface, so the ground the crew can see is the
ground the footpads touch. This is a deliberate change from the earlier
conservative contract and is bounded by the same rules: the residual is
deterministic, capped at 0.24 m, and exactly zero at every measured LROC post,
so no synthesized feature can move a measured one. Appearance-only detail —
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
small-crater exponent of -2; generated diameters are restricted to 0.22–1.8 m,
inside the published Surveyor 0.13–3 m observational range and below the 2 m
LROC geometry posts. Profiles include age-dependent bowls, elliptical forms,
broken raised rims, and weak directional ejecta. Apollo 11 site reporting
constrains the qualitative context: the immediate landing region was relatively
free of rocks but covered with craters from roughly 100 ft to less than 1 ft.

Feature coordinates, crater ages, ellipticity, rim breakup, and ejecta are
synthesized, versioned by `surveyor-steady-state-microcraters-v1`, and are not
claimed as measured Apollo 11 features. A bilinear post-anchoring correction
keeps the residual continuous across measured cell boundaries and exactly zero
at every LROC post. The visual residual is smoothly bounded to 0.24 m.

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

`Tools/TerrainGenerator` verifies the 118 MB NAC GeoTIFF by byte count and
SHA-256. It also verifies two contiguous SLDEM2015 geometry slabs, two 69 MB
NAC orthophoto slabs, an 18 MB 304-pixel/degree WAC slab, and north/south
64-pixel/degree WAC slabs fetched by exact HTTP byte range. The committed PDS
labels are independently cross-checked, and the manifest records full source
sizes and MD5 values where published, byte offsets, slab SHA-256 values, and
the generator hash.
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
A repeatable `regional` Simulator capture no longer outlines the NAC crop, and
the corresponding asset test checks both retained center detail and the radial
parent handoff.

The follow-up `landing` pass still loaded both progressive levels, reported
0.125 m as the finest mesh, and completed its latest debug tile build in about
4.5 seconds. That latency remains a debug-Simulator optimization target before
device acceptance; the full orbit-to-contact preset sequence and Vision Pro
comfort/performance pass are still required.
