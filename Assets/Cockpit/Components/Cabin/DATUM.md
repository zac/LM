# Enclosed Cabin datum v2

Descent-ready visual interior. This replaces the OPEN skeleton. Metric +X right/LMP, +Y up, -Z forward; `/Cabin` root is identity. Native Blender is Z-up; `build.py` physically converts points, normals and local transforms. This is approximate visual enclosure, not certified pressure-vessel or hatch engineering.

The original freeze is superseded. `evidence/baseline-0936446/` preserves the original datum, mount manifest, builder, handoff and USDA. Historical LPD calibration claims there are comparison evidence only.

| Quantity | Current construction | Qualification |
|---|---|---|
| Barrel | nominal R 1.1684, center Y 1.10, Z -.48 to +.5868 | 92in diameter / 42in depth from Apollo 11 press kit printed p96; registration approximate |
| Aft visual closure | Z +1.15 | New approximate midsection extension, not a revision of the 42in forward compartment dimension |
| Standing deck | original 1.397 x .9144 inset, top Y .1225 | Early Grumman approximate 55x36in; original axis assignment remains provisional |
| Floor additions | full connected side/forward/aft floor | Visual liner beneath future equipment; usable clear area will shrink with installation |
| Crown | faceted circle except central flat roof X +/-.43, Y 2.1863971 | Visual liner; flat hatch surround not surveyed |
| CDR/LMP eye | (+/-.5588,1.78,-.38) | Original reference preserved, not calibrated gaze/reach acceptance |
| Forward triangles | exact baseline sharp construction corners | WindowsLPD supplies rounded visible apertures, panes, seals and markings; no optical certification |
| Docking opening | .137 x .3402 tangent opening at (-.5588,2.1261097,-.2) | Nominal viewing dimensions and curved pane supported by TN D-7439 p9; placement approximate |
| Forward hatch | .8128 square, center (0,.55,-1.02) | Nominal 32in from press kit; moved -.07 Z from old mount; closed leaf and shallow relief approximate |
| Transfer hatch | .8128 diameter, center (0,roof,.65) | Coarse upper transfer closure; pose/outline needs later source refinement, no hinge/egress claim |
| Engine cover | X +/-.315, Y .1225 to .4425, Z .60 to 1.15 | Qualitative raised cover from Grumman plan/section, dimensions invented and explicitly replaceable |
| Panel/instrument mounts | exact old world positions, rotations, names and paths | Reservations only; no measured mating planes and no new instrument placement |

`interface-v2.json` is the controlling interface, with the agreed WindowsLPD reference/hash. Right/up/inward-normal must form a proper rotation; docking local up is +Z aft. The first window proposal used a reflected basis; this was corrected with the window worker without moving the symmetric opening.

Grumman training drawings (1967, LM-2 design basis) establish the continuous floor, forward barrel plus aft equipment region, central raised engine cover and upper transfer opening relationships. They do not survey an LM-5 interior. The Apollo 16 floor photo is used only for qualitative low threshold and deck strip appearance, not stowage installation; the cabin is descent-ready, not surface-stay clutter. Apollo 11 closeout/flight photos guide forward cheek and roof relationships. Exact file hashes and page locators are in `evidence/foundation/provenance.json`.

No PanelInventory blank faces, CommanderPanels surrounds, window frames/panes, controls or finished instruments are copied into this shell. `Mounts` and `Optical` are non-rendering metadata; retained `LPD_Inner/Outer` nodes have no artwork. Use the independent WindowsLPD asset for new optics. `migration.json` enumerates every removed original visual node and the cutaway groups.
