# Panel and equipment evidence assessment

Target: descent-ready Apollo 11-led interior. This inventory is a major-region planning map, not a complete flight switch transcription or a verified LM-5 stowage configuration.

Primary evidence read visually in this task: NASA `ad013.gif`, `ad016.gif`, `ad017.gif`; later Apollo 16 closeout `LM11-co42.jpg`. The copied controls study identifies the original handbook page numbers and mission limits; its 41-page original scan excerpt and original/excerpt hash manifest are included. `files.json` hashes intact copied evidence. `manifest.json` is the original image URL/retrieval record, including failed NASA URLs and successful archive alternatives.

| Evidence | Applicability and use | Limit |
|---|---|---|
| NASA News Reference drawing ad013, https://www.nasa.gov/wp-content/uploads/static/history/diagrams/ad013.gif | Numbered panels 1–6,8,11,12,14,16, ORDEAL; major instrument/region organization; five commander and four pilot breaker strips | Undated configuration, exploded panel layout, not scale or installed dimensions |
| AOH LM10+ §1.2.2.1.1 printed 1-8 / original PDF21 | Panel numbering, station relationship and nominal inclinations | Later handbook, not an Eagle configuration certification |
| AOH printed 3-75–3-80 / PDF669–673; 3-87–3-88 / PDF681–682 | DSKY on P4 and DEDA on P6 | Functions inform names only; no behavior implemented |
| NASA 1972 notebook ad016, https://www.nasa.gov/wp-content/uploads/static/history/diagrams/ad016.gif | AOT at upper center; COAS commander side; sequence camera pilot side; utility lights and lower forward stowage | Later program diagram; approximate placement only |
| NASA 1972 notebook ad017, https://www.nasa.gov/wp-content/uploads/static/history/diagrams/ad017.gif | Oxygen/water/ECS on image-left **when looking aft**, therefore Cabin +X; LGC/DSEA/PLSS/CDU/WMS on image-right, therefore Cabin -X | Perspective cutaway; no measured center/envelope, no invented panel numbers |
| Apollo 16 LM11-co42, archive URL in manifest.json | Lower forward bags and stowage relationships | Clearly later closeout, not Eagle descent-ready content |
| Apollo 11 AS11-36-5389HR | Forward configuration comparison reference retained | Exact panel outline or dimensional inference not extracted here |

All authored outlines, frame thicknesses, subdivision boundaries, instrument envelopes used for blanks and text sizes are provisional visual authoring choices. Existing DSKY/FDAI offsets and their full front envelopes come from the pinned CommanderPanels contract, not photographs. The surrounding panel slot divisions do not establish switch centers. The current generic rectangular tray outlines deliberately avoid asserting unmeasured fabrication outlines.

No invented panels 7/9/10/13/15: unverified region numbering stays descriptive. ORDEAL is a separate named assembly. AOT, COAS and sequence-camera placeholders are equipment reservations with plain blank faces, not optical models. Windows/shades/LPD stay WindowsLPD-owned; no marks or eye transforms are copied into this runtime asset.

Aft equipment is named from the primary aft diagram, with camera-relative left/right converted explicitly to Cabin axes. Ascent engine cover, overhead/forward hatch leaves, drogue clearance, restraints and armrests are external structural/context entries owned by Cabin. The overhead relief-valve reservation is beside/below the hatch; it is not a replacement hatch face.

## What remains unresolved

- Exact LM-5 side/aft equipment outlines, mounting station dimensions, descent-phase stowage and routing.
- Pilot ACA and both TTCA installation poses. Available external components are registered without guessed bindings or duplicate geometry.
- Full continuous ACA sweep, housing supports, pinch/gaze/hand reach, cabling and service access.
- Combined Cabin/Windows/CommanderPanels fit and native visionOS rendering after coordinator packaging.
