# Imported cabin shadow correction

The imported foundation disabled every model's dynamic shadow casting, replacing a procedural shell that explicitly cast shadows. Direct mission sunlight therefore illuminated interior surfaces through the enclosure. Native overhead A/B captures confirmed that enabling only `/Cabin/Shell` removed the broad white ceiling; disabling the active post-terrain-swap sun independently removed the saturation. Authored/runtime liner tint remained approximately (0.58, 0.59, 0.55), nonmetallic and nonemissive.

Restoring casting exposed coarse artifacts from the camera-fitted 45 m shadow projection. Lower depth bias increased acne; higher bias and front culling did not resolve it. Fixed light-space 8 m diagnostic coverage produced clean broad shading and localized sunlight without changing illuminance, orientation, or materials.

## Runtime policy

- The imported pressure shell casts shadows. Layered panel faces, glazing, controls and planning text retain their existing noncasting policy.
- Fit full square light-space XY coverage around locally enabled shell and exterior lander mesh bounds, with 0.5 m margin. Disabled legacy ascent geometry is excluded. Bounds work before anchoring; `visualBounds(excludeInactive:)` incorrectly returns empty infinite bounds at that stage.
- Above 45 m altitude, fit caster depth plus 45 m downstream receiver coverage. Distant ground is omitted because the previous local map did not reach it.
- At or below 45 m, include positive light-ray intersections with the current rendered ground reference plane and a 5 m downward relief allowance. This is a conservative shadow envelope, never a simulation/collision surface. Reject grazing/invalid fits and spans/depths beyond supported limits (64 m XY, 512 m depth), restoring the existing automatic projection and original light position.
- Update after Apollo/global world transforms, initial lighting setup, enclosure replacement and exterior installation. Sun translation anchors the fixed shadow map; intensity and orientation are unchanged. Cached corners preserve active geometry ownership.
- Coverage is local to cockpit and lander. Terrain/rock shadows outside that footprint are not represented; this is not a claim of unchanged distant terrain shadows.

Apple documents the light's forward direction as -Z and position-independent directional illumination, and `orthographicScale` as the fixed projection width/height: [DirectionalLightComponent](https://developer.apple.com/documentation/realitykit/directionallightcomponent), [ShadowProjectionType](https://developer.apple.com/documentation/realitykit/directionallightcomponent/shadow/shadowprojectiontype). Installed Xcode 26.6 provides automatic/fixed projections, bias and culling; no public shadow-map resolution/cascade control was used.

## Planning annotation

`Panel5__Translation` now says “Translation controls pending” in the optional planning layer. It no longer falsely claims DES RATE is unmodeled; the working switch belongs to Engine. This text correction does not claim occupancy, hide the blank, or move hardware.

## Validation and evidence

The first focused run exposed infinite prepublication bounds; explicit enabled-mesh traversal fixed it. The corrected focused run passed 20 tests across fit math, rigid-frame invariance, invalid/horizon/oversized fallback, source-position restoration/recovery, startup light continuity, shell casting, planning text, and assembly regressions.

Diagnostic images and exact source snapshots are under `/private/tmp/lm-systems-validation/evidence/lighting-diagnostics*`. They were built from explicitly uncommitted diagnostic variants of 82a21da; they are not part of the earlier 90-test immutable acceptance. Temporary sun-off/culling/projection tuning flags were removed. A DEBUG-only paused validation launch option and read-only `shadow-validation.json` report support reproducible final evidence. The `exterior` inspection camera is explicitly outside the enclosed cabin.

Full regression and final fitted-policy cockpit/ground screenshots are pending at this source commit; the coordinator owns durable final evidence and publication. LMKit d8c24dd and AGC b3f1553 remain unchanged.
