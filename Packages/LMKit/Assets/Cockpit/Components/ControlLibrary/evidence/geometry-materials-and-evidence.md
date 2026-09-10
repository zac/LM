# Cabin geometry, materials, and evidence

Research date: 2026-09-08. Target: an Apollo 11-inspired interior with individually documented substitutions. These notes support modeling; they do not certify an exact reconstruction of LM-5.

## Establish the crew stations before detailing panels

The forward compartment has a curved shell and two closely spaced flight stations. Its center instrument stack, lower controls, side consoles, windows, armrests, restraints, and hatch constrain each other. Build that arrangement first. A flat wall of controls will lose the relationships that make the cabin recognizable and usable.

NASA's Apollo 11 press kit describes the forward crew compartment as 92 inches in diameter and 42 inches deep, with a 32-inch square inward-opening forward hatch. It lists 160 cubic feet of habitable volume, while its broader cabin-volume description uses 235 cubic feet. These are different measures, not alternate cube dimensions. The 42-inch depth describes the forward compartment, not the complete pressurized interior including the midsection. [Apollo 11 press kit, printed p. 96, PDF p. 100](https://www.nasa.gov/wp-content/uploads/static/apollo50th/pdf/A11_PressKit.pdf#page=100)

The 1967 Grumman training guide supplies additional geometric references. It predates Apollo 11 and cites LM-2 documentation. Treat it as an early design basis to reconcile against LM-5 photos and procedures. Its historical panel assignments must not silently override a later flight handbook. [Grumman course 30915, 15 February 1967](https://www.ibiblio.org/apollo/Documents/lm_structures_study_guide.pdf)

| Feature | Documented value | Source and locator | Modeling qualification |
|---|---|---|---|
| Forward cabin diameter | 92 in = 2.3368 m | Apollo 11 press kit p. 96; Grumman printed p. 17, PDF p. 25 | Overall nominal dimension, not unobstructed shoulder room |
| Forward cabin depth | 42 in = 1.0668 m | Same | Excludes the complete aft cabin layout |
| Flight-station spacing | 44 in = 1.1176 m | Grumman p. 17, PDF p. 25 | 1967 design reference, not a measured LM-5 survey |
| Compartment deck | Approximately 36 by 55 in = 0.9144 by 1.397 m | Grumman p. 27, PDF p. 35 | Approximate outline; check which direction belongs to each side in plan drawings |
| Main panels 1 and 2 | Canted forward 10 degrees | Grumman p. 27, PDF p. 35 | Early training description; datum and sign need drawing interpretation |
| Lower center panels 3 and 4 | Slope down and aft 45 degrees toward horizontal | Same | Do not copy a flattened panel diagram as their installed transform |
| Lower side-console tier | 15 degrees above horizontal | Same | 1967 basis |
| Middle side-console tier | 36.5 degrees above horizontal | Same | 1967 basis |
| Forward hatch | 32 in square = 0.8128 m square | Apollo 11 press kit p. 96 | Opening nominal size; frame, latch and swing geometry need separate reconstruction |
| Forward window triangle | 25, 28, 24 in sides = 0.635, 0.7112, 0.6096 m | NASA TN D-7439 p. 9, PDF p. 14 | Pane size, not an instruction to make a facade-aligned opening |
| Window visibility | Approximately 65 degrees down, 80 degrees outboard | NASA TN D-7439 p. 9 | Visibility envelope, not pane orientation angles |
| Overhead docking window | Approximately 5 by 13 in viewing area | NASA TN D-7439 p. 9 | Inner pane curved to match cabin, unlike flat forward panes |
| Commander's flight design eye | Body stations X 279.25, Y 22, Z 54 in | Grumman T30915-39, printed p. 35, PDF p. 43 | Absolute body stations, not Blender coordinates or height above the deck |

Conversions above use exactly 0.0254 meters per inch. Original nominal or approximate precision remains unchanged by conversion. The [measurement ledger](measurements.csv) makes these values available without retyping.

The two forward windows each have an inner structural pane and a protective outer pane, with a cavity vented to the exterior. NASA describes their planes as oblique to the vehicle axes. The overhead docking window is above the commander. [NASA TN D-7439, pp. 8-9](https://ntrs.nasa.gov/api/citations/19730023038/downloads/19730023038.pdf#page=13)

The existing project already implements a two-pane landing-point designator and a source-based commander eye datum. Preserve that work as the integration starting point. Its 20 mm inter-pane separation is explicitly provisional; its reconstructed corner rays come from readings of the visibility plot. App validation tolerances do not make those inputs flight measurements. See [CommanderWindowCalibration.md](../../CommanderWindowCalibration.md) and the [asset pipeline review](blender-usdz-visionos.md).

## Visual anchors saved with this research

These are rendered source pages, not new engineering drawings. The Grumman pages are 1967 training figures. Retain their captions and orientation when tracing. In particular, T30915-38 says the LPD is shown looking inboard; tracing it without checking viewpoint can mirror the markings.

![NASA crew station arrangement](references/figures/crew-station-arrangement.jpg)

NASA TN D-7919 figure 2, printed p. 6, local NTRS PDF p. 14. This identifies the center stack, side tiers, hatch, restraints, windows, and overhead equipment. It is a general configuration drawing, not an LM-5 closeout photograph. [NASA report](https://ntrs.nasa.gov/api/citations/19750012347/downloads/19750012347.pdf#page=14)

![Grumman commander eye reference](references/figures/grumman-flight-design-eye.jpg)

Grumman T30915-39, January 1967, printed p. 35, original PDF p. 43. The printed station coordinates are stronger evidence than distances inferred from the drawn outline. [Original guide](https://www.ibiblio.org/apollo/Documents/lm_structures_study_guide.pdf#page=43)

![Grumman window and LPD](references/figures/grumman-lpd-window.jpg)

Grumman T30915-38, January 1967, printed p. 36, original PDF p. 44. The sectional drawing shows inner and outer panes and coatings but does not provide a usable numerical pane-separation dimension. [Original guide](https://www.ibiblio.org/apollo/Documents/lm_structures_study_guide.pdf#page=44)

Additional saved pages: [main panels](references/figures/lm-main-panels.jpg), NASA TN D-7919 figure 3, printed p. 7, local PDF p. 15; [commander side](references/figures/grumman-cdr-side.jpg), Grumman T30915-36, printed p. 29, original PDF p. 37. The general drawings establish relationships; use the mission-tagged photo catalog and handbook tables for lettering and installed hardware.

## Material and lighting research

The cockpit should distinguish painted structure, panel legends, luminous display areas, metal hardware, transparent panes, soft controller boots, restraints, and stowed equipment. Their exact roughness and colors still need photo comparison. A scan's yellow paper, a photograph's exposure, or a museum's room lighting is not a spacecraft material sample.

NASA's lighting report describes white instrument/nomenclature lighting, green alphanumeric readouts, red warning indications, and yellow caution indications. This is a general system description, not a palette to apply to every lamp. Individual lights can differ; determine each from its control entry and photo. The report distinguishes integral electroluminescent lighting from incandescent LM floodlighting. [NASA TN D-7290, printed p. 6, PDF p. 9](https://ntrs.nasa.gov/api/citations/19730017160/downloads/19730017160.pdf#page=9)

Its LM floodlight layout has one overhead unit above each of panels 1 and 2, one forward unit above each of panels 5 and 6, and 31 side-panel lights. Overhead and forward units can dim; side-panel lights cannot. This is a useful design reference for a controllable cabin-lighting study. It is not proof that every fixture is visible or modeled in the photographs selected here. The adjacent fluorescent-lamp discussion is about the command module and must not be copied into the LM. [NASA TN D-7290, printed p. 11, PDF p. 14](https://ntrs.nasa.gov/api/citations/19730017160/downloads/19730017160.pdf#page=14)

The report also describes two portable LM utility lights with clamps and cables, with different illumination levels for commander and LMP. These are separate props rather than baked light spots. The report's photometric units are historical measurements; converting them into renderer parameters and matching headset exposure is a later validation task. [NASA TN D-7290, printed p. 14, PDF p. 17](https://ntrs.nasa.gov/api/citations/19730017160/downloads/19730017160.pdf#page=17)

Recommended material studies are a daylight-only cockpit, low integral lighting, and full cabin lighting. Use them to check that labels remain readable, dark panel recesses retain depth, and the windows do not produce distracting double reflections. These are proposed authoring tests, not reconstructed Apollo 11 exposure settings.

## Mechanical details that should survive modeling

NASA describes maintained and momentary toggles, lever locks, protective guards, detented rotary controls, continuously variable controls, and protected circuit breakers. Breaker recesses and barriers mattered because crew equipment could strike exposed hardware. These distinctions affect animation and interaction as well as silhouette. [NASA TN D-7919, printed pp. 7-13](https://ntrs.nasa.gov/api/citations/19750012347/downloads/19750012347.pdf#page=15)

Build separate moving parts for switch levers, guards, keys, knobs, breaker plungers, indicator mechanisms, needles, and the FDAI ball. Keep panel faces, bezels and fixed indices stationary. Do not give every toggle the same travel or make every guarded control a one-step tap. Exact per-control detents, spring return, and electrical meaning belong in the control inventory.

Armrests, restraints, controller pedestals, and glareshields deserve geometry before small fasteners. They establish where hands and bodies can move. The manual drawings describe pressure-suited operation; the headset user's reachable space still requires testing. A seated accessibility mode can reposition the experience while keeping the historical geometry intact, but should be identified as an application mode.

## Drawing archive leads and what was actually verified

Virtual AGC hosts original Apollo engineering scans and a searchable assembly hierarchy. The Apollo 11 LM hierarchy identifies G&N configuration 6014999-091 and DSKY assembly 2003994-091. This was verified in the archive index; the complete assembly drawing was not dimensionally inspected during this lane. The current repo already cites DSKY outline drawing 2003956 Rev B, so a future DSKY modeling pass should reconcile that drawing with the existing geometry instead of starting from a museum photo. [Apollo 11 G&N assembly hierarchy](https://www.ibiblio.org/apollo/6014999-091.html)

The [Grumman drawing archive](https://www.ibiblio.org/apollo/ElectroMechanical.html#LEM) identifies LDW280-54000 as a top-level LM-4 through LM-9 lead, with uncertainty in the archive's own applicability description. The downloaded [drawing master index](https://www.ibiblio.org/apollo/LemDrawingIndex.tsv) contains 41,000-plus rows in this snapshot, mostly earlier scanned boxes. Searches for cockpit display-panel titles did not yield an immediately usable complete dimensional drawing set. This is not evidence that such drawings do not exist.

One specific lead is LDW1018-20 Rev B, sheet 1, titled OUTLINE LEM TIMER, noted as Curtis Instruments drawing 10283. Its [archive frame](https://archive.org/stream/apertureCardBox502NARASW_images#page/n1945/mode/1up) is indexed but uninspected. Treat it as a follow-up lead, not a source of dimensions already established here.

## Source archive and limits

The local [documents folder](references/documents) contains complete NASA display/control, lighting, and window reports. The Grumman excerpt preserves original PDF pages 1-2 and 25-46, in that order. Thus excerpt pages 3-24 correspond to original pages 25-46; citations above always use original PDF page numbers. Its original source was a 60 MB scan; only the relevant excerpt is retained in this packet.

The LM-5 structures handout was also inspected at its [NASA source](https://www.nasa.gov/wp-content/uploads/static/history/alsj/a11/a11LM5structures.pdf). Despite the useful mission-specific title, its 61 pages focus on structures, thermal protection, landing gear, and surface-equipment deployment. It does not replace the cabin control drawings and was not added as a full local duplicate.

Remaining limits: no exact complete panel boundary survey, no complete LM-5 switch-by-switch transcription, no measured pane cavity, no calibrated material colors, and no fabricated claims of Blender export or Vision Pro testing. The next work should resolve these specific gaps while building a small representative control panel.
