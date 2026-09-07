# Moon Explorer one-zoom plan: window, immersion gate, streaming

Self-contained work plan. `LandAnywhereMoonPlan.md` remains the controlling
plan; this document supersedes the **Presentation decision** in
`MoonExplorerExperience.md` (the explicit Globe / Surface mode split) and the
zoom clamps that implement it. All terrain, source, residual, contact and
Apollo capture contracts stay in force. Written 2026-09-06 against `739a0e5`.

**Vision:** one continuous zoom from the whole disk to 0.125 m terrain. The
viewer looks at the Moon through a window in their room. Zoomed out, the disk
fits inside the window. Zooming in grows the sphere and the frame clips it.
Past the existing handoff the regional terrain replaces the sphere, still
behind the window, and the same zoom continues to the surface. An Immerse
control, available only once the globe is gone, opens full immersion; inside,
zoom-out stops at the handoff width, and leaving immersion restores the window.

## 0. Status board (update when you land work)

| Step | State | Notes |
|---|---|---|
| 1 Window container and immersion gate | Complete in Simulator | 54 focused tests; 11 byte-identical Apollo captures; seven-stage portal journey including partial opacity. Physical gates remain open. |
| 2 One camera model and gesture set | Implemented; visual/device gates open | `4c8bd2a`: camera/gestures, 61 focused tests. Separate final Apollo adapter: 65 tests, 11/11 byte-identical ladder, eleven-stage journey and five exact restore cycles. Shared camera/ENU uses source-derived coverage bounds. Close-view faceting and physical acceptance remain open. |
| 3 Scene stepping off the observation graph | Complete in Simulator | 63 focused tests; 11 byte-identical Apollo images; seven-stage portal journey; five restore cycles exact. Over-60s sample shows no SwiftUI update loop. Physical lifecycle/pacing gates remain open. |
| 4 Coarse-first terrain and prefetch | Not started | §4 |
| 5 Sliding region | Not started | §4 |
| 6 Tiled globe imagery | Not started | §4; revives the original W2 design |

### Owner review follow-up, 2026-09-07

The owner authorized A–F in order, with Simulator performance as a landing
gate. Freeze the preceding Release app and compare the seven-stage journey
and five-cycle restore soak for each item. D/E also require the matched
highland dive. A regression in hitch count or lifetime peak needs an actionable
explanation and remains unlanded until resolved. All physical gates stay open.

| Item | State | Gate |
|---|---|---|
| A Relief lighting and sun-dependent radiance | Withheld: performance gate | Lighting candidate retained under A/implementation.patch; matched journey peak and hitch regressions prevent landing |
| B Free-standing disk and smaller portal | Withheld: memory gate | Corrected switch and 11 Apollo images pass; journey peak +1.203 MiB. Patch retained; next experiment is lazy portal realization |
| C Height-field gesture anchor | Withheld: performance gate | 0.0184 ms pick and about 64 MiB lower retained footprint; matched lifetime peaks rise, patch retained |
| D Coarse-first terrain, plan Step 4 | In implementation | Highland warm/cold dive, per-level/build costs, no hitch regression |
| E Tiled globe imagery, plan Step 6 | Not started | Half lifetime peak, disk PSNR, sharper overlap, Apollo identity |
| F Sliding region, plan Step 5 | Waiting for D and E | 100 km pan, final contact equals rendered |

## 1. Evaluation of the branch at `739a0e5`

The branch does not need a fixing pass before this pivot. The problems worth
acting on are structural, and the two-mode split causes most of them.

Keep unchanged:

- Coordinate authority, the 4,096 m floating origin and rigid-only frame
  transforms (`LMLunarFloatingOrigin`, `LMLunarFrameTransform`).
- The globe-to-site handoff: scale matching, radiance matching, foreground
  projection, opaque endpoints (`LunarExplorerSession.globeSiteBlend`,
  `LunarExplorerScene.updatePresentationTransform`). Reuse it inside the window.
- Atomic generation publication and the morph in `LMLunarTerrainPresentation`.
- The eleven byte-identical Apollo captures as the regression anchor.

Fix as part of this plan:

- **Bug: the giant sphere is reachable today.** In Surface mode a pinch or the
  Settings scale slider can zoom out past 120 km across; the blend then shows
  the whole globe at 2.17 m in full immersion, the outcome the mode split was
  built to prevent. The window makes this impossible by construction.
- **Bug: heading changes rebuild terrain.** Below 250 m altitude the corridor
  plans depend on heading (`LMLunarTerrainPresentation.plans`,
  `LunarExplorerScene.requestProgressiveTerrain`), so drag-to-rotate can start
  tile generation on every gesture frame. Quantise heading for planning to
  15° with hysteresis and re-plan only when the gesture ends.
- **Structure: two products in one scene.** `isExplorerExperience` forks
  behaviour in about fifteen places across session, scene, view and browser.
  Make the product path the only path; express capture launches as
  configuration of it.
- **Structure: Apollo 11 is a different camera.** The bundled site keeps a
  planar frame, a 900 m pan limit, a lower presentation height and its own
  focus offsets (`usesBundledSite`). Fold it in as the first site pack inside
  the global frame, as `LandAnywhereMoonPlan.md` already intends.
- **Structure: scene stepping inside the RealityView update closure.** Four
  SwiftUI update-loop hangs were fixed by equality guards on diagnostics.
  Continuous gestures mutate state every frame. Drive the scene from a
  `SceneEvents.Update` subscription reading a session snapshot.
- **Structure: zoom is a stops table.** `exploreZoom` interpolates width,
  altitude and tilt between named presets. Replace it with one camera model.

Out of scope here: the in-progress mesh reuse and sample cache
(`66d91bb`, `739a0e5`) are left alone. The monolithic 64 ppd sphere texture
is a memory problem but is a separate step (§4 step 6).

## 2. Key finding

The continuous zoom already exists. The capture and inspection path
(`isExplorerExperience == false`) zooms from the `globe` preset through the
crossfade at 240 km to 120 km across down to surface tiles, and has been
validated at Apollo 11 (`Tools/CaptureLunarExplorerZoomLadder.sh`) and at a
highland site (`Stage2GlobalTerrainValidation.md`). The Explorer product
deliberately does not use it: the Globe / Surface picker was chosen so a pinch
could never fill the room with a sphere. A clipped window answers that concern
without splitting modes, so this pivot is mostly presentation and interaction
work, not new terrain machinery.

## 3. The unified model

### 3.1 Container

None of the three visionOS mechanisms that hold a world gives a soft feathered
edge around arbitrary geometry as a stock feature. That effect belongs to
spatial photos (`ImagePresentationComponent`) and to progressive immersion.

| Container | Edge | Gains | Costs |
|---|---|---|---|
| **Portal in the existing mixed ImmersiveSpace (recommended)** | Hard, any shape; optional inner darkening vignette | Smallest delta. Keeps the oblique camera the terrain LODs are tuned for. Head movement gives parallax through the frame. One binding switches the same space to full immersion. | Still a Full Space; no walk-around globe. |
| Volumetric window in the Shared Space | Hard box clip at volume bounds | Coexists with other apps, system move/resize, walk-around globe, tilt from head position | Diorama view loses the low oblique views; volume size caps the window; immersion needs a second space. |
| Progressive immersion bubble | Feathered, stock, Digital Crown | The one free soft edge to passthrough | View-centred bubble, not a window at the globe. Use as the immersive step. |

Decision recorded here as a recommendation, owner may override: portal for the
window; immersion offered as `.progressive` so the crown dials from bubble to
full, with the Immerse control jumping straight to full. A true feathered
window edge would be an opacity fade on terrain materials near the frame via a
ShaderGraph material. That conflicts with the opaque-only and byte-identical
Apollo material contracts; treat it as a separate, gated experiment.

Mechanics: `PortalComponent(target:clippingMode:crossingMode:)` (visionOS 2)
on a rounded-rectangle portal mesh with `PortalMaterial`; `WorldComponent` on
one world entity that holds `globePresentationRoot` and `presentationRoot`.
Keep the existing fixed-depth sphere placement
(`globeSurfaceDepthMeters`), so the nearest surface sits at the portal plane
and the frame clips the sphere as it grows. Crossing mode stays off; a
free-standing globe at full zoom-out is optional polish, not the first cut.

### 3.2 Immersion gate

- Immerse is enabled only when `metersAcross <= globeSiteBlendEndMetersAcross`
  (120 km), that is once the sphere has fully handed off.
- Entering immersion sets `immersionStyle` to `.full` (or `.progressive`) and
  disables the portal so the world renders directly.
- Inside immersion, zoom-out clamps at 120 km across. There is no path to the
  globe without leaving immersion.
- Leaving immersion restores `.mixed`, the portal and the zoom-out range.

### 3.3 Camera and gestures

- State: focus coordinate, altitude, heading, tilt. Width across the window
  derives from altitude and window size. Presets become named altitudes.
- Tilt is a smooth function of altitude: 0° at globe scale easing to the
  current preset angles, so a dive from the disk arrives in the Orbit framing
  without a discontinuity. This already exists on the capture path.
- Pinch: altitude, logarithmic, anchored at the gaze point so the place under
  the hand stays put. No floors other than 1.5 m altitude; the 3,400 km browse
  floor and the 5,000 km ceiling remain only as the disk-fits-window bound.
  Owner-approved boundary rule (2026-09-07): when zoom-out makes the fixed
  pinch ray miss the whole disk, smoothly release the anchor at the limb.
  Keep the fixed sphere depth and full zoom range; do not translate the
  sphere sideways or introduce another zoom floor.
- Drag: above the handoff, great-circle drag on the sphere (exists as
  `rotateGlobe`). Below it, pan in metres per point scaled by width (exists as
  pan mode). The Rotate / Move picker goes away.
- Resident source bounds remain in force. Apollo's 2,048 m measured contact
  tile needs its existing 128 m collar; the pack now supplies those bounds
  relative to the focus landmark. Removing the old 900 m camera-mode constant
  does not authorize panning into missing contact data. Region replacement
  beyond that footprint remains Step 5.
- Two-hand rotate (`RotateGesture`): heading. Planning quantises it (§1).
- Tilt gesture: later. Candidates are a vertical component of the two-hand
  gesture or a small ornament. The portal already gives parallax when leaning.

### 3.4 Zoom ladder

Widths and thresholds are the current presets and blend constants, unchanged.
LOD is selected by altitude, not width.

| Width across | State | Terrain resident |
|---|---|---|
| 5,000 km – 240 km | Globe, 64 ppd map, window | none required |
| 240 km – 120 km | Handoff crossfade, window | 512 m tiles must be ready |
| 120 km – 24 km | Terrain, window or immersion | 512, 128, 32 m |
| 24 km – 700 m | Terrain | 8, 2 m |
| 700 m – 8 m | Terrain | 0.5, 0.125 m |

## 4. Steps and gates

1. **Window container and immersion gate.** One world entity behind a portal
   mesh in the existing mixed space. Reuse the fixed-depth sphere placement
   and the crossfade unchanged. Add Immerse, the in-immersion zoom-out clamp,
   and remove the Globe / Surface picker and the 3,400 km browse floor.
   *Gate:* the eleven Apollo captures stay byte-identical on the capture path.
   A journey capture shows disk, clipped sphere, handoff, terrain, immersion
   and return with no mode switch.
2. **One camera model and gesture set.** Altitude-driven width and tilt.
   Pinch anchored at the gaze point. Drag pans. Two-hand rotate sets heading
   with quantised planning. Fold Apollo 11 into the global frame as a site
   pack so it uses the same camera.
   *Gate:* heading drag at 700 m across triggers zero tile generations during
   the gesture. Pan across a tile boundary has no visible seam.
3. **Scene stepping off the observation graph.** Scene application moves to a
   scene-update subscription reading a session snapshot; diagnostics publish
   once per change from there. Delete the equality guards that exist only to
   break feedback loops.
   *Gate:* the restore and re-entry journeys that previously hung run clean;
   no SwiftUI update-loop sample in a five-cycle soak.
4. **Coarse-first terrain and prefetch.** Request the 512 m generation when
   width drops below about 600 km and publish it when it lands; finer levels
   follow altitude. Prefetch sources on approach. Measure per-level mesh cost
   and build siblings within a level in parallel.
   *Gate:* the 240 km handoff never waits on a build in a warm-source dive on
   device. A first-visit dive shows the map until terrain arrives, never black.
5. **Sliding region.** Re-resolve the region around the focus when it leaves a
   hysteresis band; keep the floating origin; reuse verified slabs from the
   content-addressed store.
   *Gate:* pan 100 km at 24 km across without a stop, with contact equals
   rendered at the end.
6. **Tiled globe imagery.** Replace the monolithic sphere texture with a pinned
   tile pyramid (the original W2 design). Solves the 2.2 GiB peak and fills
   the visual gap between 474 m/px and the regional terrain.
   *Gate:* lifetime peak under half of today's; disk capture unchanged within
   the accepted PSNR tolerance.

Steps 1 to 3 improve the product with today's loading, because the globe stays
visible and interactive while terrain builds behind it. Steps 4 to 6 are the
longer streaming track and can proceed in parallel.

## 5. Why streaming, with numbers

Physical Vision Pro, Release, from `MoonExplorerEntryAndImport.md` and
`MoonExplorerSourceLoadingAndReuse.md`.

| Step | Today | Needed |
|---|---:|---|
| Source resolution, first visit | 24,041 ms | Prefetch below ~600 km across, off the zoom path |
| Source resolution, repeat | 62 ms | Fine |
| Regional 16-tile build | 7,581 ms | Coarse-first, per-level generations |
| CPU mesh preparation per tile | ~430 ms | Measure per level; parallel siblings |
| Globe texture load | 2,903 ms, 2,234 MiB peak | Tiled pyramid |
| Region extent | 25 km sources, 20 km pan limit | Sliding region |
| Surface frame pacing | 22.22 ms windows | 90 Hz gate already open; measure the portal's stencil cost |

## 6. Decisions for the owner

1. Portal window or Shared Space volume. Recommendation: portal.
2. Soft edge: hard rounded frame plus vignette now, feathering from progressive
   immersion; a true feathered window is a later gated shader experiment.
3. Immersion entry: button to full with crown available via progressive, or
   button only.
4. Apollo 11 as a site pack. Right for one zoom; touches the capture baselines,
   so it lands as its own gated step.

## 7. Sources

- Discover RealityKit APIs for iOS, macOS and visionOS, WWDC24:
  https://developer.apple.com/videos/play/wwdc2024/10103/
- PortalComponent, allowing world content to peek out (Apple engineer guidance):
  https://developer.apple.com/forums/thread/747152
- visionOS 2 PortalComponent:
  https://xreality.zone/en/post/visionos-2-portalcomponent-a-teleportation-wonder-that-better-meets-expectations/
- Dive deep into volumes and immersive spaces, WWDC24:
  https://developer.apple.com/videos/play/wwdc2024/10153/
- What's new in visionOS 26, WWDC25:
  https://developer.apple.com/videos/play/wwdc2025/317/
