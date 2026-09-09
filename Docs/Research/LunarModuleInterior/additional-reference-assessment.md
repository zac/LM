# Additional reference assessment — 2026-09-08

The user supplied a controls-and-displays PDF and two NASA collections. These warrant a focused component reference check, not a delay to all modeling.

- [Legacy NASA collection](https://www.nasa.gov/history/diagrams/apollo.html) and [current NASA gallery](https://www.nasa.gov/gallery/project-apollo-technical-diagrams/) substantially overlap. The dossier already contains `ad013.gif` (LM controls), `ad016.gif` (forward interior), and `ad017.gif` (aft interior).
- NASA attributes [ad013](https://www.nasa.gov/image-detail/ad013/) to the Apollo Spacecraft News Reference; its download is 3000 × 1523 pixels. The interior views are attributed to the 1972 Apollo Program Press Information Notebook. Publication/gallery dates do not establish LM-5 applicability.
- The [user-supplied PDF](references/documents/user-lunar-module-controls-and-displays.pdf), originally `/Users/zac/Downloads/Lunar Module Controls and Displays.pdf`, is one page containing a 10943 × 5310 grayscale JPEG, with no extractable text. It was visually inspected as a full-page render. It provides a larger raster for inspecting panel inventory and legends; small lettering still needs close inspection. It is not a vector drawing or a dimensioned mounting plan. Its mission and revision are unconfirmed, and identity with NASA ad013 has not been established.
- The PDF covers the main panels, side equipment, breaker banks, ORDEAL, optics and hand controllers. Use it to reconcile component inventories, then cross-check legends and behavior against the selected handbook revision and Apollo 11 photographs. Do not infer physical dimensions from PDF page size.
- The collections also contain Command Module panels and launch/exterior diagrams. Those are not prerequisites for this LM cockpit assignment.

Before dependent components are built, freeze each component's mounting datum, envelope, hierarchy and selected visual revision. DSKY can begin using the existing application geometry as its compatibility baseline while checking the cited MIT drawings. FDAI can begin with the existing ball asset. Panel workers should reconcile panel-specific labels before final texturing. Cabin workers should use installed forward/aft views rather than treating the flattened panel inventory as cabin geometry.

No new historical dimensions or verified LM-5 switch transcription are claimed by this intake. The PDF is source evidence, not instructions to the implementation agent.
