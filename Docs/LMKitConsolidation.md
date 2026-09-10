# LMKit consolidation into LM

The owner requested moving LMKit's hackathon-separated work into the main LM
repository. The implementation keeps `LMKit` as an internal resource package
at `Packages/LMKit`; LM now needs only the separate AGC checkout.
The standalone Moon app continues to depend only on LunarMap/LunarMapExplorer.

## Imported history and ownership

- LM input: `558640eb9b878b67a0ca0fa5a785319142d2b026`.
- LMKit input: `5287dfda4c5b8ba88882dc27f4dd9b9235e161e7`.
- Import merge: `750aa44a3f8412cbe134396fc297fa6b0de43e59`.
- Original LMKit tree and imported subtree are identical:
  `a9904f1a8f51da1c914bec2776e3d0b2de823904`.
- All 876 imported tracked files are byte-identical before the subsequent
  README/AGENTS/provenance documentation changes. The original 82-commit
  history is retained as a merge parent, without squash or rewriting.

Models, Blender/USD authoring files, scripts, tests, evidence, handoffs and
resource APIs are colocated. Nested `.gitattributes` retains Git LFS rules.
The original standalone repo and all its branches remain intact; it is not
archived or deleted remotely. Future asset changes belong in this repository.
Historical handoffs retain their original paths and commit IDs as evidence;
current workflow instructions are in the package README and AGENTS.md.

The package's source, manifest, tests, tools and runtime resources are otherwise
unchanged. Xcode's local dependency changes from `../LMKit` to `Packages/LMKit`.
The module name, imports and `LMKit_LMKit.bundle` name remain stable. This
avoids resource-loading or cockpit-binding changes during repository migration.
AGC/LMCore still own simulation. Imported `.github` content, if any, is
historical package content; nesting it does not install root LM CI workflows.

## Evidence and validation

Evidence root: `/tmp/LM-LMKit-Consolidation-2026-09-09/`.

- `import-audit.json` / `lmkit-source-hashes.json`: 876 identical files; zero
  mismatches. Runtime assets comprise 67 files / 9,817,185 bytes. Authoring
  resources and source evidence are not added to the app resource bundle.
- `lfs-fsck.log`: imported LFS object integrity passes.
- `lmkit-tests.log`: all 13 native macOS RealityKit package tests pass in
  3.465 s from the new package directory, including the parameterized resource
  load cases and native independent-pivot checks.
- `python3 Tools/sync_dsky.py` succeeds from `Packages/LMKit`; a subsequent
  check confirms all 67 shipping resources remain byte-identical.

- `release-build.log`: ordinary LM Release Simulator build succeeds with fresh
  DerivedData; package resolution names the internal `Packages/LMKit` path.
  Xcode 26.6 / visionOS 26.5 Simulator
  `8F38C0E7-6366-4DAC-9372-DCF6F9151DCB`.
- Release executable SHA-256:
  `de90d83add4910d10deeb762280b41509398781902eb637682811dc9b9cbd740`.
  App bundle: 478,036,638 bytes.
- `shipping-bundle-audit.json`: all 72 files in the compiled
  `LMKit_LMKit.bundle` (including generated metadata) match the frozen
  pre-migration Release bundle byte-for-byte. No runtime asset changed.
- `cockpit-tests.log` / `CockpitTests.xcresult`: 39 app-hosted tests in five
  suites pass in 44.494 s: instrument integration, commander assembly, pilot
  FDAI, systems integration, and cockpit console enclosure. These load the
  internal package and verify actual asset bindings. Debug configuration is
  used for the existing app-hosted test hooks.

This is bounded migration validation: resource identity, an ordinary Release
build, native asset tests and app-hosted integration tests. No new screenshot,
full flight, performance benchmark or physical-device test was run. The
existing FDAI repair evidence remains in `Docs/FDAIContrastRepair.md`; this
migration does not claim a further visual or flight-quality improvement.

## Ongoing workflow

Open `LM.xcodeproj` as usual. No sibling LMKit repo is required. Run authoring
and resource-sync commands from `Packages/LMKit`; use `swift test -c release`
there for native asset tests. Preserve component interfaces, source evidence
and independently addressable parts. Refresh accepted exports with the
appropriate package `Tools/sync_*.py`, then run package and cockpit integration
tests. Continue using Git LFS for Blender and USD assets.

This consolidation does not close the existing P64 redesignation exemption,
Moon performance/visual qualification, parked D/F work, or physical Vision Pro
readability, input, stereo, thermal and long-session gates. No renderer,
terrain/contact data, attitude logic or guidance behavior changes are intended.
