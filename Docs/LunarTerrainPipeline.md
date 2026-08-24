# Lunar terrain pipeline

## Fidelity contract

Measured terrain is authoritative. Procedural detail may add only frequencies
below the best available source resolution and must never move a measured
sample. The same absolute lunar coordinate and generator version must always
produce the same result.

The current Apollo 11 vertical slice uses the LROC
`NAC_DTM_APOLLO11` v1.9 product pinned in
`LM/Terrain/TerrainManifest.json`:

- **Near field:** 1,024 × 1,024 posts at 2 m spacing, centered on the Apollo 11
  retroreflector coordinate. These samples drive rendered geometry, local
  surface-height queries, dust placement, and terminal procedural refinement.
- **Horizon foundation:** 512 × 512 posts at 32 m spacing with lunar curvature.
  Source elevations are used inside the NAC DTM footprint. Outside that narrow
  footprint, the nearest boundary elevation is held before curvature is
  applied. This prevents a missing horizon but is not claimed as measured
  topography.
- **Terminal residual:** below 250 m altitude, a deterministic 0.5 m grid adds
  a bounded residual that is exactly zero at every 2 m measured post.
- **Appearance:** albedo is currently flat neutral regolith under a
  mission-angle directional light. Diagnostic hillshade is not used as albedo.

The runtime coordinate convention is +X north, +Y up, and -Z east. The cockpit
stays fixed around the wearer while the lunar world receives the inverse
vehicle pose at 1:1 scale.

## Reproduction

`Tools/TerrainGenerator` verifies the 118 MB source GeoTIFF by byte count and
SHA-256, cross-checks its committed PDS label, and records its own source hash.
With identical inputs, every committed runtime terrain asset and manifest is
byte-for-byte reproducible.

## Next fidelity layers

1. Replace horizon boundary holding with registered global LOLA/SLDEM tiles.
2. Add a pinned, photometrically normalized LROC NAC orthomosaic instead of
   treating hillshade as surface color.
3. Stream nested tiles around the vehicle with crack-free edge morphing rather
   than keeping the full near-field mesh resident.
4. Move dense terrain updates to RealityKit `LowLevelMesh` and Metal compute
   after measuring the current CPU mesh path on Vision Pro.
5. Add deterministic, geology-conditioned microcraters, rim breakup, ejecta,
   and instanced blocks. Each generated feature must retain provenance as
   synthesized detail and must not alter measured macro relief.
6. Separate visual displacement from the conservative landing-contact mesh and
   validate both across the complete P64-to-contact trajectory.

The terrain milestone is complete only when an Apollo 11 descent can move from
high altitude to contact without coverage gaps, coordinate drift, visible LOD
popping, or a frame-time/comfort regression on Vision Pro.
