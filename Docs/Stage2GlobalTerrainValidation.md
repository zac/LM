# Stage 2 global terrain validation

This record supplements the controlling `LandAnywhereMoonPlan.md`. Implementation
and numerical checks are separate from visual and mission acceptance. The global
path is not yet accepted as a seamless globe-to-surface experience.

## Item 4: source ownership and amplification

The production Explorer accepts `--lunar-explorer-coordinate=latitude,longitude`.
The original Apollo pack keeps its planar evaluator, source bytes and default
presentation. Global regions resolve an immutable source set before generating
geometry. Network completions cannot silently upgrade an active region.

The global measured floor is bundled LOLA LDEM_16 (about 1,895 m). Pinned LOLA
LDEM_128 V3.0 strips provide about 236.901175 m posts everywhere; the existing
SLDEM2015 slab provides about 59.2 m where its actual downloaded coverage applies.
Normalized WAC EMP 643 nm is the only streamed reflectance input. Missing
reflectance uses a declared uniform model. WAC morphology is confined to the
unlit globe. The Apollo-only neural model is not applied to global geology;
validated N3 conditioning remains outstanding.

`pin_lola_strips.py` verified the complete 2,123,366,400-byte LDEM_128 raster before
pinning 720 overlapping strips. The full raster stays in the ignored generator
cache. Each transport range has at most 34 rows (3,133,440 bytes); neighboring
ranges share two native rows. Latitude arithmetic uses the original raster row
origin, giving bit-identical overlap samples rather than strip-local rounding.

- Image SHA-256: `0ab81a3e8d20e5528a21bc6c994974726cb486198013085f4c423c86fbd1154b`
- Label SHA-256: `85b1901def6901ee8a50415384f17a71e773af2d979beb7245fd6ac4d5e1671b`
- Strip catalog SHA-256: `3cb3fa9507cfe174ae0c0698a684f4c3704b507b6213b0d78a2c6ac6ab303181`
- Source: <https://imbrium.mit.edu/DATA/LOLA_GDR/CYLINDRICAL/IMG/LDEM_128.IMG>

The label explicitly documents latitude-band artifacts at 45-degree boundaries
and interpolation in measurement gaps. Those limitations remain part of the
source provenance. Smoothing them away would change the measured-post contract.

The versioned residual is `lunar-source-anchored-octaves-v1`: fixed Moon-centered
projections extend the existing crater morphology through 1/4/16/64 scale factors,
up to 76.8 m diameter. Subtracting the bilinear combination of native-post model
values makes the residual exactly zero at owned measured posts. The source's
own cap ratio controls the bounded residual; it is not a global hard-coded cap.
Tests include a non-default 0.03 ratio as well as the approved 0.12 ratio.
The crater-size extension follows the small-crater regime discussed in
<https://ntrs.nasa.gov/citations/19800068354>; it does not claim every lunar region
has Surveyor's measured crater abundance or geological history.

The existing planner/baker supports 512/128/32/8/2/0.5/0.125 m meshes globally.
Each child reads the actual submitted parent triangles, including its parent's
morph collar. A complete generation publishes together. CPU copies of those
vertices supply contact. Tile centers are subtracted in Double before Float
conversion, and each chunk is placed directly in the active ENU. A bounded
per-region post-value cache improves source sampling without changing values.

The 210 km handoff originally intersected the globe because a 1 cm foreground
offset cannot contain kilometer-scale relief. A bound over the submitted region
now applies a homothety about the eye to move the full region ahead of the globe,
preserving every monocular projected point. This requires stereoscopic comfort
validation on physical Vision Pro.

## Numerical and Simulator evidence

All runs use visionOS Simulator UDID `8F38C0E7-6366-4DAC-9372-DCF6F9151DCB`.
Captures wait for the production geometry-ready event and then settle at least
90 seconds. Tile tint, normal-map-off and shadow-off controls are diagnostics,
not acceptance images.

- `/tmp/LM-Stage2-Resolver-Triangles-v2.xcresult`: 16 resolver/elevation tests
  passed. The 100-sample spherical graph probe had maximum radial error
  0.000052729854 m; its cached kernel took 0.021786333 s versus 0.147372334 s
  before post memoization. Parent-edge height and normal error were both zero.
- `/tmp/LM-Stage2-Global-Geometry-v5.xcresult`: 20 resolver, floating-origin and
  existing landing tests passed. Distant chunks at 50–64 km, with 4.2 km
  re-anchors, had worst Float presentation error 0.000905842703 m (under 1 mm).
  The foreground-bound test preserves every projected corner and bounds depth.
- `/tmp/LM-Stage2-Item4-Apollo-Control/`: Globe and Surface PNGs are byte-identical
  to item 0. Settled p95/max were 16.67 ms, zero missed frames. Physical footprint
  was 305.9/381.0 MiB; the item 0 Globe/Surface values were 312.2/368.6 MiB.
  Surface tile builds were 1260–1671 ms. This run does not cover all eleven stops.
- `/tmp/LM-Stage2-Global-Depth-Corridor/`: highland point −42°, 120°, final
  near-field and bounded-depth handoff controls. The globe intersections are
  removed. A coarse triangular near-field patch remains visible at the edge.
- `/tmp/LM-Stage2-Global-Tile-Control/` and
  `/tmp/LM-Stage2-Global-Geometry-Control/`: tile tint identified the intruding
  surface as a terminal parent; disabling shadows and normal maps did not remove
  it. Widening the fine view corridor reduced but did not eliminate the artifact.
- `/tmp/LM-Stage2-Global-Coarse-Ladder/`: highland 128/32/8 m and handoff captures.
  Their generation times were 5653/3479/4907/6899 ms. These precede the final
  depth-bound fix and must not be presented as accepted final handoff images.
- `/tmp/LM-Stage2-Item4-Offline-Reanchor/`: an offline production region and
  before/after capture of the actual re-anchor trigger, with no geometry rebake.
  The final per-frame and image-difference results are recorded below.

Open gates: the coarse near-field intrusion; temporal band-arrival continuity;
site-specific handoff radiance at arbitrary locations; global source-join visual
acceptance; the complete Apollo/mare/highland ladder; N3 geology conditioning;
and physical Vision Pro frame timing, memory, stereo depth and gesture comfort.
No acceptance threshold has been relaxed to close these gates.
