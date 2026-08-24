# Lunar terrain pipeline

## Fidelity contract

Measured terrain is authoritative. Procedural detail may add only frequencies
below the best available source resolution and must never move a measured
sample. The same absolute lunar coordinate and generator version must always
produce the same result.

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
  a bounded residual that is exactly zero at every 2 m measured post.
- **Appearance:** the WAC empirical mosaic supplies photometrically normalized
  broad reflectance at about 99.7 m/pixel in the near and medium bands and
  473.8 m/pixel in the far band. The near texture adds only bounded,
  exposure-normalized high-frequency contrast from the two registered 0.5 m
  NAC observations. That detail fades to zero through the outer 128 m collar,
  and the far WAC band is registered to the medium boundary. Textures encode a
  linear 643 nm reflectance proxy as sRGB; mission lighting and mesh normals
  remain dynamic in RealityKit. Diagnostic hillshade is never surface color.

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

## Next fidelity layers

1. Characterize the two NAC observations' photometric response more precisely,
   or replace their exposure-normalized residual with a calibrated NAC mosaic
   if one becomes available. Keep WAC as the absolute reflectance reference.
2. Stream nested tiles around the vehicle with crack-free edge morphing rather
   than keeping the full near-field mesh resident.
3. Move dense terrain updates to RealityKit `LowLevelMesh` and Metal compute
   after measuring the current CPU mesh path on Vision Pro.
4. Add deterministic, geology-conditioned microcraters, rim breakup, ejecta,
   and instanced blocks. Each generated feature must retain provenance as
   synthesized detail and must not alter measured macro relief.
5. Separate visual displacement from the conservative landing-contact mesh and
   validate both across the complete P64-to-contact trajectory.

The terrain milestone is complete only when an Apollo 11 descent can move from
high altitude to contact without coverage gaps, coordinate drift, visible LOD
popping, or a frame-time/comfort regression on Vision Pro.
