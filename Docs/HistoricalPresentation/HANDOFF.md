# Historical cockpit presentation

Base: LM `11f7335b73884ce8dd8ebe33583f666e2b329c72`. Dependencies remain LMKit `86aa71b4b9ed203f11e8b572e23da2b0285a0ad8`, AGC/LMCore `b3f15533db335ee882dc07401790c93010809e8f`. No assembly replacement or optical/flight-model changes are included.

## Presentation policy

Normal entry hides the entire event cue ornament, the yellow called-angle marker, the numeric LPD app hint, the eye diagnostic, and diagnostic pane colors. The actual DSKY still receives unmodified AGC numbers. The app hint directs the user to DSKY N64 while retaining PRO/redesignation guidance. App status, fallback controls, validation checklist, mission window, recenter, exit, and audio controls remain available.

Training aids are opt-in. Event cues and angle text are labeled Training. The eye diagnostic requires a second explicit choice; it enables the previous synthetic pane colors. Turning training off clears the eye choice, so turning it back on does not silently restore that diagnostic. Recenter and restart do not assign presentation state; a newly entered cockpit starts historical again. Audio event scheduling and simulation/controller lifecycles are unchanged.

DEBUG capture arguments `--cockpit-training-overlays` and `--cockpit-eye-alignment` reproduce opt-in choices; the eye flag alone cannot enable training. Normal production initialization ignores these arguments.

## Approximate physical appearance

The normal generated marks now use one warm, nonemissive material on both panes. This follows the actual window photo on slide 38 of the [NASA-hosted Eppler Apollo Lunar Landing Experience Report](https://www.nasa.gov/wp-content/uploads/2023/06/eppler-slides-apollo-lunar-landing-experience-report-20070-r4.pdf). The image shows pale warm marks; mission/vehicle and original photographer are unidentified. RGB (0.72, 0.65, 0.43) and roughness 1 are artistic choices, not measured pigment or photometry. The source's cyan illustration is not glass color evidence.

WindowsLPD evidence commit `849e250` contains `Assets/Cockpit/Components/WindowsLPD/EVIDENCE.md` and `evidence/eppler-slide38.png`; PNG SHA256 `53e32cdfae7ceb8bccfa33633722c57f23c2a504d3ea4ed11301b8659aee351d`. The photo was inspected. This task does not claim the previous geometry is historically calibrated: it lacks the photo-supported 50-degree crossbar and retains oversized baseline lines/numerals and uncertain eye/pane assumptions. New WindowsLPD artwork supplies revised visual marks in the later integration.

## Single owner integration

`LMCommanderStationScene.setLandingPointMarkingOwner(.importedWindows)` disables all 26 generated grids and labels after imported windows successfully install. `.appGenerated` restores them for fallback. References survive assembly reparenting and recentering. Diagnostic material changes never re-enable suppressed marks. Switching to imported ownership immediately hides any existing projected called-angle sphere, and subsequent training updates cannot enable it. Switching back does not resurrect stale marker state. Existing assembly mounting code was not changed.

The coordinator must call the ownership API only after successful imported asset installation and restore app ownership on fallback. Imported windows must provide exactly one CDR inner/outer set and no LMP LPD. Do not enable both representations. The current diagnostic tint affects only generated entities; imported diagnostic presentation requires its own explicitly opt-in material API, not duplicate geometry. The imported artwork is contained photo-inspired geometry, not angular-calibrated targeting. The projected training marker is therefore restricted to the unverified app comparison geometry; reconcile a future optical/layout contract before enabling any imported angle-to-mark correspondence.

## Verification

Focused simulator results and capture hashes accompany this handoff in `evidence.json`. Captures use the pinned baseline assembly, not the forthcoming enclosed assembly. The source-backed appearance is approximate. Physical headset stereo, gaze/pinch, reach, photometry, and performance remain untested here.
