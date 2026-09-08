# Read-only ceiling material audit

Inspected native screenshot `timers-normal.png` and actual authored USDZ attributes; no render, simulator or source edit. The broad field behind the two forward overhead mesh inserts is the existing Cabin roof bridge, not a large white InteriorDetails card. Primary paths:

- `/Cabin/Shell/Cutaway_Ceiling/Forward_Roof_Bridge_00`
- `/Cabin/Shell/Cutaway_Ceiling/Forward_Roof_Bridge_01`
- Adjacent crown meshes under the same group use the same liner material.

These bind `/Materials/WarmGrayLiner`: diffuse RGB **(0.58, 0.59, 0.55)** and roughness **0.70**. Metallic, emissiveColor and opacity are not authored: standard USD Preview Surface defaults are nonmetal, no emission and opaque. Interior bridge faces lie at Y2.186397 and have explicit uniform normals **(0,-1,0)** matching the geometric winding. Opposite outer faces at Y2.211397 have +Y normals. `doubleSided=true`. There is no flipped interior face-normal evidence on this surface.

The separate narrow cover bands at `/InteriorDetails/ForwardOverheadLiner/*_CoverSide_*` and `*_CoverEnd_*` bind `/Materials/LinerCream`: RGB **(0.67,0.66,0.56)**, metallic **0**, roughness **0.64**, no authored emission. Mesh bars bind `/Materials/LinerMesh`: RGB **(0.39,0.40,0.34)**, metallic **0.15**, roughness **0.64**, no emission. InteriorDetails meshes use outward geometric winding, no explicit normal primvar and `doubleSided=false`; previous geometry checks verified manifold positive-volume solids. The existing gray shell is visible through their actual open lattice.

Source and packaged USDZ SHA-256 values match for both Cabin and InteriorDetails. The installed source path applies `.paintedStructure` recursively to Cabin: roughness raised to at least0.9, specular capped0.08, preserving base tint/texture with no added emission. That path does not author a white ceiling. The scene's lighting/exposure/material conversion therefore needs runtime inspection to explain the pale/white output; this source-only audit cannot distinguish those rendering causes or declare a lighting bug from the screenshot alone.

Full material values, exact mesh paths and large-face geometric/authored normals are recorded in `result.json`. `read.py` reproduces the read-only inspection using Blender's USD library.
