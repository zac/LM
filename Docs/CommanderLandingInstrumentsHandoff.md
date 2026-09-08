# Commander landing instruments runtime

This phase adds source-informed altitude/rate tapes, a later fly-to cross-pointer aid, physical AUTO/ATT HOLD and DES RATE controls, and optional cabin/breaker detail to the enclosed foundation. LMKit's accepted resource snapshot is `1285040`; AGC/LMCore remains `b3f15533db335ee882dc07401790c93010809e8f` with no behavior changes.

## Data and behavior

Altitude uses reconstructed geometric height, not the session's radar slant range. Rate is radial upward-positive in feet/second. Values outside the documented tape intervals or nonfinite values hide the corresponding rows and bring forward the authored unavailable shutter. Each row is placed from the contract's piecewise scale and enabled only while its full glyph fits the aperture; USD-authored hidden visibility is not used.

Cross-pointer input is reconstructed horizontal velocity in the yaw-defined lunar-surface frame. It is limited to landing programs 63–67 and valid flight states/headings. Fixed LO MULT full scale is ±20 ft/s, with saturated travel. Later fly-to convention moves the vertical bar left for rightward velocity and the horizontal bar up for forward velocity. This sign formula is an operational inference from Luminary Memo 171, using Memo 165's later descent frame. It is not Apollo 11/Luminary 099 display output or a simulated landing-radar/AGS channel. Missing data hides both needles. Source qualifications remain in metadata and the optional training ornament; no simulation placard is added to the historical face.

AUTO/ATT HOLD uses the existing session API; OFF remains unsupported and rejected without moving the actuator. Selecting ATT HOLD does not itself guarantee P66. DES RATE preserves the existing held channel-16 input behavior: plus slows descent, minus speeds it. No app repeat timer or new engine logic is introduced. The existing simulation may process a held input each frame; this does not establish historically calibrated repeat timing. Release, cancellation, pause, stop, scene loss and cockpit exit neutralize DES RATE. Generation tokens prevent late drag samples from reacquiring after a forced release. The maintained attitude switch retains its state.

## Assembly and fallbacks

All instrument loads validate detached roots before installation. Partial components preserve their region blank: altitude/rate at Panel1 Range/Thrust with the approved (-.020,0,.008)m offset; cross-pointer at Panel1 CrossPointer; attitude mode at Panel3 Stability; unplacarded side-mounted DES RATE at Panel5 Engine. Translation is untouched. Only the imported duplicate control backing and the successfully replaced procedural control/legend are disabled. Existing DSKY, FDAI and ACA instances remain live. Failed loads retain their existing fallback and do not prevent other instruments loading.

Altitude/rate's taller provisional body and the cross-pointer's rear housing are not mechanically qualified against the backing. Retained blanks lie behind the visible scales; provisional fit limitations are recorded in the LMKit component handoffs. Mounts and unit scale are preserved rather than silently moving controls to conceal these limitations.

InteriorDetails and BreakerBanks are separately validated, noninteractive identity-root overlays. Failure is contained per overlay; all nine mapped breaker panel/slot transforms and ownership are validated before the nine exact placeholders are suppressed. InteriorDetails suppresses none. `--no-interior-details` omits both and preserves their blanks. Normal startup loads valid overlays. Dial markings alone receive a bounded unlit material treatment preserving authored colors/textures; housings, windows and cabin lighting remain authored.

## Validation controls

Existing `--assembly-validation-view=front`, `cdr`, `lmp`, `rear`, `overhead`, `side` and `crew-eye` selectors remain. Added `control-closeup` and `detail-side` are observer cameras inside the cabin, without implicit cutaways. `--cockpit-training-overlays`, `--cockpit-planning-labels`, `--no-interior-details`, and `--procedural-cockpit` allow independent comparison.

Validation is recorded separately below after native execution. Simulator images establish rendered appearance for the selected camera and state; they do not establish headset reach, eye tracking, full optical aperture or mechanical fit.

The serial visionOS 26.5 simulator regression run passed **27 tests, zero failures**, covering real tape row/shutter movement, cross-pointer axes, actuator quaternions/OFF rejection, stale input generations, transactional breaker mappings/rollback, no-details startup, foundation labels/datums, ACA and existing instrument interaction. Evidence: `/private/tmp/lm-commander-instruments-validation/evidence/final-2.xcresult` and `test-summary.json`. An earlier parallel test host was killed before connecting and is not counted as a test result. A subsequent immediate state hydration call after component installation is included in the capture build so already-paused sessions do not await another state emission.
