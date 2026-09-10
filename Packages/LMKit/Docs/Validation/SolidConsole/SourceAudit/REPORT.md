# Solid console source/geometry audit

Read-only inspection at LMKit `70c091471bbc1af6f82ba277f6c9cccc7caf01b3`. Reference visually inspected: `/Users/zac/Downloads/SI 99-15229h.jpg`. No simulator or new render. `bounds.json` records exact USD mesh bounds, input SHA256 values and complete Panel1–5 slot contracts; `read.py` reproduces extraction with Blender USD libraries. All dimensions metres, Cabin +X right/+Y up/-Z forward. Panel local +Z points toward crew.

## Why the assembly looks exposed

The reference shows continuous fitted gray console surfaces and pale surrounding structural fields. Small equipment projections and under-console openings exist, but rear instrument boxes do not substitute for the broad fitted panel surfaces.

Existing CommanderPanels contains segmented backing around apertures and shallow perimeter returns, not a deep closed console volume. Assembly initialization deliberately disables `/CommanderPanels/Panel_1/Panel_1_RemovableBacking` and `/CommanderPanels/Panel_4/Panel_4_RemovableBacking` because PanelInventory already provides thin slot-sized blanks on these face planes. Thus blanket re-enabling these groups reintroduces duplicate surfaces without creating the missing cavity enclosure. Slot placeholders are removed for installed full-slot components; partial slots retain backing. Individual instrument housing assets remain intact, so missing inter-slot skins and side closures expose their backs at oblique views.

New solids should bridge inter-slot gaps and conceal instrument rear cavities. Do not disable whole PanelInventory panels, since slot roots parent live components. Suppression manifests must name only replaced surface groups. Existing `/CommanderPanels/Panel_1/Panel_1_Shell` and `Panel_1_Trim`, and matching Panel4 shell/trim, need actual overlap review against new geometry; they contain the returns/aperture collars, not just placeholders. Preserve original backing suppression unless the replacement transaction intentionally changes ownership.

## Critical instrument depths

FDAI `/FDAI_Mount/FDAI_Fixed/FDAI_MountingPlate/Cube_001` is146.050mm square at instrument Z[-.004,0]. Bezel is same width, Z[0,.009]. RearHousing is127mm square, Z[-.208,0]; connector reaches-.233. Ball extends to+.042 and roll/error marks roughly+.044–.0465. These dial depths are not panel skin seating depths.

CDR Panel1 FDAI slot is(-.055,-.015,+.016): mounting-plate backside panelZ+.012, bezel+.016..+.025, housing-.192..+.016. Pilot Panel2 FDAI slot is(.060,-.115,0): mounting backside-.004, bezel0..+.009, housing-.208..0. Proposed CDR collar seat+.0118 and pilot skin-.004 are compatible with those plate backs; maintain aperture through rear housing and never cover ball/bezel.

DSKY slot Panel4 is(0,.015,+.009). Face mesh `/DSKY_Mount/DSKY_Face/DSKY_Face_Geometry` is206.3496mm by203.2mm, instrumentZ[-.006,+.006], therefore panelZ[+.003,+.015]. Housing `/DSKY_Mount/DSKY_Housing/DSKY_Housing_Geometry` is195.58mm by191.77mm at instrumentZ[-.160214,-.006], therefore panelZ[-.151214,+.003]. Front display/keys project beyond face. Leave keys'3mm rearward travel clear. Those housing dimensions are provisional visual bounds, explicitly not qualified historical cutout dimensions; see DSKY fit-interface/HANDOFF.

## Central width and windows

Proposed central enclosure CabinX[-.400,.400] stays49.004mm from nearest inner glazing X: forward panes each remain at|X|>=.449004. Own-station design eyes X±.5588 to any point in the corresponding pane retain|X|>=.449004; therefore any geometry entirely bounded by|X|<=.400 cannot block those rays. Existing frame extends32mm outward in pane plane, leaving a conservative17mm X separation. This is a coordinate proof for the bounded central volume, not clearance proof for future side wings/window-surround additions.

Inventory panel envelopes extend to±.485 because Panel1/2 are480mm wide at X±.245. A±.400 console intentionally does not cover every nominal outboard envelope margin. Existing principal slot regions fit within this narrower width. Use actual mounted surfaces and reference silhouette rather than simply boxing the complete480mm nominal envelopes, which would encroach toward windows.

## Datum summary

Panel1/2 centers(±.245,1.604410648,-.884985924), rotationX -10degrees. Panel3 center(0,1.278142214,-.805857837), rotationX -45degrees. Panel4 center(0,1.070142150,-.597857833), rotationX -45degrees. Panel5 center(-.558799982,.898352563,-.295082450), rotationX -75degrees. Exact quaternion values and all slots are in bounds.json.

ACA root Cabin(-.49,.9075,-.37); preserve sweep and hand access. Panel5__Timer is explicitly blocked and empty. Preserve hatch openings, native live instrument roots, window glazing and independent handrails. Deep enclosures may penetrate the existing pressure-shell approximation behind the visual panel; classify that separately from face obstruction. Final actual-mesh combined checks remain necessary after worker delivery.
