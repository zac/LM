# Research backlog and stopping point

Research date: 2026-09-08. The first pass is sufficient to begin a source-tagged blockout and a representative control prototype. These gaps should guide further research instead of another broad image search.

| Priority | Open question | Current evidence | Next action and completion condition |
|---|---|---|---|
| 1 | Exact LM-5 panel inventory at the chosen mission phase | Eagle photos, LM-5 procedures, later system handbook tables | Select baseline revision and phase; transcribe every control on panels 1-6 with a readable source crop and state table. Identify all substitutions. |
| 1 | Exact installed panel geometry | 1967 nominal angles and size, arrangement drawings, preflight photos | Find dimensioned assembly drawings or fit multiple photos against known datums. Record residuals and uncertainty; do not label a perspective estimate measured. |
| 1 | Commander window pane separation | Two-pane source sections; existing provisional 20 mm | Find a dimensioned production section or calibrated artifact survey. Reconcile with the existing optical contract before changing it. |
| 1 | Imported control ownership | Current app validates names but keeps separate procedural controls | Choose binding ownership; test DSKY key input, ACA, ROD and instrument readouts on the imported model. This is future implementation work. |
| 1 | Dense-panel input on Vision Pro | Apple input-target and target-spacing guidance | Prototype adjacent switches and breaker rows at actual scale; measure wrong-control activation and reach on device. Choose direct manipulation or a contextual native precision interface where necessary. |
| 2 | DSKY exact face, key and mount dimensions | Current code cites 2003956 Rev B and 2003994-091; archive hierarchy verified | Inspect the original outline and assembly sheets; distinguish dimension callouts from digitized centers and compare against code. |
| 2 | ACA/TTCA physical pivots, travel, stops, boots and hand switches | Control handbook descriptions; photos and NASA hand-controller report lead | Inspect NASA TN D-7884 and original component drawings. Reconcile model limits with the selected control mode and existing simulation. |
| 2 | Side console panels 8/12/14 and breakers 11/16 | Flat diagram and oblique photos | Capture readable mission-tagged rows and dimensions. Include breaker labels, amperages where legible, guard spacing and plungers. |
| 2 | ECS exact knob inventory for the chosen cabin | Excellent LM-11/LM-12 closeouts; operations handbook | Resolve labels against a matching schematic/table. If retained in Eagle-led model, list the later configuration at component level. |
| 2 | AOT and DEDA detail | Handbook overview and general drawings | Obtain clear faces and side views; transcribe AOT rotary positions and DEDA input workflow before implementing their behavior. |
| 2 | Lamp, talkback and power behavior | Handbook states, NASA hardware reports | Record lamp tests, off/unpowered appearance, transition behavior, guard relationships and circuit dependencies per control. |
| 2 | Material colors and luminous appearance | Color flight frames, monochrome lit panel, lighting report | Compare several exposures and known materials. No scanned color should become an unqualified paint/PBR value. Qualify emission in the target renderer. |
| 3 | Hatch latch mechanism and cabin clearances | 32-inch nominal forward hatch, aft/preflight/closeout imagery | Obtain latch/hinge drawings or detailed imagery. Validate travel without penetrating nearby equipment. |
| 3 | Museum panorama reuse | LM-2 collection record and panorama page | Inspect the panorama and resolve its own media rights if importing it. Collection CC0 status does not automatically resolve panorama media status. |
| 3 | Complete stowage at a selected moment | Preflight and flight photos depict different arrangements | Choose descent-ready, surface-stay or museum/exploration state; source that configuration before dressing the entire cabin. |

## Source conflicts retained

- The 1967 guide's panel assignments and construction text predate LM-5. Use it for qualified geometry, not as a universal label atlas.
- The later operations handbook contains a foldout explicitly marked LM-8/LM-9. Its cover date alone does not establish that figure's applicability.
- NASA and ALSJ give different timing context for AS11-36-5390; the photo catalog preserves both.
- NASA migrated ALSJ image links often returned 404. The catalog records successful Apollo Journals copies as distinct retrieval sources.
- NTRS and NASA-hosted PDF versions can have different front matter and page offsets. Local page citations must refer to the exact archived file.
- Smithsonian LM-2 is a ground article modified to resemble Eagle. It is not a flown Apollo 11 interior.

## Searches and review performed

The parallel research covered NASA/Grumman control handbooks, Apollo 11 procedures, ALSJ imagery and later closeouts, NASA crew-station and lighting experience reports, structural/window geometry, and official Blender/OpenUSD/Apple asset documentation. The local LM app was read to identify existing geometry and binding contracts.

Specific geometry searches included LM-5 structures, crew-station displays and controls, spacecraft windows, lighting considerations, the Grumman structures study guide, and the Virtual AGC engineering-drawing index. The LM-5 structures handout proved mostly exterior/structure oriented. A targeted scan of the available Grumman master index did not establish a complete cockpit production-drawing set. The timer outline remains a lead.

Original image files were inspected by the imagery researcher. The coordinating pass independently checked the Apollo 11 forward-panel image, NASA control inventory diagram, and all five saved geometry/control figure renders. Detailed manual pages and applicability notes were reviewed in the controls lane. These checks support source selection and the notes; they are not visual verification of a new model.

Stop condition for this pass: each major work area has a usable source route, consequential limitations are recorded, and additional broad searches would add less value than the targeted measurement and transcription tasks above. Continue with those tasks when preparing the first Blender components.
