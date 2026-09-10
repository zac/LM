# Cross-pointer sources and reconstruction decisions

This is a source-guided visual reconstruction for a simulation-fed, later-style landing aid. It is not an Apollo 11 instrument/electrical qualification.

## Primary documents inspected

1. **Grumman Apollo Operations Handbook, LM10 and subsequent, Volume I**, table 3-1, printed page 3-16 (original PDF page 614; retained excerpt page 9). It assigns forward/lateral readings to Z/Y body axes for PGNS, and describes LR applicability from high gate to touchdown. The red lamp indicates interrupted instrument power. Printed pages 3-73/3-74 (original PDF667, excerpt26) establish ±20 ft/s velocity on LO MULT; HI MULT is ±200 ft/s with X10 illuminated. LOS LO uses X.1 and ±2 mrad/s. We support only LO velocity: both multipliers remain inactive.
   [Original searchable handbook](https://www.ibiblio.org/apollo/Documents/LMA790-3-LM10-ApolloOperationsHandbookLunarModuleLM10AndSubsequent-Volume1-SubsystemsData-SearchableText.pdf). The unchanged complete-page excerpt and its original page/hash manifest were copied from PanelInventory at ee3a19f; mixed revisions and later applicability remain explicit.

2. **D. Eyles, LUMINARY Memo165, 28 July1970, The Return of RIOFLAG**, page1. The revised descent display uses surface-relative velocity resolved with yaw; its forward/lateral axes coincide with body Z/Y only when erect. This is the source for a yaw-horizontal aid rather than directly passing pitched/rolled body velocity. The memo specifically distinguishes ascent/abort inertial crossrange output. Those modes are unsupported here.
   [Original memo](https://www.ibiblio.org/apollo/Documents/LUM165_text.pdf).

3. **D. Eyles, LUMINARY Memo171, 16 September1970, Introduction to ZERLINA50**, page2. Both velocity cross-pointer signs changed to make the display fly-to in pitch/roll. This is a development/simulator revision, not evidence of Apollo11 polarity or a claim that ZERLINA50 flew. Accordingly this component explicitly chooses a later-inspired simulation display and records the distinction.
   [Original memo](https://www.ibiblio.org/apollo/Documents/LUM171-DE_text.pdf).

4. **AOH figure reproduced by Gary Neff in ALSJ**, `xpoint-aoh.jpg` and `LM-Panel1.jpg`. The figure supports square face proportions, two curved blades, scale graduations 0/5/10/15/20, FWD VEL/LAT VEL, and multiplier placements. It does not establish dimensions, movement pivots, electrical polarity or material reflectance. These are reproductions of handbook drawings hosted in an editorial page, not independent mission photography.
   [Figure](https://apollojournals.org/alsj/xpoint.jpg), [panel figure](https://apollojournals.org/alsj/LM-Panel1.jpg), [context page](https://apollojournals.org/alsj/xpoint.html).

## Operational inference, separate from direct source facts

The fly-to description is translated into this explicit screen convention: rightward velocity drives the vertical blade left (roll-left correction); forward velocity drives the horizontal blade up (pitch-back correction). The memos do not state these local XYZ numbers or show verified LM5 wiring. This is an operational inference reviewed with the runtime/review workers. Numeric saturation and mechanical travel are application/authoring decisions. LM owns frame conversion, phase, validity and runtime tests.

Surface yaw-forward must be projected perpendicular to local radial up. Surface-right is forward cross up in the simulation's right-handed convention. Pure radial descent should produce zero horizontal readings. Reject nonfinite data, missing up and near-vertical projected heading; do not invent a heading. The exact computation stays in LM, not this asset library.

## Deliberate physical and presentation choices

- Existing Panel1__CrossPointer reservation is140x65mm, centered panel-local(-.07,.10,0). A square61x61mm façade fits at unit scale; no anisotropic deformation or peer inventory edit is used. Absolute size is provisional. Remaining slot area needs neutral backing from the coordinator.
- The20mm rear housing is a visual proxy. CommanderPanels currently has no cross-pointer cutout: backing/rear overlap is not mechanically qualified. No insertion/connector/service envelope or contact flange is claimed.
- Blades translate on independent X/Y nodes rather than reconstructing hidden meter pivots. Shallow bowing follows the drawing qualitatively, with scale-end travel±16mm. This is not a measured mechanical transfer function.
- Warm bright scales/needles over a dark face and small emissive terms favor legibility. No calibrated EL spectrum/photometry is claimed; the black-and-white schematic cannot establish materials.
- No synthetic mode/source placard is present in the production asset. Source qualification remains in the interface/handoff or optional host training UI. Inactive X10/X.1 and power flag remain addressable but do not imply implemented modes or electrical power simulation.
- Invalid simulation data hides the needle group rather than falsely centering it. This is an application policy; it does not masquerade as historical power-failure indication.
