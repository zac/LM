# Immersive fidelity foundation

The simulator treats visual fidelity as an engineering contract, not a one-off procedural model.

## Cockpit asset contract

An artist-authored `ApolloLMCabin.usdz` may replace the procedural cabin when it uses meters, identity root scale, and the coordinate convention `+X LMP/right, +Y overhead, -Z forward`. It must provide every named transform in `LMCockpitAssetContract.Node`. Empty transforms are valid for eye, mount, and control pivots.

The target asset should separate cabin shell, window panes, panel faces, legends, fasteners, fabrics, foil, hoses, breakers, guards, and movable controls. Geometry LODs and texture resolution can then change without changing simulation or interaction code.

The commander's window is a flight instrument. The LPD must remain two physical marking layers on the inner and outer panes. Do not bake both scales into one texture. The commander eye datum, pane planes, window frame, and LPD transforms require artifact or drawing validation before being marked flight-accurate.

## Terrain provenance and progressive detail

Measured LROC elevation is authoritative. `LMProgressiveTerrainSampler` may synthesize only the spatial frequencies below the loaded source post spacing. Its residual is deterministic, bounded, and zero at measured posts. Procedural relief must be labeled as synthesized in diagnostics and must disappear automatically when a higher-resolution measured source is installed.

The renderer consumes stable `LMTerrainTileID` values from `LMProgressiveTerrainPlanner`. The measured 2 m regional mesh remains resident. Below 250 m, a nested 0.5 m tile adds bounded crater morphology. A 0.125 m landing tile preloads below 60 m and resolves features down to 0.25 m. Each spatial band morphs to the actual rendered parent through its own edge collar, so coincident parent and child boundaries remain identical. Mesh arrays generate off the main actor. Tile generation and cancellation are independent per stable ID, so a speculative neighbor request cannot starve the required under-vehicle tile. Lifecycle logs record vertex count and generation time. This allows the RealityKit implementation to evolve toward streamed real-data tiles, Metal tessellation, or another renderer without changing the terrain truth model.

`LMProgressiveTerrainSurfaceSampler` is the single surface evaluator for mesh generation, cockpit presentation, and descent-engine dust. The preloaded landing band contributes to the cockpit datum gradually from 40 m to 25 m and is exact at touchdown. Flight and contact still use measured LROC interpolation only; visual alignment cannot turn synthesized relief into an unvalidated landing aid or hazard.

Source-backed terrain uses one mission-oriented directional light at 10.77 degrees elevation, exposed at 25,000 RealityKit lux to retain low-Sun relief without clipping the surface against a black immersive sky. The provisional surface owns its own fallback light so loading the real terrain removes both fallback objects atomically. A restrained texture-derived exposure floor prevents fully shadowed texels from quantizing to black while the PBR term supplies the dominant directional relief.

Both measured and progressive mesh builders emit counter-clockwise upward-facing triangles whose geometric normals agree with their supplied vertex normals. RealityKit keeps normal back-face culling enabled; winding regressions must fail tests rather than being hidden with a two-sided material.

Near-term data path:

1. Keep the current 2 m LROC NAC DTM as the authoritative near-field geometry.
2. Use the photometrically normalized WAC 643 nm mosaic for broad reflectance
   and the two registered 0.5 m NAC orthorectified observations for bounded
   near-field high-frequency contrast. Do not claim the NAC residual as
   absolute albedo without an additional calibration artifact.
3. Add a higher-resolution measured DTM where one is available and record its hash, projection, datum, extent, and post spacing.
4. Use deterministic procedural residual only below the finest measured scale.
5. Validate seams, vertical datum, touchdown contact, memory, frame time, and stereo comfort on Vision Pro.

## LPD source basis and open calibration gate

NASA TN D-6846 describes the dual-pane aiming method, the computer-derived look angle relative to the LM forward body axis, and Apollo 11 redesignation increments of 0.5 degrees in-plane and 2 degrees cross-range. Its window figure and the Apollo-era grid detail show a 0 through 60 degree elevation scale and plus/minus 10 degree horizontal scales.

Primary sources:

- https://www.nasa.gov/wp-content/uploads/static/history/alsj/nasa-tnd-6846pt.1.pdf
- https://ntrs.nasa.gov/citations/19700026504
- https://www.nasa.gov/wp-content/uploads/static/history/alsj/a11/a11.landing.html
- https://www.nasa.gov/wp-content/uploads/static/history/alsj/LM10HandbookVol1.pdf

The design eye and window plane are now reconstructed from Grumman course 30915 figures T30915-30, T30915-38, and T30915-39 together with the 25 by 28 by 24 inch pane in NASA TN D-7439. `CommanderWindowCalibration.md` records the coordinate mapping, figure readings, hashes, reconstruction, and artist tolerances. The inter-pane separation and plotted corner readings remain explicit measurement gates until a dimensioned production drawing or calibrated artifact survey supersedes them, followed by on-head collimation validation.
