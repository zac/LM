# Scoped cabin readability candidate

Base: LM `f9d77ea3a0b1c83dfafedd4768e579a5c24e8e08`. Runtime-only candidate; LMKit exports, mission-light configuration, terrain calibration and physical transforms are unchanged.

Structural Cabin, CommanderPanels and inventory panel surfaces retain authored base colors/textures and metalness. Their PBR roughness is at least 0.9 and specular scale at most 0.08, reducing harsh highlights. Windows/LPD and glazing are excluded. FDAI ball artwork retains its authored texture with a PBR emissive floor of 0.20; selected fixed indices retain their colors with a 0.35 floor. These are app readability treatments, not a reconstruction of instrument power or historical illumination. DSKY's existing presentation is unchanged. No global unlit conversion or new light is introduced.

Runtime `slotOccupancy` records coverage, component IDs and an optional qualification independently of authoring metadata. Successful installation replaces the stale planning text in the same label frame, with a 100 mm planning-only text standoff to clear raised equipment faces. Partial equipment says `PARTIAL REGION` and `Other equipment pending`; visual breaker hardware retains `Visual hardware only`. Original label entities remain retained but disabled. The whole layer remains independently toggleable and hidden by default. Failed/blocked installs retain original labels and blanks; partial installs retain their backing. Existing duplicate/slot ownership checks are unchanged. `installOccupant` accepts an optional component ID (the pilot installer should pass `Pilot FDAI`). Future complementary partial installation must update metadata only after its own successful validation.

Validation so far: Swift parser and whitespace checks pass. A compiled macOS RealityKit headless check passes authored color/metalness/transform preservation, structural reflectance bounds, absence of added structural emission, PBR face fill and multi-component partial caveat. No simulator was used in this lane. Visual acceptance remains pending combined pilot/readability simulator review; these values are a candidate, not an assertion that headset glare/readability is resolved.

Selected app tests for combined validation:

- `LMCockpitReadabilityTests` (three material/metadata tests).
- `LMCommanderStationAssemblyTests` (including failed/blocked install metadata and partial planning replacement).
- `LMInstrumentIntegrationTests/importedFDAINativeHierarchyKeepsFixedStructureStill` (authored texture retained, moving/fixed hierarchy, unbound indicators).
- `LMCommanderLandingInstrumentTests` for optional overlays and existing landing instruments.

Compare normal CDR/front and planning views against `Docs/Validation/CommanderInstruments/Final`; preserve the same camera/state and mission-light startup. Confirm FDAI indices/ball, non-glowing cabin structures, unchanged windows, and partial-region labels. Parent coordinator owns combined validation and publication.
