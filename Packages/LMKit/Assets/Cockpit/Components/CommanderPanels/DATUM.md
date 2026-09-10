# Commander panel surround datum

Identity root `/CommanderPanels`, meters, +X right/LMP, +Y overhead, -Z forward. Attach this root directly under the identity Cabin root. Do not also apply a panel placement: the two children already contain Cabin-relative transforms. Native Blender is Z-up using `(x,-z,y)`; export physically converts geometry and every local transform back to `(x,z,-y)` and marks USD Y-up.

`mounting.json` is the machine-readable contract. `panel_cabin_relative` and `interface_cabin_relative` are absolute in Cabin, even when their recorded Cabin paths are nested. `interface_parent_local` alone is local to the Panel_1/Panel_4 child. All scales are one.

| Datum | Cabin translation m | Rotation X | Instrument local offset m |
|---|---|---|---|
| Panel_1 | (-.2450000048, 1.6044106483, -.8849859238) | -10 degrees | FDAI (-.055,-.015,.016) |
| Panel_4 | (0,1.0701421499,-.5978578329) | -45 degrees | DSKY (0,.015,.009) |

The exact original floating-point positions are preserved in JSON; the local reconstruction is checked within 1 micrometer. Instrument size, pose, CDR eye and pane transforms remain unchanged. Empty interface nodes are placement references, not physical contacts or runtime bindings.

Panel 1's new outline is .395 x .500 m, centered at panel-local (+.0425,0), so its outboard edge is 85 mm inboard of the original .480 m-wide reservation. Panel 4 retains .400 x .340 m. This narrower new geometry avoids the fixed CDR optics; it does not change the reservation or any existing component. Full-reservation trial intersections are retained in `evidence/full-reservation-collision.json`.

All sheet/channel/trim/head dimensions are deliberate provisional authoring choices: 4 mm backing, 26 mm channel return, 4 mm rear flange, rear limit -34 mm panel-local Z, 1 mm collar above the sheet, 6 mm diameter captive head proxies. These are not engineering specifications. Shell channels meet their backing and rear flange; the central holes are open all the way through. Each backing strip, collar strip, return, flange and captive head is separately addressable. Removing the RemovableBacking group does not move either instrument interface, shell, or other panel.

The openings are rectangular conservative full-visual-envelope reservations, not derived fabrication holes. FDAI opening .15405 square; DSKY .2123496 x .2092 m. Each is 3 mm outside the largest current front envelope on each side, so the instrument face does not overlap the backing. This intentional visible gap avoids inventing a seating flange. There is no claimed contact or fastener engagement with an instrument. The provisional open rear supports do not enclose or support the rear boxes.
