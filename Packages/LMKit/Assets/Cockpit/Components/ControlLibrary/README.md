# ControlLibrary

Six reusable representative LM control families. These are parameterized visual/mechanical authoring assets, **not certified LM-5 hardware or simulation components**. Source-backed mechanism classes coexist with provisional physical dimensions. `HANDOFF.md` defines the proposed integration interface and unresolved accuracy work.

- `MaintainedToggle.usdz`: maintained three-position wedge toggle.
- `MomentaryToggle.usdz`: centered spring-return three-position toggle; spring semantics in metadata only.
- `GuardedSwitch.usdz`: maintained two-position toggle with separately hinged provisional protective cage.
- `RotarySelector.usdz`: circular-skirt pointer selector, four illustrative detents spaced 30°.
- `CircuitBreaker.usdz`: push/pull black knob and aluminum open-state band.
- `Talkback.usdz`: independently addressable gray and barber-pole indication surfaces.

`ControlLibrary.blend` contains all editable geometry on a **preview-only inspection board**. Each exported family instead has an identity mounting root, with no board, camera, sample placards, lights or simulation wiring. Procedural mesh construction and constant materials have no external texture dependencies. `parameters.json` exposes control travel, mounting proposals and selected shape dimensions; `build.py` contains reusable primitive/material/assembly construction. The full set of dimensions remains inspectable in that script; this is not a complete catalog configurator.

Run from this directory, with Blender 5.2.1 and its bundled USD Python bindings:

```sh
blender -b --factory-startup --python-exit-code 1 --python build.py
blender -b --factory-startup --python-exit-code 1 --python validate.py
xcrun swiftc -module-cache-path /tmp/control-library-module-cache -parse-as-library validate_native.swift -o /tmp/control-library-native
/tmp/control-library-native "$PWD"
```

Blender and RealityKit may require normal macOS process permissions to initialize graphics services. All images use fast Workbench rendering; there is no heavy render or bake. The motion image is a pose demonstration, not recorded flight state or live animation. The neutral source file is saved before those temporary poses are applied.

Do not derive panel apertures or manufacturing dimensions from the model without coordinator acceptance and better drawings. Names must not be interpreted as AGC/LMCore bindings.
