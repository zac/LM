# FDAI evidence assessment

Inspected 2026-09-08. Photographs are source evidence, not surface textures. Original image rights remain with their credited creators; no blanket license is assigned by this delivery.

## Mission-specific and primary evidence

**AS11-36-5389**, NASA Apollo 11 in-flight cockpit photograph, preserved as `AS11-36-5389HR.jpg`, establishes the LM-5 octagonal face, three peripheral meters and two-tone ball. The source is oblique, partially occluded and reflective. It supplies no calibrated ruler or mechanical dimensions. Original archived URL: https://apollojournals.org/alsj/a11/AS11-36-5389HR.jpg . Copied byte-for-byte from the cockpit coordinator's preserved reference, not resampled.

**NASA FC027, LM-5 through LM-9 Systems Handbook**, January 17 1969, cover revised by Change 4 June 2 1969. Preserved 13-page source extract: `LM5-LM9-systems-excerpt.pdf`; drawing 10.4.3, PDF page 5 / printed 10-7, also rendered in `LM5-FDAI-drawing-10-4-3.png`. https://apollojournals.org/alsj/LMSysHandbk.pdf . Its labeled upper vertical roll-error, horizontal pitch-error and lower vertical yaw-error pointers are the authoritative component arrangement. It distinguishes the sphere drives and vehicle roll Z / pitch Y / yaw X. Those vehicle axes must not be confused with this asset's X-right/Y-up/Z-crew basis. No dimensional outline is present.

This drawing shows ±20°/second rate-meter annotations and ±5° errors. Later LM rate selection is described as 5/25°/second. The drawing therefore does not justify a universal software calibration. All scales in this component remain visual marks; the consuming app owns selected sensitivity and signal interpretation.

## Explicit substitutions and comparisons

**Apollo 14 LM-8 FDAI**, Grumman photograph, scan by Paul Fjeld, courtesy Karl Dodenhoff/My Little Space Museum. `apollo14-fdai.jpg`, https://apollojournals.org/alsj/MLSM-LM-8FDAI.jpg , contextual page https://apollojournals.org/alsj/alsj-FDAI.html . This is the clear close-up used for trim, ROLL/PITCH/YAW RATE legend placement, ivory meter strips and amber error bars. It is a later-mission substitution. It does not certify LM-5 typography, dimensions or finish.

**CSM comparison photograph**, Bruce M. Yarbro/Smithsonian credit visible on image, `csm-fdai-comparison.jpg`, https://apollojournals.org/alsj/afj-fdai.jpg . The circular CSM installation and its wing are not the target LM facade.

**Ken Shirriff's firsthand FDAI teardown**, https://www.righto.com/2025/06/inside-apollo-fdai.html , discusses a repurposed Apollo LM unit modified for Shuttle simulator use. The account distinguishes its altered reticle/paint from the original LM crosshair, red side bands and rate legends. It supports pivoted galvanometer pointers and explains why the ball mechanism has separate axes. Its altered specimen is not a controlled LM-5 dimensional source. No internals were reconstructed from it. The renderer's central crosshair and red side bands follow the LM distinction, not the modified specimen.

**RR Auction early unflown LM unit**, https://www.icollector.com/Lunar-Module-Flight-Director-Attitude-Indicator-FDAI_i19544310 , approximately 5.75 inches square ×11 inches long, Lear Siegler Model 4068 C. Used only as a provisional envelope clue; not a manufacturing or installation drawing. The modeled nominal face is 146.05 mm square; gasket increases measured extents to 148.05 mm. The rear shape is simplified and its connector has no claimed pinout.

## User-provided sources

**19730061045.pdf**, Apollo Operations Handbook, CSM spacecraft 012, November 12 1966. Original remains at the user-provided path; its hash is in `provenance.json`. Inspected physical PDF pages 185–186, printed 2.3-27–28, preserved as full-page PNGs. Page 185 describes the CSM fixed indices, a geared roll bug and fly-to needles. Page 186 describes attitude reference behavior. These are CSM Block I facts, not an LM mechanical contract. The optional roll bug in this component remains separately addressable with unverified LM linkage.

https://apollojournals.org/afj/ap16fj/01popup_fdai.html describes CSM display interpretation, peripheral rate positions, colored ball regions and selected scales. Its CSM switch values and Honeywell facade were not imported into this LM component.

https://apollojournals.org/afj/ap08fj/02earth_orbit_tli.html#0003028 explains inertial versus orbital-reference display behavior and ORDEAL in the context of Apollo 8. It supports keeping reference-frame state outside the visual asset. It is not a source for LM dimensions.

https://www.ibiblio.org/apollo/yaTelemetry.html#gsc.tab=0 documents Virtual AGC peripheral tools, including a separate IMU/FDAI simulator whose state is distinct from the AGC core. It is an integration research lead, not validated LMKit binding code or evidence of hardware geometry. No code from that simulator was added.

## Comparison and limits

The final front review matches the LM reference's octagonal trim, black field, top/right/bottom meters, ivory strips, amber error needles and ball markings. The neutral model shows zero geometric offsets rather than copying the photograph's instrument state. Separate static renders expose both yaw caps and combined pointer motion.

The inherited 4096×2048 texture uses abbreviated numeric labels, contrasting hemispheres and 15-degree red polar regions. It is retained exactly, with explicitly authored UV mapping. Font shape, red-band extent, roll scale layout and error-index spacing are visual approximations. The exact historical dial artwork, optical depth and electro-luminescence remain unqualified. No power-off flag or servo internals are modeled. The larger backing plate, mounting screws and rear connector are provisional exterior geometry; no cutout or mating surface can be inferred.

## Glass round trip

Blender 5.2 imported the USD constant opacity 0.055 as Transmission Weight 0.945, leaving Alpha=1. This was initially flagged by an overly narrow alpha-only check. The material was inspected rather than suppressing the issue. Blender's importer explicitly makes this conversion when opacityThreshold is zero and opacity is not an alpha-texture connection: https://github.com/blender/blender/blob/main/source/blender/io/usd/intern/usd_reader_material.cc . Validation now checks the represented transparency and records both values. The source's blended glass and imported transmissive glass may look different; RealityKit rendered appearance remains a coordinator gate.
