# FDAI gray-fill repair

The owner's running-cockpit screenshot showed both FDAIs as nearly uniform
gray disks with faint grid lines. Input main is `2f5aa38`; LMKit remains
`5287dfd`. Evidence is under `/tmp/LM-FDAI-2026-09-09/`.

## Cause isolated in the native renderer

The earlier LM fix already disables all `FDAI_Glass` entities. The packaged
LMKit asset still contains that cosmetic cover, but the remaining app washout
was reproduced with it disabled. The original LMKit ball texture contains
strong black/ivory regions and intact markings.

A small macOS RealityKit fixture loads the actual packaged USDZ, uses the same
camera/light for each image and changes only material treatment:

- `original.png`: the enabled cover adds a gray cast, especially to the dark
  hemisphere. Imported materials are recorded in `materials.txt`.
- `no-glass.png`: disabling the cover exposes a black lower hemisphere with
  white lines and an ivory upper hemisphere with dark lines.
- `app-policy.png`: applying the existing LM printed-face emissive treatment
  to that uncovered ball produces a broad gray lower hemisphere again.
- `fixed-policy.png`: applying the exact repaired `LMCockpitMaterialPolicy`
  source restores the black/ivory distinction and fine markings.

This is a controlled native-renderer observation, not a claim about the
physical instrument's optical stack. The temporary fixture scripts and native
snapshots are retained alongside the evidence.

## Change

FDAI ball surfaces now use `.attitudeBall`: the existing matte roughness and
low specular response, with black emissive color and zero emissive intensity.
Base texture, UVs, transforms, live attitude mapping, fixed reticle and existing
glass suppression are unchanged. Other panel markings retain their existing
material treatment. No LMKit authoring/package assets, AGC, terrain, mission
lights, exposure or guidance code changed.

## Validation

- **10 instrument integration tests pass** in 2.909 s on visionOS 26.5 Simulator
  using Xcode 26.6 (`InstrumentTests.xcresult`, `instrument-tests.log`). The
  native hierarchy regression requires the retained base texture, disabled
  glass, zero ball emission, matte response and unchanged fixed structure
  while the ball rotates. Existing orientation/sign tests pass unchanged.
- `cockpit-fixed.png` is the actual Debug LM app after terrain preparation,
  using the existing `--assembly-validation-view=cdr` observer and
  `--cockpit-validation-paused` arguments. Both FDAIs show distinct light/dark
  regions instead of the uniform gray disk. The grid/numerals remain dim
  under this mission light; this repair does not qualify all instrument
  legibility. `cockpit.log` confirms the artist cabin and terrain loaded.
- `capture-hashes.json` records image hashes and both the Debug executable
  stub and `LM.debug.dylib`; the latter contains the Debug runtime code.

No physical Vision Pro check, full-flight recapture or performance comparison
was run for this small material repair. Physical optical appearance, readability
under different lighting and tracked viewpoints remain open. The normal dirty
LM checkout and the cockpit owner's worktree remain untouched.


The ordinary Release LM build also passes (`release-build.log`). Executable
SHA-256: `d3181a3b0cfe9abe533663e58af9b5bc3125486b4242046103a351c9180603a4`.
The visual capture above is explicitly the Debug observer build, not a Release
or physical-device screenshot.
