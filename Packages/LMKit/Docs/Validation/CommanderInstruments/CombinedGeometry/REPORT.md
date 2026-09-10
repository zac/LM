# New-component combined geometry check

Read-only final authored USDZ snapshot from canonical LMKit. Six assets installed using their exact contracted poses: InteriorDetails and BreakerBanks identity Cabin-relative; AltitudeRate in Panel1__RangeThrust plus approved (-.02,0,.008) slot offset; CrossPointer identity in Panel1__CrossPointer; AttitudeMode in Panel3__Stability; DescentRate in Panel5__Engine. No source saved, no render, no simulator.

**Result: all 15 component-pair combinations have zero mesh AABB broadphase overlaps.** Therefore no cross-component triangle surface intersection is possible at this neutral pose (BVH fallback was available but no triangle candidate required it). This distinguishes actual geometric exclusion from merely reporting unchecked broadphase candidates. InteriorDetails vs BreakerBanks is included.

**Twenty representative face rays from commander eye (-.5588,1.78,-.38) found no obstruction by any other new component.** Each functional asset used center and four quarter-extent points on the front of its root-local bounds. These are sampled geometry probes, not visible legend/material or full eye-box qualification.

`results.json` records exact paths, SHA-256 hashes, Cabin matrices, bounds, every pair count and every sampled ray. The matrices and mesh vertices were evaluated after Blender USD import with Y-up to Z-up conversion. Script: `check.py`; Blender log: `run.log`.

Limits: neutral state, six new assets only. Does not retest each asset internally or the original foundation; original rear backing penetration remains separately documented. Does not establish continuous actuator/hand sweep, exact fit, every sightline, material transparency, readable scales, app state, native runtime or headset acceptance.

## Exact asset hashes

- InteriorDetails: `1d6fef1c8815d902235bdb0df32d201dbc25ac95fb7bb6ff90852781ed918231`

- BreakerBanks: `fce4e4248806f4ff963775bc8013e17e6dee370671e656390bb8d05fcddfc217`

- AltitudeRate: `047bd435c51ecb1920aedc8f8b1cefbc9ea9056ac1139503a81abe29b42254c1`

- CrossPointer: `8095cdf3c12c4b77025e415ad21ea24a5bf51615674fd076f7458b9369ae1eae`

- AttitudeMode: `4e7b811a7ed251bd9065a852a2ed652ca16a5fd06b48beea98702a492dc63f86`

- DescentRate: `ffa295038be35261353a8a0c8fe35316647d4e0b910b7ca108e97f55375cf078`
