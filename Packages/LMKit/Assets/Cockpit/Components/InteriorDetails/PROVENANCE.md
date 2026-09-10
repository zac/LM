# Interior detail evidence and reconstruction

These meshes are optional visual reconstruction for the existing provisional cabin. No exact Apollo 11 cable route, screw pitch, clamp design or material formulation is established. All numeric dimensions and placements in `build.py` are deliberately provisional. None of the geometry represents a new functioning subsystem.

## Sources actually inspected

- [User photo: occupied cutaway cabin](../../../../References/Interior/User-2026-09-08/583935771_852557297354456_2723809586326518278_n.jpg): visible lower side wiring/bundles, metallic supporting edges and repeated fasteners; overhead edge routing. Original vehicle, photographer and date remain unestablished in the shared manifest. Used for hardware vocabulary and visual density, not dimensions or mirrored routing accuracy.
- [User photo: museum interior](../../../../References/Interior/User-2026-09-08/images.jpeg): pale upper liner panels with seams and discrete fasteners, exposed cables beside and below the forward control stack, layered structure. Museum/restoration state is not flight configuration evidence. Visible photographic credit is preserved in the original; this component does not redistribute a modified crop or bake the photo into a texture.
- [User collage](../../../../References/Interior/User-2026-09-08/511406576_9899452223514721_2569389181361959162_n.jpg): inspected to distinguish historical/diagram excerpts from a simulated illuminated cockpit. The simulated display, labels and window overlay are not copied into this component.
- [Coordinator's Smithsonian LM-2 panorama observations](../../../../References/Interior/User-2026-09-08/PANORAMA-OBSERVATIONS.md): independently visible cable paths, clamps, exposed supports, panel seams and ceiling depth justify this class of detail. LM-2 was a ground-test vehicle later presented as Eagle; the panorama is not a mission-accurate measured LM-5 survey. [Smithsonian panorama page](https://airandspace.si.edu/multimedia-gallery/panorama/lm-interiorjpg).

Shared original file provenance and hashes remain in [reference manifest](../../../../References/Interior/User-2026-09-08/manifest.json). No new rights or mission claims are inferred.

## How evidence became geometry

- CDR/LMP lower side harnesses: four plain sleeved runs, one dark and three muted ivory, with discrete bent-strip clamps/pads and screw heads. The shallow horizontal routing is chosen to fit the current reserved interior, not traced from a specific flown wire harness. Ends are capped geometry; exact destinations and connectors are unknown. The paired stations are a practical mirrored provisional treatment, not evidence of historical symmetry.
- Lower liner trims: narrow L-section deck-edge straps and separate fore/aft seam strips with repeated fasteners. Forward strips stop below the side tray slot envelopes. They add an edge treatment without moving or replacing the underlying liner.
- Upper liner details: narrow seam bands and paired restrained sleeves follow the actual existing Cabin crown facets 3–5. Their offsets avoid penetrating the liner. They sit above the breaker bank zone, outboard of camera/COAS, and avoid the docking aperture. Wire destinations and connector identities are not invented.
- Forward header trim: simple shallow straps and fasteners follow the existing `Forward_Above_Hatch` plane, above the instrument faces. This is source-guided visible panel-edge treatment, not a new instrument or equipment box.
- Clamp and fastener forms are low-poly approximations: there are no engraved part numbers or text-as-mesh. Neutral material values are visual choices, not calibrated reflectance or flight paint specifications.

## Preserved boundaries

No breaker-strip hardware is included: the separate BreakerBanks worker owns it. No control slot is filled or hidden; no switch, instrument, support, panel datum or window is moved. No hatch operation, simulation, emissive effect, input target, collision or light is introduced. All detail groups can be removed independently.

## Second detail phase

The original seven groups retain identical mesh/topology/attribute fingerprints; `evidence/phase1-group-fingerprints.json` and `validation.json` record that check. Six added groups extend the same optional overlay:

- `ForwardOverheadLiner`: two shallow cover frames and actual open mesh inserts below the existing forward roof bridge. The supplied museum photo and panorama notes show pale solid liner sections interrupted by mesh/perforated patches. These particular rectangular subdivisions, 12 mm mesh pitch, 1 mm bars and placements are visual approximations, not copied flight part geometry. They do not cut or replace the cabin roof.
- `CDRAftCrownInserts` and `LMPAftCrownInserts`: similar narrow mesh/cover fields follow actual crown facet 2 behind the docking window and outboard of the transfer hatch. They are not claimed to be ventilation grilles or a working airflow path. The underlying liner remains intact.
- `ForwardHeaderCableRun`: two sleeved routes with four simple retaining clamps above the forward control stack. The photos support exposed constrained routing in this region; specific circuit identities, end connectors and mirrored route details remain unknown. This is visible geometric texture, not a new instrument.
- `ForwardHatchFittings` and `TransferHatchFittings`: simple fixed handgrips, mounting bosses and discrete fasteners relieve the otherwise blank closed hatch faces. Neither the exact handle design nor fastener count is established by these references. They are explicitly provisional and do not model a latch, pressure seal, lock or qualified hinge. They stay within the existing closed-leaf outlines. Disable/reparent these groups if a future host opens or removes a leaf; this overlay itself has no hatch state or animation.

These additions preserve all existing openings and underlying boundaries. No source image is used as a texture. Fine mesh, handle proportions, fastener spacing and colors remain explicit approximations awaiting closer source drawings or suitably licensed detailed photographs.

### Added cover material

`LinerCream` uses an uncalibrated diffuse RGB of (0.67, 0.66, 0.56), with roughness 0.64 and no metalness. The warmer/light cover color is a visual interpretation of the pale museum liner sections in `images.jpeg` and the panorama notes. It deliberately differs from the retained gray Cabin shell; the shell material is not changed. `LinerMesh` uses provisional RGB (0.39, 0.40, 0.34) and metalness 0.15. Neither value is measured Apollo paint, reflectance, lighting or aging evidence. Workbench shading is not the final native material appearance; evaluate those materials with the coordinator's runtime readability/lighting changes before visual acceptance.
