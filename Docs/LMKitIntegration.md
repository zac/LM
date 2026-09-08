# LMKit integration

LMKit is the model/resource library; AGC owns computer behavior, LMCore owns vehicle simulation, and LM owns presentation, input and state binding. No simulation code moved in this change.

Validated LMKit commit: `d8e35fa3ec8dc400cbb2762c24953022b07e8ebb`. The Xcode project uses `../LMKit` as a local package, like `../AGC`; this is a checkout requirement, not an enforced remote revision pin. Clone both beside LM. For a Codex worktree, provide sibling links to the intended dependency checkouts and verify their exact commits before building. This task used canonical checkouts under `/Users/zac/Projects/personal/lm/` through untracked sibling symlinks.

`LunarModuleModel` and `LMCommanderStationScene` now load `LMKitAssets.legacySceneURL`; `MainMenuView` uses `LMKitAssets.lunarModuleURL`, replacing a previously unmatched asset name. The wrapper and its relative USDZ reference are unchanged bytes. Physics proxy, RCS names, DPS bell, scale and app registration remain unchanged. RealityKitContent continues to own remaining sky, FDAI and scene assets.

The accepted DSKY is bundled at `LMKitAssets.dskyURL`, with source and previews in LMKit's component directory. It is not yet mounted or connected to live AGC inputs/output in LM. Continue using the current procedural cockpit until its binder deliberately replaces that geometry. Rear housing fit and Vision Pro material/interaction checks remain open.

Validation: LMKit's four tests passed, checking hydrated resources, shipping DSKY equality to its authoring export, actual RealityKit legacy scene nodes, and all nineteen direct-child DSKY keys. LM built for generic visionOS Simulator using the xcodebuild skill runner; no simulator launch or headset test is claimed. DSKY worker validation is retained separately in its imported handoff.

Future component deliveries include exact commit, portable source and output assets, evidence, validation and known limitations. Coordinator imports/reviews them in LMKit, updates packaged resources, tests, then advances the LM dependency checkout. Do not silently repurpose LMCore for visual authoring.
