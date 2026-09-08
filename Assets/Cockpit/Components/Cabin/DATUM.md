# Cabin datum and measurement freeze v1

This is a forward-compartment structural blockout, not a full pressure vessel or certified LM-5 replica. Freeze this skeleton for interface review before panel detail. All coordinates below are meters in +X right/LMP, +Y overhead, -Z forward. Origin matches the existing procedural cabin, not a physical body-station zero. Blender uses (x,-z,y); USD physically maps back to (x,z,-y). Root is identity.

| Quantity | Value | Evidence / qualification |
|---|---:|---|
| Forward compartment nominal diameter | 2.3368 | Apollo 11 press kit p96, 92 in; not clear usable width |
| Nominal barrel depth | 1.0668 | Same, 42 in; oblique forward closure protrudes beyond barrel; aft midsection omitted |
| Station spacing | 1.1176 | Grumman 1967 p17; not LM-5 survey |
| Deck W × D | 1.397 × .9144 | Grumman p27 approximate 55 × 36 in; width/depth assignment provisional |
| Deck center / thickness | (0,.10,-.07) / .045 | Legacy scene compatibility, not historical station |
| Shell crown center / radius | (0,1.10) / 1.1684 | Nominal radius; vertical registration provisional |
| Shell barrel fore/aft Z | -.48 / .5868 | Proposed optical-compatible registration, not body stations |
| Shell visual thickness | .025 | Provisional, not pressure structure sizing |
| Hatch clear nominal opening | .8128 square | Apollo 11 press kit p96; rounded production corners unmeasured |
| Hatch center | (0,.55,-.95) | Proposed; threshold .1436; no door, hinge, latch or swing certification |
| Main panel cant | -10° about +X | Grumman p27: top forward; installed sign checked against photos |
| Lower center panels | -45° about +X | Grumman p27: bottom aft |
| Side lower / middle tiers | -75° / -53.5° about +X | 15° / 36.5° above horizontal, early design basis |
| CDR_Eye | (-.5588,1.78,-.38) | Preserved app contract; source body stations (279.25,22,54) in |
| Source body to scene | (-Y,X,-Z) × .0254 + (0,-5.31295,.9916) | Distinguishes absolute station from scene eye height |
| Inner triangle top / inboard / outboard | .7112 / .6096 / .635 | NASA TN D-7439 p9 nominal 28/24/25 in |
| Inner corner offsets from eye | (-.4415295,0,-.1183075); (.1097963,.0494183,-.5648532); (.0175769,-.4308411,-.2009045) | Preserved ray reconstruction, not surveyed corners |
| Outer plane normal offset | .020 | PROVISIONAL cavity; optical compatibility only |
| LMP panes | Mirror CDR around X=0 | Proposed symmetry, no LMP optical calibration claim |
| Frame rail width / pane thickness | .024 / .003 | Visual estimates; triangle dimensions are datum faces |

All panel sizes, centers, shield profiles and mount offsets in `mounts.json` are proposed, replaceable reservations. Surface face +Z points toward crew. Panel mount origins are face centers; instrument reservation origins use the old app offsets from panel center and are NOT measured mating surfaces. DSKY has NO cutout or rear slot: the delivered component explicitly disqualifies its rear box for fitting.

Legacy comparison: panels 1/2 Z moved from -.535 to -.91 to meet oblique window inboard upper region; panel 3 from (0,1.245,-.540) to (0,1.264,-.82); panel 4 from (0,1.015,-.435) to (0,1.056,-.612). Sizes retained as provisional envelopes. Glareshields rebuilt as tall outboard stack-edge fins from 69-H-134 and AS11-36-5389; old shallow plates were inconsistent with visible installation. App source and calibration are unchanged. These proposals require coordinator reconciliation before use.
