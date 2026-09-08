# Articulated ACA integration

Worker task `01a082b1-da15-7642-9195-0a71036a38be`, branch `codex/aca-integration`, worktree `/Users/zac/.codex/worktrees/313f/LM`. Clean detached baseline verified at `9016960683efabb491dfed16f10ea3ef90196d01` before branch creation. No integration/main merge or push.

Pinned dependencies are hydrated archives of LMKit `3ad1a999ff17aea859eaea5750f1c65e66fad673` and AGC/LMCore `b3f15533db335ee882dc07401790c93010809e8f`, under `/tmp/lm-aca-deps`, with untracked sibling symlinks. Archive resources were already hydrated; zero LFS pointer replacements were needed. Shared dependency checkouts, assets and simulation implementations were not modified.

## Runtime and identity

`LMImportedACA` loads the packaged ACA USDZ and interface manifest. It validates unique semantic nodes, parentage, neutral origins, unit scale, neutral rotations and axis contract before installation. Normal startup installs the imported visual; missing/invalid assets leave the functional procedural fallback. Installation is synchronous, detached and idempotent. Success removes the procedural handle children and its collider/input target; the existing pedestal stays. A single grip-sized proxy follows ACA_Pitch and all upstream pivots. The gesture targets its marker component and verifies ancestry, including child entities. PTT is retained as neutral visual geometry only; no trigger/friction behavior is added.

The stable `acaHandle` container, DSKY/FDAI identities, optical datum and optional assembly behavior remain intact. Optional assembly retains the same pedestal and ACA registration. Imported fixed housing stays outside the moving hierarchy. The old single-quaternion implementation remains solely for functional fallback.

## Explicit input and visual conversion

Cabin coordinates are +X right, +Y up, -Z forward. Hand displacement is now measured in the cabin parent, preserving the established mapping under root/observer rotations: pitch = clamp(-dz/.055), yaw = clamp(dy/.055), roll = clamp(dx/.055). These remain normalized simulation commands, not inferred vehicle axes.

| Positive command | Existing AGC path | Imported visual |
|---|---|---|
| Pitch (hand forward) | positive pitch counts, channel 0166 | ACA_Pitch local +X |
| Yaw (hand upward) | positive yaw counts, channel 0167 | ACA_Yaw local +Y |
| Roll (hand right) | positive roll counts, channel 0170 | ACA_Roll local -Z |

The signs preserve the existing LM visual convention. In particular, +X pitch moves the modeled top crewward even though forward hand displacement requests positive pitch. This pre-existing gesture/visual relationship is explicit; it is not a claim of one-to-one physical grip tracking. Nested roll→yaw→pitch changes combined visual kinematics to match the imported contract; no simulation-axis reorder occurs. Parent-local neutral translations remain .061/.062/.077 m. The existing app ±11° proportional visual range is used, not the asset's illustrative ±8° demo or a new mechanical-stop claim. LM counts remain 8% dead zone, nominal ±42 and combined ±57 clamp; negative values retain AGC ones'-complement encoding. Nonfinite input is neutralized.

Direct gestures acquire a session generation; release, cancellation, deactivation, pause and stop invalidate it. Updates require the same generation and an active, running, unpaused session. Forced release retains the gesture's old token until completion so late callbacks cannot reacquire after a restart. View disappearance blocks further callbacks; gesture state reset handles cancellation. Session inputs and rendered pivots return to neutral. Programmatic tests establish these state transitions; OS pinch/cancellation dispatch remains a headset acceptance gate.

## Provisional registration and envelope

The existing pedestal center is ACA pivot minus 40 mm Y, with 55 mm height. Its top is pivot Y minus 12.5 mm. Seat the imported housing-bottom origin there: local `(0,-.0125,0)` below the unchanged handle container, or cabin `(-.49,.9075,-.37)` m. Root rotation is identity and scale is one. No geometry is resized to fit. This aligns two provisional surfaces; the ACA bottom center is explicitly **not** a verified mounting datum. No adapter, bolt pattern or hidden mating interface is invented.

Native RealityKit neutral bounds are 101.6 × 255.5 × 169.9 mm. A 729-pose grid across every axis at 2.75° spacing through ±11° gives an AABB of 137.052 × 262.537 × 169.9 mm. Cabin bounds are approximately `[-.558526,.9075,-.45495]` to `[-.421474,1.170037,-.28505]`. The sampled envelope fits the pedestal's 180 × 200 mm plan footprint, with housing bottom on its top. This is sampled visual bounds, not continuous collision, clearance, hand reach or certified installation proof. Source, exact numbers and reproduction script are in `Docs/Validation/ACA/`.

## TTCA audit — no binding

At the pinned revisions, LM `PoweredDescentSession` exposes `setACA`, `setRHC`, `setROD`, `attitudeMode` and corresponding release methods. There is no typed TTCA, JETS/THROTTLE selector, manual-throttle fraction, friction, or translational-hand-controller state/API. DES RATE is the channel-016 increment/decrement switch, not a throttle axis.

AGC/LMCore APIs available:

- `LMFrameInput` (`Sources/LMCore/LMFrameInput.swift`) carries radar, powered-descent panel, rotational-hand-controller, descent-rate and raw channel inputs. `LMPoweredDescentPanelState` exposes only attitude mode; its held channel-030 word includes automatic-throttle state. No typed TTCA/manual-throttle/translation payload exists.
- `LMSimulationRuntime.setRotationalHandControllerInput`, `setDescentRateControlInput(descendPlus:descendMinus:)`, `enqueueInput(s)` and `AGCRuntime.setRotationalHandControllerInput` feed the existing hardware path. `AGCRotationalHandControllerInput.signedCounts` encodes pitch/yaw/roll; AGC writes 0166/0167/0170 without reordering. Raw channel enqueue and erasable writes are low-level capabilities, not an established TTCA binding.
- `LMDPSThrottleMap.thrustNewtons(pulsePosition:engineOn:)` converts computer throttle pulse position. Internal `LMDPSThrottleState.advance(thrustRegister:driveActive:deltaTime:)` is driven by AGC THRUST/channel-014 in `LMSimulationRuntime.stepExact`. This is an AGC-output plant model, not a public manual lever control. It retains its own sourced 10%–94% model; no asset lever angle or differing handbook 10%–92.5% range is substituted.
- Existing `LMDynamics.specificForceBody` sums DPS thrust and configured RCS jet forces, so translational dynamics exist. Missing controller semantics do not imply missing all translation dynamics. `enableLandingDAP` also changes SNUFFBIT according to current attitude-mode policy; bypassing it with guessed raw inputs would not establish safe TTCA behavior.

Future TTCA work needs an accepted station/revision contract for selector gating, shared vertical jets/throttle semantics, lateral/axial inputs, channel mapping, dead zones/detents, calibrated manual-throttle handoff and interaction with held panel words/DAP policy, plus coordinator scope approval. No new dynamics, duplicate simulation, TTCA installation or guessed axis mapping was implemented.

## Validation

Final source, test counts, xcresult, captures and remaining placement/device gates are recorded in `Docs/Validation/ACA/README.md` and its manifests. The full unrelated suite was not run. No real Vision Pro execution or physical pinch acceptance is claimed.
