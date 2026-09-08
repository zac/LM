# DSKY facade evidence check — 2026-09-08

Research was bounded to the external facade, against the assignment and draft v0 cockpit contract. These findings are recommendations to the component builder, not claims that every change has been implemented.

## Mission-specific annunciator panel

The [2003994-091 assembly drilldown](https://www.ibiblio.org/apollo/2003994-091.html) identifies find 37 as **1005025-001, Indicator, Status/Caution**, and find 38 as 2003988-011 or -021 E/L and cover. The [mission configuration research](https://www.ibiblio.org/apollo/yaDSKY.html) identifies -091 with Apollo 11 onward lunar modules. Generic outline 2003956 Rev B and assembly Rev G facade illustrations must therefore not override the -091 annunciator specification: those show earlier arrangements.

Primary **1005025**, initial release, sheets 1–3, was downloaded and visually inspected from MIT Instrumentation Laboratory / NARA aperture cards, [Box 438](https://archive.org/details/apertureCardBox438NARASW_images), zero-based pages 1689, 1690, 1691. Archive item labels these public domain.

| Local evidence | Direct source |
|---|---|
| research-1005025.jpg | https://archive.org/download/apertureCardBox438NARASW_images/page/n1689.jpg |
| research-1005025-sheet2.jpg | https://archive.org/download/apertureCardBox438NARASW_images/page/n1690.jpg |
| research-1005025-sheet3.jpg | https://archive.org/download/apertureCardBox438NARASW_images/page/n1691.jpg |

Front layout is two columns of seven cells. Left from top: UPLINK ACTY, NO ATT, STBY, KEY REL, OPR ERR, blank, blank. Right: TEMP, GIMBAL LOCK, PROG, RESTART, TRACKER, ALT, VEL. The lower two left cells physically exist but have no Apollo 11 legend. Do not add later PRIO DISP / NO DAP decals. The drawing's hatch convention marks every right cell and the lower two left spares yellow; the upper five left cells are white. This resolves ALT/VEL as physically present for the selected instrument revision.

Sheet 3 dimensional callouts: legend width 1.095–1.105 inches; legend height .525–.535 inches; successive row datum differences approximately .595 inches. Case flange width 3.255–3.265 inches, flange height 4.410–4.425 inches. These are source dimensions of the status/caution subassembly, not replacements for the app's DSKY mounting datum. Current build.py's initial 33 mm cell width was larger than the nominal 27.94 mm source dimension; preserve the interface but refine interior spacing.

Sheet 1 specifies approximately .156-inch-high Gorton Condensed black legend characters, centered on the display. Sheet 2 calls for an acrylic face sheet and aluminum case; unenergized legend areas are low-reflectance diffuse neutral gray, with black characters, and surface gloss of at most 5 units. Thus a glossy green or amber unpowered lamp is not a faithful material. Energized colors are aviation white / aviation yellow under MIL-C-25050C. Sheet 1 calls for legend-background luminance 15 ±3 foot-lamberts; there must be no leakage between lit and unlit cells. Use separate emissive background meshes/material state per lamp, retaining black opaque lettering. Exact RGB and engine emission-strength values require render calibration and are not established by this drawing.

## Digits, keyboard, and appearance

The inspected 2003956-B and 2003994-G source images establish the broad numeric layout: COMP ACTY upper left, PROG and two numerals upper right; VERB and NOUN below those; three signed five-place register rows below, with horizontal rules. Numerals are visibly slanted seven-segment forms, unlike upright rectangular LCD digits. The initial build.py uses upright box segments and unlit materials everywhere; for an illuminated preview, give the segments restrained green emission and a modest slant / chamfered ends, and label the readout explicitly as a static preview. Do not bake a simulated program into the asset.

The [MIT final computer design report R-713](https://www.ibiblio.org/apollo/klabs/history/history_docs/r713.pdf), section 2.3, describes segmented electroluminescent registers and a keyboard whose characters are illuminated with electroluminescent panels. This supports illuminated glyphs rather than a glow covering the entire plastic key. Exact key surface sculpt and emission hue are not dimension-certified here. Gorton Normal is the appropriate engraving pattern lead for key legends; [Gene Dorr's font reconstruction](https://github.com/ehdorrii/dsky-fonts) is a useful secondary reproduction reference, but no font has been copied into this asset and its reuse license was not verified.

Apollo 11 photograph AS11-36-5390 and preflight photos 69-H-134/135 were inspected from the local dossier. These provide cockpit context but do not resolve the standalone DSKY facade closely enough to measure keys or settle precise color. Do not describe them as close-up material calibration. Existing dossier caveat about COMP ACTY white versus green remains unresolved by the status/caution drawing, since COMP ACTY belongs to the separate numeric E/L assembly. Source 2003988 was located in Box 459, but its multi-file archive page endpoint returned an unrelated rope-driver specification; that image was rejected and is not included as evidence.

## Integration-facing construction

Keep each required DSKY_Key_* neutral transform directly under DSKY_Mount, with cap, legend, and any visual feedback children beneath that transform. Use distinct geometry or material slots for emissive glyphs, key body, and optional hover appearance so the coordinator can highlight a single key without highlighting the face. Do not make a unified mesh across keys. The asset cannot by itself prove eye-target / pinch behavior: the coordinator must attach RealityKit input/collision/hover components, route to the existing AGC, and test on-device. The selected press depth remains provisional; preserve PRO press/release handling and all current binding names.
