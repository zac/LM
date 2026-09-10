# Enclosed Cabin foundation handoff

Built on clean `09364460e8be570338f3d39a07067fe2bee0b044` in `/Users/zac/.codex/worktrees/6943/LMKit`, branch `cabin-enclosed-foundation`. All changes are inside `Assets/Cockpit/Components/Cabin/`. No shared Sources/Tests/Tools, simulation, LM master assembly, other component assets, merge or push. Early proposal and preserved baseline were committed as `2fafa5b` before final window-edge geometry. Final commit is supplied by task handoff; this document does not embed its own hash.

## Delivered

A coherent, neutral, descent-ready visual shell: connected deck, forward cheek/backing surfaces, side liner and faceted crown, aft bulkhead and approximate engine cover; independent closed forward and upper transfer hatch leaves; independently addressable inspection cutaways. Actual forward and docking apertures remain open for WindowsLPD. 267 meshes / 2,760 triangles. No copied instrument/catalog/panel placeholder/surround/window geometry is present in the production shell.

Original metric datum and panel/instrument world poses remain unchanged. Forward hatch opening shifts Z -.95 to -1.02. Existing aft termination Z .5868 extends to an approximate midsection closure at 1.15; this does not revise the source's 42in forward-barrel dimension. Eye and construction triangle corners remain unchanged and provisional. See `DATUM.md`, controlling `interface-v2.json`, and `mounts.json`.

The forward finite-thickness cheeks are trimmed along the provisional eye-to-construction-corner rays to avoid clipping the opening. This is a compatibility treatment, not optical calibration. The original datum, source builder, mounts, handoff and USDA remain in `evidence/baseline-0936446/`; original authoring provenance `eb4efc1` is retained. Retained Optical nodes and empty LPD layers are comparison metadata only.

## Dependencies and evidence

- Windows contract: `80c9b2d`, exact `interface-v1.json` SHA-256 `28bb74258353bbc8365b7a54011782332ff69927c0683154a46b80b8ad24f22f`. Local pinned copy in `evidence/foundation/`. Its right-handed docking basis uses local up +Z; the earlier reflected proposal is preserved separately as superseded evidence.
- Combined visual review only: Windows `5699e64d29ee0ec77c60d2324f64e51fe68156e3`, USDZ `91c03cc4b6826473cfdccdce195fece5f591b778b8afdb3a71505df8f528cc32`. Imported at identity into a temporary Blender scene, never saved into Cabin.blend or Cabin USD.
- Accepted ACA: SHA-256 `df2b00baa607543deedc89ba3a2e87fb5862e5243e02dd104981bd34aef254c5`, runtime mount (-.49,.9075,-.37), from accepted LMKit `86aa71b`. Read-only LM integration evidence at `11f7335` retained under `evidence/foundation/`; original validation manifest distinguishes its test-source commit `7c1b4a7`.
- `evidence/foundation/provenance.json` records exact reference file hashes, original URLs, page locators, applicability, helper provenance and substitutes. Grumman 1967 plan/section full-page renders retain their captions. Apollo11 photo guides forward relationships; Apollo16 deck photo is a qualitative substitute only. Aft closure, transfer hatch pose, engine-cover size and wall thickness are explicitly approximate.
- `artifacts.json` is the final source/output/review hash index. Blender 5.2.1 LTS build `9e2066aef7ef`. No add-ons, linked libraries, network dependency, external texture or heavy render/bake.

## Validation

- `validation.json`: 3,556 checks pass. Metric Blender, USD meters/Y-up, proper rotations, identity scales/root, closed outward solids, nondegenerate geometry, bound Preview Surface materials, every world transform, USDZ reimport, physical bounds. ARKit compliance: zero errors/failed checks/warnings.
- 342 interior construction-triangle sightline samples are unobstructed. 16,384 spherical rays from CDR/LMP/aft/low positions show zero unexpected escapes; permitted escapes are through agreed windows. This samples visual enclosure, not pressure-tight topology.
- `validation-native.json`: native macOS RealityKit load, preserved ten mount poses, eye/pane comparison bases, named independent hatch/leaf groups and absence of duplicated old geometry. No simulator jobs.
- `aca-clearance.json`: 729 sampled poses at 2.75-degree steps over +/-11 degrees on all three axes, zero Cabin mesh AABB overlaps, minimum 25.049984mm gap at `CDR_Front_Lower_00`. Conservative AABB separation at sampled poses; not continuous collision or hand/reach certification.
- `reviews/`: front, side cutaway, CDR, LMP, rear, overhead, deck cutaway and side interior. Combined views include actual final Windows miters and docking retainer. Workbench glazing is hidden to expose opening edges; actual USD keeps neutral material semantics.

Combined review shows rounded frame corners covering the sharp shell construction edges and an open docking window. Wall-to-retainer backing contact is expected; no claim of mechanical seal mating. Fine surface intersection/contact, optical targeting, panel sightlines in the full assembly, pressure vessel, hinge sweep/egress, headset stereo/reach/photometry and performance remain unqualified. Blank aft/side spaces are intentional equipment mounting areas. Imported and old LPD targeting remain unqualified.

P5 Timer/top-rail notch is PanelInventory-owned. It does not create a hull opening: this shell remains continuous behind/below that equipment tray. No ACA or panel pose change was made. Mount metadata does not imply live bindings.

## Reproduce

From repo root, using a materialized Git LFS checkout:

```sh
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python-exit-code 1 --python Assets/Cockpit/Components/Cabin/build.py
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python-exit-code 1 --python Assets/Cockpit/Components/Cabin/validate.py
xcrun swiftc -module-cache-path /tmp/cabin-swift-module-cache -parse-as-library Assets/Cockpit/Components/Cabin/validate_native.swift -o /tmp/cabin-validate-native
/tmp/cabin-validate-native "$PWD/Assets/Cockpit/Components/Cabin/Cabin.usdz"
```

Compile `check-aca-clearance.swift` the same way; arguments are the materialized resource base containing `HandControllers/ACA.usdz`, then absolute Cabin.usdz path. `review_combined.py` accepts `-- /absolute/path/WindowsLPD.usdz` after Blender's script argument. It writes only review PNGs/report; no production asset save. The exact dependency hashes above are required for comparison. Rebuilding produces equivalent geometry; binary authoring timestamps are not claimed bit-reproducible.

## Install — coordinator only

1. Replace the complete old `/Cabin` once with this Cabin.usdz at identity. Keep independently loaded instruments and CommanderPanels. `migration.json` enumerates all 71 removed original visual nodes/paths; do not reinstall old panes, frames, reservations or glareshields by name.
2. Install WindowsLPD separately at identity, using its corrected contract and historical-view policy. Cabin Optical nodes are metadata only. Install PanelInventory blanks and separate planning labels; preserve its unresolved ACA/Timer slot.
3. All `Cutaway_*` groups and `Hatches` start visible. Inspection may disable named cutaway groups; restore them for the enclosed view. Hatch leaves are static authored surfaces, not actuated or certified hinge pivots.
4. Coordinator refreshes shared runtime resources using the approved Tools workflow, including `Tools/sync_dsky.py`, then validates packaging and serial LM integration. This worker intentionally did not touch shared packaging or run a simulator.

## Late user-reference review

All three images from coordinator reference commit `a525dd6` were visually inspected after the asset commit. `reviews/USER-REFERENCE-COMPARISON.md` records visible deviations: smooth/faceted lining lacks perforated ceiling and detailed hatch hardware; side equipment bays remain intentionally empty; the coarse central cover is not positively identified with the photographed obstruction. Unknown image provenance and Smithsonian LM-2 restoration applicability remain explicit. This is a qualified foundation, not a finished historical cabin. No agreed interface or geometry changed from those qualitative images.
