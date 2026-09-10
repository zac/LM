# Enclosed shell visual review

All PNGs are lightweight Blender Workbench geometry reviews, not historical photometry or Vision Pro captures. Closed static hatch surfaces are present; glazing is intentionally absent for WindowsLPD installation. No panel blanks or instruments are included in this component.

- `front.png`: aft wall hidden, looking forward; floor, front closure and open triangular holes.
- `side.png`: LMP side and ceiling hidden; deck-to-wall transition and forward depth.
- `crew-eye.png`, `lmp-eye.png`: actual preserved eye positions, looking through the corresponding construction aperture.
- `rear.png`: all groups visible, from front interior looking at closed aft wall and approximate raised cover.
- `overhead.png`: all groups visible, central transfer hatch closed.
- `overhead-cutaway.png`: ceiling and hatch group hidden to inspect connected deck and standing area.
- `side-interior.png`: all groups visible, showing side wall from inside.

The intentionally undecorated shell leaves equipment to other components. Faceted forward cheek transitions and the aft bulkhead remain coarse. The aft section is an appearance approximation; it must not be described as the full measured pressure vessel. Frame/shell overlap, panel installation sightlines and combined equipment review are coordinator gates. Physical headset stereo, reach, gaze/pinch and frame rate were not tested.

Enclosure validation casts 16,384 evenly distributed directions from CDR, LMP, aft and low central positions; only agreed window openings may escape. This samples visibility, not watertight topology or structural certification. Each constituent mesh separately passes closed-edge and outward-winding checks.

Final combined checks use WindowsLPD commit `5699e64` (see `combined-review.json`). `combined-docking-review.png` directly inspects the crown opening. Retainer-to-liner backing contact is expected, while the visible central apertures remain clear. The corner-miter joins are a visual check, not a mechanical fit acceptance. The final shell thickness is trimmed along the provisional forward eye rays; 342 independent construction-triangle samples confirm it no longer clips those sightlines.
