# DSKY mounting and envelope audit

2026-09-08. Read-only interpretation of primary outline **2003956 Rev B**, archive PDF page 73, preserved as `2003956-B.png`; inspected the larger local raster for dimension extension lines and notes. This audit concerns geometric placement and does not certify a receiving cockpit cutout.

## What is established

All drawing dimensions below are inches, converted using exactly 25.4 mm/in. Square-marked dimensions are controlled by ICD MH01-01305-116 per drawing note 1. The ICD itself and mating cockpit cutout were not inspected.

| Drawing callout | Interpretation | Metric |
|---|---|---:|
| 8.124 | Overall front-face width | 206.3496 mm |
| 8.000 | Overall front-face height | 203.2 mm |
| 7.700 | Left/right mounting-thread centerline separation; **not housing width** | 195.58 mm |
| .212 | Side edge to mounting-thread centerline | 5.3848 mm |
| 6.900 | Span between inward shoulder/body edges drawn on front elevation | 175.26 mm |
| .400 | Mounting-thread centerline to inward shoulder/body edge | 10.16 mm |
| .500 | Bottom face edge to lowest mounting-thread centerline | 12.7 mm |
| 2.330 / 4.670 / 7.000 | Other three mounting-thread rows measured from lowest thread row | 59.182 / 118.618 / 177.8 mm |
| 4.900 MAX | Rear envelope from UNIT MTG SURFACE | 124.46 mm max |
| 2.000 REF, SEE NOTE 5 | Nominal front projection from UNIT MTG SURFACE | 50.8 mm reference |
| 6.91 MAX REF | Overall depth reference in side elevation | 175.514 mm max reference |
| 2.50–2.53 | Connector mounting surface to UNIT MTG SURFACE | 63.5–64.262 mm |

The mounting-thread rows are distinct from the larger face assembly screw heads. A face-center datum puts the eight interface thread centers at x = ±97.79 mm and y = −88.9, −29.718, +29.718, +88.9 mm. Their front-view locations are established; the audit does not establish thread engagement geometry or machining clearances.

The **UNIT MTG SURFACE** leader in the side view terminates at the vertical shoulder 2.000 REF behind the front. It does not identify the rear of a thin front plate as the mounting plane. A useful placement datum is that shoulder plane at face center. If the modeled reference face is USD Z=0 and +Z faces the astronaut, its nominal mounting datum is Z=−0.0508 m; this is a placement reference derived from a REF dimension, not a newly controlled manufacturing datum.

## Configuration exception

Note 5 applies the 2.01/1.99 front dimension to universal DSKYs except listed later configurations, including **2003994-021 and subsequent**. For those configurations, the surface of E/L and cover assembly 2003899-011 can protrude beyond the shown maximum by up to **.09 in (2.286 mm)**. Selected assembly -091 is later than -021, so treating 6.91 MAX REF as an unconditional bounding box for every visible surface is not justified. The .09 allowance concerns the E/L-cover surface; it is not permission to deepen the entire housing. The independently documented -091 assembly uses a later E/L-cover part, so its exact front protrusion still requires that assembly's dimensions.

## Fit assessment and safe changes

The front face width and height match the outline. The previous simplified 7.7 in wide, 7.55 in tall housing cannot be called an exact insertion envelope: 7.7 in is the mounting pitch, and 7.55 in has no matching dimension in this outline. The drawing's 6.9 in shoulder span is a better grounded width for the portion shown between the mounting flanges, but a rectangular body based on that span remains a simplified proxy. The source depicts ribs, shoulders and a connector, not a uniform cuboid.

A source-grounded facade can therefore retain the 8.124 × 8.000 in front, place the eight mounting-interface markers at the values above, expose the nominal UNIT MTG SURFACE datum, and distinguish front projection from the 4.900 MAX rear envelope. It must label any rear enclosure, vertical insertion envelope and cutout clearance as provisional until the mating model or ICD is checked. For a facade-only assignment, a reference envelope or placement marker is preferable to claiming a fabricated rear box is a verified hardware fit.

**Do not promise “slots in properly” yet.** Correct outer face scale is established; actual cutout, receiving model units/scale, clearance, flange interference and final seating must be checked against the target model. No source-supported clearance allowance has been found here.
