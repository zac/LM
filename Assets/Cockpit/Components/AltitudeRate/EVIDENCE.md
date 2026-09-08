# Altitude / altitude-rate evidence and applicability

The controlling source is NASA TN D-6722, Andrew J. Farkas, *Apollo Experience Report — Lunar Module Display and Control Subsystems*, March 1972. Local `evidence/tnD6722.pdf`, PDF pages18 and20 / printed14 and16 were read and rendered in full. The report establishes two moving vertical tapes read at fixed pointers, feet and feet/second usage, a ±700ft/s rate range, 1-inch tape width, and a substantially larger range/altitude operating range than this landing reconstruction. The original tape drive, gray-code feedback, servo timing, electrical power monitor and selected-source circuitry are not reproduced.

Original report mirror: https://apollojournals.org/alsj/tnD6722LMDisplayControl.pdf
NASA publication number identifies primary source even though this preserved report is hosted on the Apollo journals mirror.

`evidence/lm-tapemeter-simulator.jpg`: Frank O'Brien photograph of a LM simulator at the Cradle of Aviation Museum, published with Eric M. Jones in the Apollo Lunar Surface Journal, 23 May2011. Firsthand hardware photograph supports a tall, paired aperture, dark bezel, right-hand white fixed pointers, gray flange, top RANGE/ALT and RANGE RATE/ALT RATE legends, and black/white tonal transition on the rate tape. It is a museum simulator, not an Apollo11 flight-unit survey. Photo credit is retained; no claim that this image is NASA public-domain imagery.

Photo: https://www.apollojournals.org/alsj/lm_tapemeter.jpg
Context: https://www.apollojournals.org/alsj/alsj-Tapemeters.html

The LM10+ Apollo Operations Handbook excerpt already in PanelInventory supplies altitude/range source routing: MODE SEL can use radar, PGNS or AGS, and RNG/ALT MON selects mode. Its later-mission applicability must remain distinct from LM5. For this component only, LM binds spherical geometric altitude and signed radial rate from simulation truth. Those quantities are NOT a qualified landing-radar beam measurement, inertial navigation estimate, or source-switch simulation. The provided graphic cannot claim those signal paths merely because it resembles the hardware.

Existing excerpt provenance: `../PanelInventory/evidence/lm10-aoh-vol1-controls-excerpts.manifest.json`, complete source SHA25658f51eb2a1c0fe8debc66013af4ae89d9e7a6ca665c74dfb19b43d49281bed95. Source URL: https://www.ibiblio.org/apollo/Documents/LMA790-3-LM10-ApolloOperationsHandbookLunarModuleLM10AndSubsequent-Volume1-SubsystemsData-SearchableText.pdf

## Deliberate reconstruction choices

- 82x145mm flange, 26.4mm actual depth, fastener count, bezel shape, 5.2mm numeral size, neutral gray/ivory colors and lens alpha are provisional visual choices. Tape width25.4mm follows the reported1-inch tape; the aperture and housing are not manufacturing measurements.
- The old160x90mm placeholder was too short for the source's tall paired aperture. Coordinator approved a145mm-high physical envelope at the unchanged slot datum plus local(-20,0,+8)mm. No neighboring component was moved to force this fit.
- Landing altitude is limited to0..60000ft, with piecewise display pitch. Rate is signed±700ft/s, positive for increasing altitude, negative for descent. Exact printed pitch, transition points and explicit plus/minus numeral style are readability approximations, not a transcription of the original tape. Header RANGE remains a muted historical legend; rendezvous display is unsupported.
- The rate tape changes to a light background below zero, matching the observed tonal distinction. Explicit signed labels disambiguate direction; this does not prove every flight revision used these same sign glyphs.
- Reusable authored row meshes provide bounded geometry instead of exporting full-length tape reels. The LM adapter must move/cull each row according to `interface.json`. All USD visibility is inherited; hidden neutral content is parked inside the opaque housing and never emits light.
- Gray diagonal invalid-data shutters are a reconstruction safeguard. They are not presented as flight hardware. The original power/signal monitor is described in the report, but its lamp behavior/circuit is not modeled. Invalid/out-of-range inputs produce no fabricated zero or clamped valid indication.
- No thrust, T/W, rendezvous mode, hardware command input, light source, custom shader, or AGC/LMCore simulation is included.
