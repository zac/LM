# LM and Moon

Native visionOS apps sharing a lunar terrain engine. LM provides the live AGC
landing simulation and cockpit; Moon provides the standalone LunarMap Explorer.

## Check out the dependencies

Use sibling directories named `AGC` and `LM`:

```sh
git clone https://github.com/zac/AGC.git
git clone https://github.com/zac/LM.git
```

Install Git LFS and hydrate the assets with `git lfs pull` in LM.
Open `LM/LM.xcodeproj`, then select the shared **LM** or **Moon** scheme.
The project resolves AGC/LMCore from `../AGC`, cockpit assets from `Packages/LMKit`,
and LunarMap/LunarMapExplorer from `Packages/LunarMap`. These are local package
paths, not enforced remote revision pins. Use the exact dependency revisions
in [the integration report](Docs/MainIntegration.md) to reproduce its checks.

LMKit's models, authoring tools, evidence and resource APIs now live in this
repository. The internal package keeps the asset bundle and imports stable;
no separate LMKit checkout is required. See
[the consolidation report](Docs/LMKitConsolidation.md) for imported history,
byte-identity checks and the authoring workflow.

## Tests and acceptance

Run AGC tests from `../AGC` and asset tests from `Packages/LMKit` with `swift test`.
Run LM's app-hosted tests using the shared LM scheme. Run LunarMap tests using
`LunarMap-Package` from `Packages/LunarMap`, targeting a visionOS Simulator.
Moon and LM share the engine's resources and capture arguments; capture tools
accept `LUNAR_BUNDLE_ID=io.positron.Moon` for the Moon app.

[Main integration](Docs/MainIntegration.md) records the checks actually run,
known failures, and deferred device/visual/performance qualification.
[LunarMap package work](Docs/LunarMapPackage.md) and
[the controlling terrain plan](Docs/LandAnywhereMoonPlan.md) retain the
terrain contracts. Simulator results do not establish Vision Pro acceptance.
