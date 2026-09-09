# Prepared Apollo landing terrain

Apollo cockpit entry loads the cabin, exterior LM, base terrain meshes and textures, rock field, and contact surface before starting the selected live checkpoint. The default remains the two-minute P64 checkpoint. A readiness gate also prevents physics from advancing during loading if another control starts the session early. Loading failure does not start the descent.

The demo now holds the three existing non-overlapping terrain bands resident. Near-field geometry has 2 m posts across 2,048 m; medium and far bands have nested holes and parent morphs. Apollo cockpit no longer requests progressive overlays, detail texture preparation, or moving contact-patch rebuilds during flight. Explorer/global-site rendering retains its existing behavior. This deliberately trades sub-meter procedural detail for a stable demo; it is not a repair of the general progressive renderer.

Contact uses the complete near-field rendered vertex grid, including perimeter morphs, with the renderer's triangle diagonal and the existing Eagle datum/alignment. Outside the grid it retains the existing measured-height fallback. This is a static terrain preload, not a scripted landing outcome. The prior 120-second headless timing was measured against LMCore's default surface; timing and outcome on this rendered surface still require a live check.

## Evidence and limits

Code inspection found that Apollo progressive entities were added over the still-visible base near-field entity, while old/new progressive generations could also overlap during replacement. These are plausible causes of the screenshot's doubled-looking surface/shadows. The provisional sun is removed with its owning terrain on publication; the loaded world has one shadow-casting mission sun and an earthshine light with shadows disabled and zero intensity. No additional light was removed because no duplicate shadow-casting light was established by the inspected path.

The previous start sequence launched descent before awaiting cabin/terrain loading. Progressive requests created concurrent tile jobs, with synchronous main-actor mesh realization on completion, and introduced finer geometry below 60 m. This change removes those jobs from the Apollo cockpit demo. There is no runtime frame trace establishing that these were the only sources of hitches; initial renderer/GPU warmup and other work can still cost frames.

## Validation

- visionOS Simulator-targeted build passed in an isolated checkout using the Xcode build wrapper; no app installation, launch, or simulator control.
- `python3 Docs/LandingPreload/ValidateContact.py`: eight assertions passed against the production contact-sampler implementation, compiled with interface stubs. Checks cover corners, both triangles of a non-planar quad, their seam, and fallback datum. This is an interpolation regression check, not a simulation test.
- Final source hashes and build result are recorded in `validation.json`.

User-owned Xcode project/scheme edits, AGC, LMKit, and the canonical LM checkout were not changed. On-device visual and frame-time acceptance remains outstanding.
