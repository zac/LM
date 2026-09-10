# Review views

All images are transient Blender Workbench review compositions, not app/runtime renders. Blue meshes are the exact delivered neutral instrument triangles at accepted poses, with a uniform review material and no live display state or texture. They exist only during `review.py`, never in the production Blender/USD assets. Gray context is Cabin geometry. Review labels are image annotations implemented as transient camera text, never production labels.

`front.png`, `side.png`, `crew-eye.png`: the accepted observer eye and target coordinates, including fixed CDR eye (-.5588,1.78,-.38). Blender uses its own documented 20 mm projection and 1200 x 1000 framing; these are not pixel-identical simulator or headset captures. Both instrument faces and surround edges remain visible. Panel 1's narrowed outboard edge leaves a gap to the window structure. Blank backing areas are intentionally unpopulated, not a proposed full control catalog.

`FDAI-aperture.png`, `DSKY-aperture.png`: instrument references hidden to show actual through openings. `*-clearance.png`: oblique views expose backing depth, gaps and rear housings. `*-section.png`: transient central X section removes the +X half of support and instrument meshes; open cut boundaries in these review scenes do not represent production mesh defects. No internal mechanism is inferred from the sectioned exterior. The section shows an open rear and no instrument-contact flange.

Cabin crown/side skin and transparent pane surfaces are omitted from these review renders to expose the forward stack. Panels 1/4 reservation backing, instrument reservation rails and both glare shields are omitted consistently with accepted installation. Other Cabin context, including original Panel 5/6 reservations, is reference-only; this is not a complete reconstruction of live app controls. Do not use it to qualify ACA sweep, control collisions or egress.

Camera metadata and per-frame timing are in `cameras.json` and `render-times.json`. These are small Workbench renders with no bakes or visionOS simulator use. Materials/photometry, headset legibility and frame time are not qualified.
