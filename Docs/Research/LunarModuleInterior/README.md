# Lunar module interior research

Research date: 2026-09-08. Intended use: build a detailed Blender cabin, export USDZ, and connect its controls to the native Vision Pro application. Research baseline: `89ecb0fe641292640a56e37ddf72587c342a4066`. This worktree is now the `cockpit/integration` coordination checkout. This packet is research only.

See [cockpit coordination](../../CockpitCoordination.md) for branch ownership, worker dispatch and integration gates.

## Recommended target

Confirmed library split: AGC runs the guidance computer; LMCore supplies flight dynamics and vehicle simulation; the native RealityKit application binds input and renders the Blender-authored USDZ. Keep spacecraft motion authoritative in LMCore rather than introducing a second flight-dynamics model in RealityKit physics. The current `PoweredDescentSession` already imports LMCore and uses `LMSimulationRuntime` and `LMSimulationSnapshot`.

Confirmed architecture: use Zac's existing AGC implementation to power the cockpit. The USDZ supplies the modeled controls, displays and moving parts; the native application connects them to the existing AGC and LMCore simulation. DSKY entry, program execution, readouts and computer annunciations must come from that runtime. Do not implement a second verb/noun interpreter or scripted imitation of the computer in the asset layer. Later-mission visual substitutions do not imply changing the running flight software.

The current app already sends physical DSKY input through `PoweredDescentSession.sendDSKYKey` and renders `snapshot.agc.dsky`. Imported asset controls should reuse those paths. Non-AGC systems and the separate abort-guidance DEDA need explicitly identified simulation owners; a visible control should not be assumed to connect to the AGC merely because it is inside the cabin. See the [confirmed integration architecture](blender-usdz-visionos.md).

Build an Apollo 11-led interior. Use Eagle photographs and LM-5 procedures for the recognizable forward stations and operational baseline. Fill gaps using later handbooks and closeout photographs, recording each substitution on the affected panel or component. This permits a coherent, documented cockpit without pretending that mixed evidence proves an exact July 1969 configuration.

The first modeling target should be the commander station, its window and landing-point designator, the center DSKY, and representative adjacent controls. Establish scale, eye position, panel cant, switch depth, legible labels, and live instrument behavior there before repeating components across the cabin. This is a recommended sequence; the research covers the wider interior.

## Read the packet

| Document | What it supplies |
|---|---|
| [Controls and panels](controls-and-panels.md) | Panel map, control families, instrument behavior, exact manual page pointers, mission differences, and state dependencies |
| [Photo reference catalog](photo-reference-catalog.md) | Twelve inspected original images, including Apollo 11 flight/preflight views, later closeouts and diagrams, with provenance and modeling observations |
| [Geometry, materials, and evidence](geometry-materials-and-evidence.md) | Cabin dimensions, crew-eye references, panel angles, lighting, five saved figure renders, and unresolved measurements |
| [Blender, USDZ, and visionOS](blender-usdz-visionos.md) | Current app contract, proposed hierarchy and pivots, materials, control bindings, and on-device validation |
| [Measurements CSV](measurements.csv) | Values with original units, converted units, source/page, applicability and uncertainty |
| [Research backlog](research-backlog.md) | Specific unresolved questions and what evidence would close them |
| [Additional reference assessment](additional-reference-assessment.md) | User-supplied large panel scan, NASA collection overlap, and research prerequisites for modeling |
| [Reference manifest](references/manifest.json) | Local document/figure hashes, original source locations and excerpt mappings |
| [Image manifest](references/images/manifest.json) | Image IDs, dimensions, hashes, working sources and failed retrieval history |

## Findings that affect the build

The cabin is a three-dimensional workstation. Glareshields, canted panels, tiered breaker consoles, armrests, optical instruments and restraints are part of the control interface. NASA's arrangement figure and the preflight photographs show these relationships. Use flat panel drawings as component maps, then reconstruct their installed depth and angle. [NASA crew-station report, figure 2](https://ntrs.nasa.gov/api/citations/19750012347/downloads/19750012347.pdf#page=14)

The window is also an instrument. The project already has a commander-eye datum and two distinct LPD marking layers. Keep them separate in the model. The current provisional pane separation remains an open historical measurement, even if a model passes the app's geometric tolerances. [Existing calibration notes](../../CommanderWindowCalibration.md)

Controls need their own mechanisms. A maintained toggle, spring-return switch, guarded command, rotary selector, breaker, DSKY key, FDAI ball and indicator lens cannot all share the same animation or interaction rule. The handbook inventory describes the distinctions; unresolved travel limits stay unresolved rather than inheriting a generic animation.

A USDZ is only one part of the interactive delivery. The existing loader accepts named artist geometry, but live gestures and instrument updates still refer to separately built controls. Imported parts must be bound deliberately or they can overlap the procedural controls. The [pipeline review](blender-usdz-visionos.md) documents this against the current source, including required node names and the transition options.

Mission provenance needs to be recorded below the document level. A later handbook can include an earlier-vehicle foldout. A Smithsonian interior can depict LM-2 modified to resemble Eagle. A 1967 training figure can explain geometry without proving the Apollo 11 switch layout. Keep `vehicle`, `document_revision`, `figure_applicability`, and `evidence_kind` alongside each modeled assembly.

## Reference starting point

![Apollo 11 Eagle forward panel photograph](references/images/AS11-36-5389HR.jpg)

AS11-36-5389, flown Eagle. Useful for the visible panel arrangement, instrument housings, glareshields and color relationships. Focus and obstructions limit small-label transcription. [ALSJ image source](https://apollojournals.org/alsj/a11/AS11-36-5389HR.jpg)

The [photo catalog](photo-reference-catalog.md) pairs this with 69-H-134 for commander-window depth, 69-H-135 for illuminated legends, and Apollo 16/17 closeouts for lower ECS hardware. Later images are labeled individually.

## Proposed model evidence record

For each control, preserve a stable ID, panel number, printed legend, source URL and page/image ID, vehicle applicability, measured versus inferred dimensions, fixed housing, moving-part pivot, axis and travel, detents, return behavior, guard dependency, power dependency, indicator relationship, and simulation binding. Unknown values should be null with an explicit research issue.

Use independent statuses for visual fidelity and behavior. A well-modeled control can be `visual_only`; an animated control can be `mechanical_demo`; only a tested simulation connection should be `simulation_bound`. A reference from LM-11 may be well documented while still being a deliberate substitution in an Apollo 11-led cabin.

## Suggested next build and research sequence

1. Freeze the coordinate basis and block out both flight stations, center stack, windows, hatch and side tiers. Compare against the saved photographs from matched cameras.
2. Build a representative interactive group with the DSKY, one instrument, a maintained toggle, a momentary switch, a guarded command, a rotary control and a breaker. Check labels and selection at real scale.
3. Complete imported-node bindings and confirm the artist controls receive the current simulation state. Resolve duplicate procedural visuals before judging the asset.
4. Extend the documented panel inventory and resolve per-panel labels from the selected mission/revision. Model reusable components with individual provenance and state tables.
5. Add lighting, ECS, optics, aft cabin and stowage using the strongest source for each assembly. Keep later substitutions explicit.
6. Validate USD packaging, runtime names and dimensions, material appearance, stereo parallax, reach, dense-control selection, and performance on Vision Pro.

No Blender asset, USDZ export, app code change or hardware validation is claimed. This first pass establishes sources, modeling constraints and a concrete research queue. It does not yet provide an exhaustive switch-by-switch LM-5 reconstruction.

Packet verification: local Markdown targets resolve; the 12 image originals, five source PDFs/excerpts, and five figure renders have recorded hashes. PDF page counts and the handbook excerpt mapping were checked, as were the inch-to-meter conversions. No tracked application files changed. The packet occupies approximately 63 MB, mostly source scans.
