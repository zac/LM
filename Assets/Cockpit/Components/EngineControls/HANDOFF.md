# Engine controls and lunar contact

Editable `EngineControls.blend` and reproducible `build.py` produce `EngineButtons.usdz` and `LunarContact.usdz`. These are source-informed neutral hardware, with provisional dimensions except the approximate one-inch contact-light size. No simulator implementation or engine input binding is included.

## Installation

Use `interface.json` (`lmkit.engine-controls.v1`) and `mounting-matrices.json`. Export basis is meters, Y-up, local +Z toward crew. Both roots are identity transforms. Install EngineButtons_Mount as an identity child of existing Panel5__Engine. Keep the entire accepted DescentRate_Mount and its support/backing: the hollow new guard is fitted around it. Do not replace the slot or disable peer geometry. No added blanket backing, no engine hardware in Panel1, and no new inventory slot.

Reuse LunarContact_Mount twice: commander directly beneath Panel1 at local (0.041,0.099,0.0003); pilot beneath Panel3__Lighting at local (0.078,0.034,0.0003). These source-informed poses are metric estimates. Commander occupies the unreserved gap beside the cross-pointer and above FDAI; no existing slot replacement is authorized. Pilot is a partial lighting-region overlay; keep the reservation. Lamp housings insert behind panel planes intentionally; forward bezel/lens/title remain visible. Both assets retain independent roots for future source-driven remounting. No master alarm, engine arm, abort button or other panel features are owned here.

## Independent parts and interaction

EngineButtons__StartActuator, EngineButtons__StopActuator and EngineButtons__StopResetLatch are direct children. The StartLightFace and StopLightFace meshes belong to their corresponding actuator. Neutral positions are recorded by validation.json. Provisional plunger travel is negative local Z, 2 mm, purely a geometry affordance; it is not an approved physical latch/return simulation. Keep buttons inert until a separately specified authoritative crew engine interface exists. Never use session.start, session.stop, PRO or arbitrary channel011 injection.

LunarContact__LightFace is independently addressable from the blue lens and bezel. The coordinator may show a qualified observation of `state.landingGear?.isProbeContact`; this is a modeled probe-contact flag, not complete electrical lamp behavior. An unavailable optional state is unknown. Do not substitute pad contact, terminal outcome or engine-off. Power, lamp test, historical reset circuit and photometry remain unmodeled. The historic face is not relabeled with training terminology; qualification belongs outside the hardware.

## Evidence and uncertainty

`evidence/source-manifest.json` preserves source URLs, original page mapping and SHA256. The original News Reference ad013 source is retained in PanelInventory/evidence; local crops are derived illustrations, not dimensional drawings.

- ad013 engine detail shows lower circular START, upper STOP assembly and guard, with the accepted DES RATE at the guard's left side. The model follows that arrangement with a stepped, striped protective guard. Exact shell construction, latch kinematics, travel, button/lamp dimensions and stripe spacing are provisional. The accepted DES RATE support is unchanged.
- NASA TN D-6722 printed8 and10 (original PDF12,14) identifies START as momentary and describes a two-action STOP reset protection. Later LM10 AOH printed3-81/3-87 (PDF675/681) describes retained START and reset by pressing STOP again. This conflict prevents claiming a mission-accurate state machine. The visible reset bridge is independently editable, not a resolved mechanism.
- NASA TN D-7919 printed17 (original PDF25) specifies two round contact lights about one inch across and blue lenses. The asset uses 26 mm outer bezel diameter and a dark blue neutral face. The AOH table's red indication wording conflicts with the explicit lens report; emitted color/intensity is not photometrically qualified. Do not transfer the report's probe-length wording into the vehicle model.
- Mission baseline is Apollo 11 intent with explicitly later/generic supporting sources. Neither this package nor its neutral geometry is an exact LM-5 certification.

## Validation

`validate.py` checks native USD roots/units, separate parts, no authored invisibility, ARKit compliance, three DES RATE positions and 27 sampled ACA poses using actual exported mesh surface crossings. Contact faces are checked against current neighboring slot rectangles; this is reservation clearance, not a full fitted-component collision audit. `validate_native.swift` loads both USDZs in macOS RealityKit, verifies independent actuator movement/light material access and restoration. `validation.json` and `native-validation.json` record results. No continuous swept-volume, hand clearance, headset interaction or Vision Pro validation has been performed. The main coordinator owns packaged-resource integration.

Rebuild with Blender 5.2.1 `-b --python build.py`, then `-b --python validate.py`. The build imports ControlLibrary helpers and requires that peer source unchanged. Native: `swiftc -parse-as-library validate_native.swift -o /tmp/validate-engine-native`, then run with this directory as argument. Review images use low-cost Workbench rendering and do not represent final illuminated appearance.
