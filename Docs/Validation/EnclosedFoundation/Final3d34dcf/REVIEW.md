# Final planning-label fix validation

Approved sources: LM `3d34dcfd718ae410f6c5b68d5525c93ef9d01319`, LMKit `b870a9b112797d3ea627c663df2684c97f9cc2a3`, AGC/LMCore `b3f15533db335ee882dc07401790c93010809e8f`. Private hydrated archives; no shared integration-tree or package edits.

The LM runtime source is unchanged from `315124e1c3301d095d21b8fc08cd5b780d42cd1d`; the LM commit adds a drawable-label/toggle test and documentation. The LMKit runtime change is the packaged PanelInventory planning-layer USD visibility from invisible to inherited. Runtime explicitly sets the layer disabled before normal installation and enables it only for opt-in planning. Packaging provenance remains in the pinned package's `Resources/PanelInventory/packaging.json`.

## Visual gate

Preflight front planning screenshot displays actual planning text, including Panel 1 guidance/engine/abort, Panel 2 RCS/ECS, and Panel 3 regions. Preflight front normal hides the labels. The earlier invisible-text failure is resolved in this comparison. Labels remain low-contrast under the accepted provisional lighting, so this is not a typography/photometry qualification.

Final post-test capture review and test results are recorded in `run.json`. Preflight images and binary hashes are separate from the final capture set.

## Retained limits and comparison history

The prior full normal five-view and 16-image matrix belongs to LM315124e with LMKitd1b0bb54, not this final dependency. It is preserved in `lm-enclosed-validation-315124e-evidence.tar.gz`, SHA256 `60754b90392e40a60cf6973c4977277f1eb85ce3a6872de507fd7894cacfe56a`. Its planning images intentionally record the former failure. Do not relabel those as final-pin captures.

The coordinator accepted the normal enclosed foundation with explicit limits: dark panel/instrument lighting; bright, featureless overhead liner; provisional DSKY/FDAI seating gaps and protrusion; unqualified glazing optics. No flush-fit, photorealistic, calibrated-optical, or physical-headset acceptance is claimed. Simulation and live instruments are unchanged.

All captures are unedited native simulator screenshots using explicit DEBUG camera/mode launch flags. These are not gaze/pinch inputs. Earlier AXe inspection of this immersive workflow exposed no child controls; ornament accessibility and button interaction remain unverified. Tests use synthetic adapter and scene calls.


Final combined run: **47 tests in 8 suites passed, 0 failed**, including `planningLayerRetainsTextMeshesAndTogglePreservesAllBlankStates`. Discovery and xcresult are included. The final executable wrapper changed after the test build; the debug dylib stayed identical to preflight. Final captures reinstall and use the post-test binary hashes in `run.json`, keeping preflight evidence separate.

Final eight post-test screenshots reviewed: five planning views (front, CDR, LMP, rear, overhead) all display actual labels. Front normal and training hide planning names; imported LPD marks stay warm without diagnostic tint or a yellow projected sphere. Front forced fallback renders the procedural cabin with DSKY/FDAI/ACA. This resolves the missing-text defect. Existing lighting, fit, optics and interaction limitations above remain.

Dedicated simulator DE0FAD53-2A01-4B96-95D3-3505E6900DA3 was shut down and verified Shutdown; the simulator slot is released. Final capture arguments and SHA256 values are in run.json.
