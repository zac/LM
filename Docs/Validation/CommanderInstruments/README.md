# Commander instruments and interior detail validation

Accepted LMKit runtime package: `1285040`. All five component branches were merged preserving their original history; new packaged assets are byte-identical to the accepted authoring exports. Each runtime resource directory carries a SHA-256 packaging receipt. `Provenance/commander-instruments-acceptance.json` records the deliveries and exact payloads.

The complete native macOS package run passes 13 test functions, including two functions with six parameterized resource cases each. It loads the actual USDZs, verifies component hydration/source byte parity and preserves the earlier DSKY, FDAI, control-library, cabin, window, panel and hand-controller checks. See `package-tests.log`.

Independent final new-component geometry review is in `CombinedGeometry/`. All 15 asset-pair combinations have zero mesh-bounding-box overlaps at their contracted neutral poses. Twenty sampled commander-eye rays find no obstruction by another new component. These tests do not establish full sightlines, moving-hand/controller clearance or native visual readability.

Authoring evidence and per-component review images remain with AltitudeRate, DescentControls, CrossPointer, InteriorDetails and BreakerBanks under `Assets/Cockpit/Components/`.

The consuming LM app owns every live input/display binding, partial-slot installation and optional-overlay rollback. Combined visionOS simulator acceptance is recorded separately in LM; physical Vision Pro remains untested. The original foundation and old LPD calibration limitations remain in force. Instrument housings, source-inspired scale pitch, breaker terraces and cable routes are explicitly provisional.

Consuming LM source `5ec10b8` passes 64 native simulator regression tests with no failures/skips. Startup before/after and final assembly views are preserved in [LM integration evidence](https://github.com/zac/LM/blob/cockpit/integration/Docs/Validation/CommanderInstruments/README.md). The user-reported startup lighting jump is corrected in LM; no model payload changed for that fix.
