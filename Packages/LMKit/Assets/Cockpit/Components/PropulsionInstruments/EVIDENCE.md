# Propulsion instrument evidence

This is a source-guided later-LM reconstruction for the provisional LMKit Panel 1 envelope, not an Apollo 11 configuration or dimensional certification. Original documents are evidence, not build instructions. No live sensor behavior is implemented here.

## Primary sources

- **Grumman Apollo Operations Handbook, LM 10 and Subsequent, Volume I, table 3-1.** [Original scan](https://www.ibiblio.org/apollo/Documents/LMA790-3-LM10-ApolloOperationsHandbookLunarModuleLM10AndSubsequent-Volume1-SubsystemsData-SearchableText.pdf). Complete selected pages are preserved in `evidence/lm10-aoh-vol1-controls-excerpts.pdf`; its manifest records original page numbers, retrieval and hashes. Printed 3-17 through 3-19 correspond to excerpt pages 10–12 / original PDF pages 615–617. The scan contains mixed revisions. The retained panel figure includes LM 8/9 applicability; do not claim LM5 wiring.
- **Andrew J. Farkas, NASA TN D-6722, Apollo Experience Report — Lunar Module Display and Control Subsystem, March 1972.** [Archived primary report](https://apollojournals.org/alsj/tnD6722LMDisplayControl.pdf). Preserved unchanged as `evidence/tnD6722.pdf`, with searchable text alongside. Printed pages 14, 17 and 18 document the T/W mechanical accelerometer, helium readout and propellant readout respectively.
- **AOH Panel 1 illustration**, `evidence/LM-Panel1.jpg`, copied unchanged from the established CrossPointer evidence. It supports face vocabulary and arrangement; no image-derived dimension is treated as surveyed hardware.

## Source-to-artifact decisions

| Artifact | Evidence and interpretation | Implemented limit |
| --- | --- | --- |
| THRUST ENG/CMD | AOH 3-17/18: independent vertical scales 0–100%; ENG chamber pressure calibrated as thrust percentage, CMD throttle command circuitry | Two independent needles. ENG is not derived from force command. The historical CMD minimum/bias and command summation are not reproduced by LMCore's engine-gated force snapshot. |
| FUEL/OXID TEMP | AOH 3-19: selected fuel and oxidizer temperatures, +10 to +100°F | Independent needles; selector and temperature signals unavailable. |
| FUEL/OXID PRESS | AOH 3-19: selected tank pressures, 0–300 psia | Independent needles; selector, pressures and power-failure electrical behavior unavailable. |
| T/W | TN D-6722 p14: mechanical accelerometer with 0–6 lunar-g vertical scale | One independent needle. No gravitational acceleration substitution; no claim a command force/mass ratio is the physical instrument. |
| QUANTITY | AOH 3-18: 0–95% selected usable descent propellant; TN D-6722 p18: two decimal digits each for fuel and oxidizer | Two independent two-digit seven-segment rows. Display capacity 99 is distinct from qualified range 95. No aggregate-mass-to-tank conversion. |
| HELIUM | TN D-6722 p17: one four-digit decimal readout, final digit zero for pressure; temperature uses sign plus three digits | Pressure-shaped four-digit hardware only. Sensor domain unresolved; representational 0–9990 is not a calibrated range. Temperature/sign mode is unimplemented. |

Face labels, tick ranges and independently movable channels follow these sources. Thin rectangular bezels, fonts, lens shapes, seven-segment proportions, cases, screws, scale spacing and arrangement within the allocated slot are reconstruction choices. The compact instrument dimensions are provisional. No claim of original manufacturing geometry, exact EL color/photometry, or verified seated readability is made. The visible inactive red lenses do not imply a modeled electrical failure state.

## Retained assembly evidence

`evidence/AltitudeRate-mounting.json` and `evidence/PanelInventory-inventory.json` are unchanged copies used for numerical clearance checks. They pin the accepted taller AltitudeRate exception. The upper cluster remains inside Panel1__Propulsion; T/W occupies a narrow region to AltitudeRate's right. Preserve the RangeThrust blank and AltitudeRate's independent replacement identity. Root union bounds are unsuitable for placeholder replacement.

See `evidence/SIGNAL_AUDIT.md` for the public snapshot audit, `mounting-validation.json` for measured exported front envelopes, and `artifacts.sha256.json` for retained file hashes.
