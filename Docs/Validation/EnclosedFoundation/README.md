# Enclosed foundation acceptance

Accepted as a provisional, extensible interior foundation. Final tested LM source `3d34dcfd718ae410f6c5b68d5525c93ef9d01319`, LMKit `b870a9b112797d3ea627c663df2684c97f9cc2a3`, AGC/LMCore `b3f15533db335ee882dc07401790c93010809e8f`. **47 tests in 8 suites pass, zero failed/skipped.**

[Final gallery](Final3d34dcf/index.html), [review and limitations](Final3d34dcf/REVIEW.md), [exact run/binary/capture provenance](Final3d34dcf/run.json), [test summary](Final3d34dcf/test-summary.json).

The final eight post-test screenshots show five planning views plus normal/training/forced-fallback front views. Planning text now renders and stays hidden in normal/training modes. Imported physical LPD replaces procedural marks and suppresses the projected digital pointer. Working DSKY/FDAI/ACA remain. No physical headset, gaze/pinch or ornament interaction acceptance is claimed.

Earlier source LM315124e/LMKitd1b0bb5 passed46tests but actual screenshots exposed invisible planning labels. Its separate16-image matrix is retained in Baseline315124e, including failures. Native inspection found66retained text meshes; the fix derives a shipping USD with only PlanningLabels.visibility changed from invisible to inherited, while app startup explicitly hides the group. Do not relabel baseline images as final dependency evidence.

These directories preserve review reports, native screenshots, launch arguments, test-summary/discovery exports and source/binary manifests. The original full FILES-SHA256 manifests also list raw logs and xcresult files not duplicated here. Complete frozen evidence remains at:

- `/private/tmp/lm-enclosed-validation-315124e-evidence.tar.gz`, SHA256 `60754b90392e40a60cf6973c4977277f1eb85ce3a6872de507fd7894cacfe56a`.
- `/private/tmp/lm-enclosed-label-validation-3d34dcf-evidence.tar.gz`, SHA256 `fcb1ad2ebb3761a9f399c80c274b7d158a1d53053bc70be6d590896cf96617ae`.

Simulator shutdown confirmed after final capture. Existing limits remain: dark panels/low-contrast labels, bright smooth ceiling, provisional instrument seating/protrusion, sparse equipment and unqualified glazing optics. Original authoring evidence and combined geometry review are in LMKit.
