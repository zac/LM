# Source assessment

Research checkout: `ed230a6ee4286bc2385f44bc8f1889bdcc39a8ab` (LM). LMKit starting commit: `d8e35fa3ec8dc400cbb2762c24953022b07e8ebb`. The source manifest hashes the actual research files read, including working-tree research that may not be contained in that LM commit. This component's meshes and scripts are newly authored; no existing Blender geometry was copied.

Primary construction evidence is NASA TN D-7919, *Apollo Experience Report: Crew Station Integration* (1975), printed pp. 7, 10–13. Local full PDF hash and URL are in `source-manifest.json`; a text excerpt and two complete-page visual references are retained here. The retained research notes are secondary navigation/evidence summaries; relative links in those snapshots refer to the original research packet and are not portable asset dependencies.

| Family | Verified source support | Remaining inference |
|---|---|---|
| Maintained toggle | p.10: maintained and momentary distinction, wedge tab handles, luminous tips; nominal 17° ±4° three-position throw | Sizes, attachment thread, exact profile and tip material/color. This is a regular wedge toggle, not the bat-shaped lever-lock design shown in figure 5. |
| Momentary toggle | p.10: spring return; separate end-item indication. Later AOH C1 pp.3-26/27 supplies a valve example | Spring timing/force and precise LM-5 applicability. Mechanism metadata does not implement return animation. |
| Guarded switch | Program requirement for protection of inadvertent actuation; guards/barriers discussed pp.10–13 | **Cage shape, hinge, stops, attachment, clearance threshold and interlock are a proposed generic accessory. No inspected source proves this exact hinged cage was flown on LM-5.** Figure 6 wickets are CM hardware and are not used as proof of LM installation. Exact LM guarded part requires a dated drawing/photo before flight-faithful acceptance. |
| Rotary selector | pp.11–12 / fig.7: circular skirt, pointer grip/indicium; standard 30° spacing | Diameter, height, materials, four positions and ±45° end stops. These are not the 300° potentiometer stops discussed separately. |
| Circuit breaker | p.13: black push/pull knob, aluminum exposed band after deletion of white paint, about 0.5 cm travel, trip-free behavior | Dimensions, exact band chronology for LM-5 and attachment. Do not silently apply the later extended barrier guard introduced for Apollo 12 and later (p.31). |
| Talkback | Later AOH C1 pp.3-26/27: ascent helium valve gray-open / barber-pole-closed example | Aperture, bezel, internal mechanism. Face translation is a presentation technique, not a reconstruction of the flight flag mechanism. Semantic mapping is not universal. |

The Blender authoring basis is consistent with the research checkout's `LM/LMCockpitAssetContract.swift`: target +X right, +Y overhead, -Z forward, meters. Existing calibration constants were inspected for coordinate context only, not treated as measured control dimensions.

No control diameter, depth, mounting aperture, material color or roughness was measured from a calibrated drawing. All such values are provisional design dimensions. Nominal travel values are documented program-level values, not a flight-unit measurement. The later LM-10 handbook examples are substitutions for mechanism research, not Apollo 11 configuration claims. No engine START/STOP latch behavior is asserted; the research documents conflicting descriptions.

The source pages retain their source identity. No blanket license is asserted for the research packet or underlying historical photography. Material appearance is a neutral preview; luminous tips are modeled as non-emissive surfaces because luminance calibration is absent.
