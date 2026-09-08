# LM controls and panels: research for an interactive interior

Research date: 2026-09-08. Intended visual baseline: Apollo 11 / LM-5. This is a documented first modeling subset and source map, **not a complete switch transcription or a certified LM-5 configuration**. Most detailed interface descriptions below come from the later LM-10-and-subsequent handbook; their applicability is explicit. Dimensions not located in drawings remain unknown.

## Source records and local evidence

| ID | Source and applicability | What was inspected |
|---|---|---|
| C1 | Grumman **Apollo Operations Handbook, Lunar Module, LM 10 and Subsequent, Volume I, Subsystems Data**, LMA790-3-LM; basic 1 February 1970, change pages through 1 April 1971. [Searchable primary-document scan at Virtual AGC](https://www.ibiblio.org/apollo/Documents/LMA790-3-LM10-ApolloOperationsHandbookLunarModuleLM10AndSubsequent-Volume1-SubsystemsData-SearchableText.pdf). | Downloaded, text searched and relevant pages read; rendered and visually inspected original PDF pages 658, 666, 673, 675, 682, 794. Handbook title applies to later vehicles, but individual foldouts can specify earlier vehicles. |
| C2 | Grumman **Apollo Operations Handbook, LM 5 and Subsequent, Volume II, Operational Procedures**, basic 1 May 1969; supersedes 15 February 1969 issue. [Primary-document scan](https://www.ibiblio.org/apollo/Documents/Apollo%20Operations%20Handbook%20LM%205%20and%20Subsequent%20Vol%20II.pdf). | Downloaded; title and contents inspected. Poor OCR limits automatic procedure lookup. The list of illustrations calls E-1 “LM-4 Cabin Controls and Displays”: a vehicle label must be checked on the actual plate before use. No mission procedure claims below rely on uninspected C2 plates. |
| C3 | NASA **Apollo Experience Report: Lunar Module Display and Control Subsystem**, Andrew J. Farkas, TN D-6722, March 1972. [Primary report](https://www.apollojournals.org/alsj/tnD6722LMDisplayControl.pdf). | Read hardware sections, table I, table II, figures 1–2, printed pp. 1–12. Program-level hardware evidence; not an LM-5 manifest. |
| C4 | NASA **Lunar Module Systems Handbook: LM-5 Through LM-9**, FC027, 17 January 1969, cover revised Change 4 on 2 June 1969. [Schematics extract](https://www.apollojournals.org/alsj/LMSysHandbk.pdf). | Cover and subsystem index inspected. The linked 13-page extract is not the complete handbook. Valuable period-correct schematic lead; do not interpret missing pages as missing spacecraft systems. |
| C5 | ALSJ, Gary Neff, **Cross-Pointer**, adapted from LM AOH Vol. I. [Reference](https://apollojournals.org/alsj/xpoint.html). | Entire page read; supports C1 cross-pointer interpretation. Editorial adaptation, not independent mission configuration proof. |

A durable **41-page complete-page excerpt** of C1 is saved at [references/documents/lm10-aoh-vol1-controls-excerpts.pdf](references/documents/lm10-aoh-vol1-controls-excerpts.pdf). Its [JSON manifest](references/documents/lm10-aoh-vol1-controls-excerpts.manifest.json) maps excerpt pages to **one-based original PDF pages**, records source URL, retrieval date and SHA-256 hashes. It is approximately 7 MB. The large full handbooks were used as working downloads, not added to the repository.

Original C1 SHA-256: `58f51eb2a1c0fe8debc66013af4ae89d9e7a6ca665c74dfb19b43d49281bed95`.

Original C2 SHA-256: `a7381569164fa3caeea546847c3add283892e717818aa78666c1e1b4e9e307cb`.

Printed handbook page references below are authoritative locators within this scan. PDF order is irregular in places and includes blanks and foldouts; do not calculate a constant page offset. C1 p. 3-1 explains that its tables give the placarded name and positions, reference designator, panel, function, breaker, power source, and remarks. That is the right eventual transcription schema.

## Panel map

The following arrangement is documented by **C1 §1.2.2.1.1, printed p. 1-8, original PDF p. 21**. Treat it as later-handbook geometry pending LM-5 structural/photo comparison.

| Panel | Place / purpose | Controls and displays to model as separate objects |
|---|---|---|
| 1 | Commander main panel, left of center at eye level | Warning array, FDAI, cross-pointer, timers, altitude/range meter, thrust display, propulsion quantities and pressure/temperature displays, guidance/engine selections, abort controls |
| 2 | LM pilot main panel, right of center | Caution array, duplicate FDAI and cross-pointer, RCS and ECS monitoring and switches |
| 3 | Center strip below panels 1–2 | Engine/gimbal, radar, stabilization, event timer, RCS heater, lighting controls; one lunar-contact lamp |
| 4 | Center below panel 3 | DSKY and surrounding guidance controls; ACA/TTCA enable switches |
| 5 | Commander waist-level side panel | Descent-rate switch, engine start/stop, +X translation button, mission-timer and lighting controls |
| 6 | LM pilot waist-level panel | DEDA / abort-guidance controls and second engine-stop button |
| 8 | Commander left lower side | Explosive-device controls, audio, heaters; vent controls in later C1 tables |
| 11 | Above panel 8 | Circuit breakers on five angled strips |
| 12 | LM pilot right lower side | Audio, communications, antenna aiming/readout |
| 14 | Above panel 12 | Electrical distribution and power monitoring |
| 16 | Above panel 14 | Circuit breakers on four angled strips |
| ORDEAL | Aft of panel 8 | Orbital-reference controls for FDAI |

C1 documents main panels canted forward 10°, center panels sloping down/aft 45° toward horizontal, panels 8/12 at 15° above horizontal and panel 14 at 36.5°. Breaker rows are angled 15° to sight line so the open-state white band is visible. Main panels use two 0.015-inch aluminum-alloy face sheets separated by two inches with structural channels; these are internal construction dimensions, **not switch protrusion or panel-to-panel spacing**. These facts should anchor a blockout, not substitute for measured panel outlines.

**Foldout warning:** C1 figure 3-2, printed pp. 3-157/3-158, original PDF p. 794, explicitly says **LM 8 and LM 9**. This was checked visually. Its left edge is clipped in the available scan. It shows useful close arrangements of panels 2/3/4/6/12/14/16 and hand controllers, but cannot provide a complete, unambiguous LM-5 texture sheet. It also calls out `PRIO DISP` and `NO DAP` decals near the DSKY. Do not add them to Eagle without LM-5 evidence.

## A first functional modeling set

Implementation ownership is now confirmed: use the user's existing AGC runtime for DSKY semantics, program execution and computer output. The behavior descriptions below are research and validation references for connecting the physical model to that runtime, not instructions to build a second computer state machine. Mechanical animation and non-AGC subsystem behavior remain distinct responsibilities.

All historical behavior in this section is from C1 unless indicated otherwise. The proposed modeling treatments are implementation recommendations, not claims about the original hardware.

### DSKY — panel 4

**Evidence:** C1 §2.1.4.3.2, p. 2.1-77 (PDF 121); figure 2.1-5, p. 2.1-9 (PDF 58); controls tables pp. 3-75–3-79/3-80 (PDF 669–673).

The keyboard has **19 keys**: `0`–`9`, `+`, `−`, `VERB`, `NOUN`, `CLR`, `PRO`, `KEY REL`, `ENTR`, `RSET`. Model separate momentary plungers, not one interactive slab. `PROG`, `VERB`, `NOUN` are two-digit fields. Registers R1/R2/R3 each have five numeric positions and a sign. Blanked fields and flashing VERB/NOUN are actual interface states; a permanent illuminated “88” test pattern is not a normal operating display.

| Input / indicator | Documented meaning | Modeling consequence |
|---|---|---|
| VERB / NOUN | Sets interpretation of the next two numeric characters and clears its respective displayed code | Maintain an entry state machine |
| ENTR | Executes the shown verb/noun command or accepts entered data | Context-sensitive action, not a universal submit to a text box |
| CLR | Clears a data-loading component; repeated clears can traverse register components | Preserve partial input and error states |
| PRO | Proceeds without data; enters standby when appropriate in P06 | Keep distinct from ENTR |
| KEY REL | Releases keyboard/display control to the computer | Permit computer-driven updates and KEY REL flashing |
| RSET | Clears condition indication after the condition is corrected | Do not use it to erase every underlying failure |
| UPLINK ACTY, NO ATT, STBY, KEY REL, OPR ERR | Status/condition indications | Independent indicator regions |
| TEMP, GIMBAL LOCK, PROG, RESTART, TRACKER | Guidance caution/condition indications | Independent illuminated legends |
| ALT / VEL | Landing-radar data-good indication logic in the surrounding panel description | Keep separate from the basic eleven-condition-light count in §2.1.4.3.2 |

**Color conflict to resolve:** C1 figure 2.1-5 calls `COMPTR ACTY` green, while p. 3-78 calls it white. Preserve this discrepancy; use mission-specific hardware imagery/drawing for final emitted color. Figure 2.1-5 and section 3 also differ in their presentation of surrounding ALT/VEL lights versus the core DSKY assembly. Do not turn a count into assumed geometry.

Do not invent mission-correct verb/noun programs from this hardware description. Apollo 11 software/procedure qualification is separate from a working keypad and display prototype.

### DEDA — panel 6

**Evidence:** C1 figure 2.1-7, p. 2.1-11 (PDF 56), and pp. 3-87–3-88 (PDF 681–682).

DEDA is the abort computer's interface and must be a separate asset from DSKY. It has a three-digit **octal address**, a five-digit data field with sign, and `OPR ERR`. Its keys include numeric/sign keys and `CLR`, `READOUT`, `ENTR`, `HOLD`. The address cannot contain 8 or 9. READOUT requests the selected address; ENTR writes the entry to that address. HOLD freezes a changing displayed value and, according to the HOLD row on p. 3-88, pressing that momentary pushbutton again resumes updating. CLR also cancels HOLD while clearing the address/data display. The table limits displayed changing-data updates to two per second. `AGS STATUS` provides OFF, STANDBY and OPERATE states. Model display power separately from key travel and address-entry validity.

### Attitude controller assemblies — ACA

**Evidence:** C1 §2.1.1.3.1, p. 2.1-12 (PDF 55), figure 2.1-9 on p. 2.1-15 (PDF 52), §2.1.4.5.1 p. 2.1-122 (PDF 167).

Each astronaut has a right-hand pistol-grip controller, with a push-to-talk trigger. Forward/aft commands pitch down/up; left/right commands roll; twisting commands yaw. The guide describes proportional rate commands, neutral/out-of-detent behavior and direct/hardover functions. The same ACA can provide incremental landing-point designation in the relevant guidance mode.

Provide a three-axis pivot/constraint hierarchy and a separate trigger, with a documented neutral pose. The selected guidance and attitude-control mode determines the response: moving the stick is not always an immediate vehicle attitude offset. The 0.5° out-of-detent threshold is described in §2.1.4.5.1; do not infer total stick travel from that threshold. Hardover and proportional ranges require the detailed mechanism curves before exact physical stops are locked.

### Thrust/translation controllers — TTCA

**Evidence:** C1 §2.1.1.3.2, p. 2.1-15 (PDF 52); figure 2.1-10, p. 2.1-16 (PDF 51).

The left-hand T-handle has separate translation axes and a THROTTLE/JETS selector lever, plus friction control. It is mounted approximately 45° to a line parallel to the LM forward Z axis. Left/right handle movements command Y-axis translation; inward/outward movements command Z-axis translation. With JETS selected, up/down commands X translation through RCS; with THROTTLE selected, up/down changes descent-engine thrust. The handbook gives 10%–92.5% for controlled descent-engine thrust. Treat this as the documented control range, not a universal thrust curve or display maximum.

Model the T-handle, selector and friction control independently. Preserve the difference between vehicle axes and Blender export axes. The selector changes what vertical handle movement means; it does not disable lateral translation.

### Flight displays and selector dependencies

**Evidence:** C1 pp. 3-16–3-23 (PDF 614–621), pp. 3-55–3-56 (PDF 649–650); C5.

| Instrument | What it shows | Important independent states |
|---|---|---|
| FDAI, commander and pilot | Attitude sphere plus rate and error pointers; selected radar shaft/trunnion angles can replace the relevant error inputs | Ball attitude, three rates, three error pointers, selected source, scale and power |
| Cross-pointer, commander and pilot | Forward/lateral velocity, AGS lateral velocity only, or rendezvous line-of-sight rates | Two pointer offsets, velocity/rate legends, multipliers, red power-failure indication |
| Altitude/range indicator | Range/range rate from rendezvous radar or altitude/altitude rate from selected source | Movable scales/readouts and matching legends; source validity |
| THRUST | Separate ENG and CMD pointers, 0–100% scales | Engine-chamber-pressure response and command response must be separate |
| T/W | Self-contained X-axis accelerometer, calibrated in lunar g | Independent of command needle and display electrical power |

`ATTITUDE MON` selects PGNS or AGS for attitude. `RATE/ERR MON` selects `RNDZ RADAR` or `LDG RDR/CMPTR`. `MODE SEL` chooses `LDG RADAR`, `PGNS`, or `AGS`. `RNG/ALT MON` chooses the altitude or rendezvous presentation. These switches route signals; they do not all choose the spacecraft's controlling guidance system.

Cross-pointer `HI MULT` is ±200 ft/s for velocity or ±20 mrad/s for line-of-sight rate. `LO MULT` is ±20 ft/s or ±2 mrad/s respectively. The illuminated multiplier changes with mode. FDAI `RATE SCALE` uses 25°/s or 5°/s full scale. Do not animate every pointer from one generic velocity vector.

The thrust display has a significant caveat: the manual controller supplies a minimum command; in automatic operation the computer and manual contribution are combined. The commanded indication can be nonzero with the engine off. Build distinct `engineRunning`, `commandedThrust` and `measuredChamberPressure` state, rather than forcing both pointers to zero whenever the engine is stopped. C1 pp. 3-17–3-18 document the command/bias details; a complete propulsion model needs more than this table.

### Engine controls and descent-rate switch

**Evidence:** C1 pp. 3-24–3-25 (PDF 622–623), p. 3-81 (PDF 675), p. 3-87 (PDF 681), and C3 table II / printed p. 10.

`ENG ARM` selects ASC/OFF/DES; `THR CONT` selects AUTO/MAN; `MAN THROT` selects CDR/SE. Treat SE as the historical placard for the other station in this later handbook, not modernize it silently to LMP. Guards/locking actions must follow photographs and mechanical evidence.

`DES RATE` has `+1 FPS`, center and `−1 FPS` positions. A discrete operation changes the commanded descent rate by one foot per second under the appropriate PGNS control. The handbook explicitly associates the plus direction with **increasing thrust** and minus with decreasing thrust. A positive increment is therefore not simply “fall faster.”

`+X TRANSL` is held to command four RCS jets in +X and releases to end that command. Engine STOP exists at both stations. START/STOP response depends on arming and abort logic; the table explicitly mentions exceptions during abort sequence.

**Do not finalize engine button latch animation yet.** C1 p. 3-81 says START remains pressed/illuminated and STOP resets with another press. C3 table II calls START momentary and describes STOP as lock/button return; its narrative says an external latch requiring two reset actions was added to prevent inadvertent restart. Both source statements were inspected, and p. 3-81 was visually checked. Separate electrical latch state, illuminated state and mechanical plunger/guard state. Resolve flight-unit mechanics from a dated drawing or close photograph rather than silently selecting one prose description.

### Warnings, talkbacks, lamp test and landing contact

**Evidence:** C1 pp. 3-19, 3-55 (PDF 617, 649), pp. 3-26–3-27 (PDF 624–625), p. 3-72 (PDF 666); C3 pp. 3–10.

Pressing either MASTER ALARM acknowledges both master lights and silences the tone; it **does not clear the originating caution/warning condition**. The table lists exceptions to the master alarm trigger, including descent quantity and C/W power indications. Build an alarm source state separate from acknowledgement.

The ascent helium-regulator switch example is a useful three-position momentary control: OPEN / center / CLOSE. Returning the switch to center leaves the valve in its commanded state. Its talkback is gray when the valve is open and barber-pole when closed. This is an example, **not a universal mapping for every LM talkback**: each display needs its own documented semantics.

C1 p. 3-72 calls the two LUNAR CONTACT lights red; either probe contact lights the indication and pressing either engine-stop switch extinguishes it. This does not document automatic engine shutdown at contact. Verify Apollo 11 lamp color/placement against mission evidence before texturing.

Lamp test is a rotary selection with separate tests for MASTER ALARM/tone, warning/caution banks, engine pushbutton lights and component/contact lamps. A lamp-test interaction provides a useful initial system demonstration without simulating all underlying failures.

### Timers, lighting, radar and ORDEAL

**Evidence:** C1 p. 3-16 (PDF 614), pp. 3-70, 3-81–3-85 (PDF 664, 675–679), pp. 3-61–3-62 (PDF 655–656), p. 3-62 (PDF 658), pp. 3-152–3-153 (PDF 748–749).

Mission timer counts upward in hours/minutes/seconds to 999:59:59. Event timer can count up/down through minutes and seconds. Slew switches separately address tens and units; documented slew rate is two digits per second while held. Preserve the difference between a spring-return slew switch and a latched run state.

Lighting has distinct flood, annunciator/numeric and integral-panel controls, with overrides. `ANUN/NUM` and `INTEGRAL` should not become one global cabin brightness slider. State can drive separate material emission groups. C1 documents numeric displays and panel markings using electroluminescence, while some pushbuttons/annunciators use incandescent illumination; photographs and lighting tables must define appearance.

Radar controls are tangible interactions worth reserving geometry for: `LDG ANT` AUTO/DES/HOVER; rendezvous-radar selector AUTO TRACK/SLEW/LGC; manual directional SLEW; signal-strength meter and NO TRACK light. Track/no-track is a system state, not merely whether a switch points at AUTO.

ORDEAL has per-FDAI orbital/inertial selections, EARTH/LUNAR power/scale selection, ALT SET, lighting and SLEW/MODE controls. C1 gives ALT SET range 10–310 nautical miles. Keep it as a separate small panel; its angular correction is a display reference-frame behavior, not vehicle rotation.

## Apollo 11 operational cross-check

The [ALSJ landing transcript](https://www.nasa.gov/wp-content/uploads/static/history/alsj/a11/a11.landing.html), around GET 102:45:40-102:45:58, records contact-light callout, shutdown, engine-stop confirmation, ACA movement out of detent, automatic mode selections, descent-engine command override off, engine arm off, and an AGS address-413 entry. This supplies a concrete mission-specific interaction sequence to investigate after the component prototype.

Treat transcript timestamps as voice-event locators, not precise switch-actuation telemetry. The important modeling distinction is that contact indication, engine shutdown, attitude-controller movement and computer entry are separate events. A contact lamp should not implicitly complete the entire landing checklist. The journal combines mission transcript with later editorial explanations; consult the underlying checklist and flight records before implementing exact initial states or timing.

The downloaded Eagle photograph shows blue-looking contact-lamp lenses, whereas C1's later table describes red indications. An unlit lens photograph does not by itself establish emitted color. Preserve lens appearance and emission color as separate evidence fields and resolve the discrepancy before final materials.

## Reusable physical control families

C3 provides a defensible reusable kit: maintained, momentary and locking toggles; detented rotary selectors; pushbuttons with differing return/latch and lighting behavior; continuously variable knobs; moving-pointer meters; mechanical/status flags; numeric displays; warning arrays. Its table I lists roughly 140 toggles, 10 rotary switches, eight large pushbutton switches and 14 potentiometers in the described subsystem. **These are not a complete count of every interactive item in the cabin**: e.g. DSKY keys, breakers and other subsystem hardware must not be omitted by using those totals as a manifest.

C3 says potentiometer mechanical stops limit travel to 300°. Do not apply that stop to every rotary knob: its antenna-command synchro section describes continuous rotation, while detented switches have position-specific travel. Likewise, not every switch is an on/off toggle and not every three-position control holds all three positions.

## Asset metadata proposal

For each eventually transcribed control preserve:

- Stable object ID such as `panel01.guid_cont`; actual reference designator in a separate field.
- Exact placard spelling and all positions, including unlabelled centers.
- Position retention: maintained, spring-return, locking, gated, continuous or unresolved.
- Moving part, pivot, neutral transform, travel limit and guard/cover relationship.
- Display type, emitted legend, color evidence, unpowered appearance and power source.
- Logical output separately from physical pose; source-selection dependencies and annunciator feedback.
- Vehicle/revision applicability, manual printed page, original PDF page and supporting photo/drawing IDs.
- Dimension confidence: drawing-measured, constrained estimate, photo-scaled estimate or unknown.

This is a proposed authoring contract; no app implementation is included in this research.

## Gaps before a high-fidelity panel build

1. Establish a complete LM-5 panel drawing/photo set. The well-indexed later handbook is excellent behavior documentation but insufficient proof for all Eagle labels and positions.
2. Measure exact panel outlines, switch centers, knob diameters, protrusion and guard dimensions from drawings or calibrated photographs. No fabricated dimensions are supplied here.
3. Resolve engine-button physical latch behavior and DSKY activity-light color using flight-unit evidence.
4. Inventory panel 8/11/12/14/16, ECS valves, optical controls and every breaker at item level. They are located in this study but not exhaustively transcribed.
5. Define the modeled mission phase and initial switch state from an Apollo 11 checklist/transcript. A cockpit assembled from mutually incompatible moments can look plausible but behave incorrectly.
6. Validate legends visually at modeling resolution. OCR in both handbooks confuses letters, digits, signs and panel references, and some foldouts are clipped. The supplied excerpt preserves the actual pages for that review.

Recommended first build: both hand-controller types, DSKY, DEDA, one FDAI, one cross-pointer, altitude/range display, engine controls, one representative spring-return valve/talkback, timer controls and lamp-test group. This is enough to test the interaction architecture while retaining clearly documented behaviors; it does not imply the cabin is complete.
