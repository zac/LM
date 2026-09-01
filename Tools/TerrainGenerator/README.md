# Apollo 11 terrain generator

This tool combines the source-pinned LROC `NAC_DTM_APOLLO11` v1.9 GeoTIFF
with LOLA/SELENE `SLDEM2015` V2.0 into the progressive terrain foundation
bundled by the LM app:

- a measured 2 m/post, 2.048 km near-field tile around the Apollo 11
  retroreflector;
- a 32 m render grid over 16.384 km constrained by native ~59.2 m SLDEM;
- a 512 m far grid over 262.144 km sampled from native ~236.9 m SLDEM;
- manifest-scaled 16-bit height maps;
- source-backed reflectance textures from empirically normalized LROC WAC
  imagery plus registered 0.5 m NAC high-frequency detail; and
- a manifest containing source URLs, exact byte ranges and checksums, PDS
  projections, landing origin, sampling, boundary registration, mission-sun
  geometry, encodings, and generator checksum.
  No wall-clock timestamp is emitted, so identical inputs produce identical
  committed assets.

The far field uses 25 centimeters per UInt16 count because lunar curvature
across 262 km spans more than 10 km. The near and medium fields retain one
centimeter per count.

The albedo bands use the LROC WAC empirical 643 nm mosaic as the
photometrically normalized absolute reflectance reference. The near band adds
only the high-frequency component of two registered 0.5 m NAC orthorectified
observations after normalizing their independent exposures. The residual is
bounded and fades to exactly zero over the outer 128 m, while the far WAC band
is registered to the medium boundary. Images are stored as sRGB encodings of a
linear reflectance proxy; dynamic mission lighting supplies shape. Diagnostic
hillshade is not used as albedo.

The source rasters remain outside Git. Download
`NAC_DTM_APOLLO11.TIF` from the URL recorded in
`LM/Terrain/TerrainManifest.json`; the generator rejects a file whose byte
count or SHA-256 does not match the pinned product.

Only rows needed for the Apollo 11 corridor are fetched from the large source
images. Create `Tools/TerrainGenerator/cache`, then run the two SLDEM requests
and five reflectance requests:

```sh
curl -L --fail \
  --range 1370787840-1396869119 \
  --output Tools/TerrainGenerator/cache/SLDEM2015_512_APOLLO11_ROWS_14874_15156_FLOAT.bin \
  https://pds-geosciences.wustl.edu/lro/lro-l-lola-3-rdr-v1/lrolol_1xxx/data/sldem2015/tiles/float_img/sldem2015_512_00n_30n_000_045_float.img

curl -L --fail \
  --range 1297244160-1502392319 \
  --output Tools/TerrainGenerator/cache/SLDEM2015_128_APOLLO11_ROWS_7038_8150_FLOAT.bin \
  https://pds-geosciences.wustl.edu/lro/lro-l-lola-3-rdr-v1/lrolol_1xxx/data/sldem2015/global/float_img/sldem2015_128_60s_60n_000_360_float.img

curl -L --fail --range 541864880-611039119 \
  --output Tools/TerrainGenerator/cache/NAC_DTM_APOLLO11_M150361817_50CM_ROWS_32100_36197.bin \
  https://pds.lroc.im-ldi.com/data/LRO-L-LROC-5-RDR-V1.0/LROLRC_2001/DATA/SDP/NAC_DTM/APOLLO11/NAC_DTM_APOLLO11_M150361817_50CM.IMG

curl -L --fail --range 541864880-611039119 \
  --output Tools/TerrainGenerator/cache/NAC_DTM_APOLLO11_M150368601_50CM_ROWS_32100_36197.bin \
  https://pds.lroc.im-ldi.com/data/LRO-L-LROC-5-RDR-V1.0/LROLRC_2001/DATA/SDP/NAC_DTM/APOLLO11/NAC_DTM_APOLLO11_M150368601_50CM.IMG

curl -L --fail --range 1964666880-1983052799 \
  --output Tools/TerrainGenerator/cache/WAC_EMP_643NM_304P_N_ROWS_17951_18118_FLOAT.bin \
  https://pds.lroc.im-ldi.com/data/LRO-L-LROC-5-RDR-V1.0/LROLRC_2001/DATA/MDR/WAC_EMP/WAC_EMP_643NM_E300N0450_304P.IMG

curl -L --fail --range 81077760-88496639 \
  --output Tools/TerrainGenerator/cache/WAC_EMP_643NM_064P_N_ROWS_3518_3839_FLOAT.bin \
  https://pds.lroc.im-ldi.com/data/LRO-L-LROC-5-RDR-V1.0/LROLRC_2001/DATA/MDR/WAC_EMP/WAC_EMP_643NM_E300N0450_064P.IMG

curl -L --fail --range 23040-5460479 \
  --output Tools/TerrainGenerator/cache/WAC_EMP_643NM_064P_S_ROWS_0_235_FLOAT.bin \
  https://pds.lroc.im-ldi.com/data/LRO-L-LROC-5-RDR-V1.0/LROLRC_2001/DATA/MDR/WAC_EMP/WAC_EMP_643NM_E300S0450_064P.IMG
```

The generator rejects every input unless its byte count and SHA-256 match the
pinned value. The matching PDS labels are committed next to the generator and
independently checked before output; published whole-source MD5 values are
also recorded in the manifest.

Run from the repository root:

```sh
swift run --package-path Tools/TerrainGenerator Apollo11TerrainGenerator \
  --dtm /path/to/NAC_DTM_APOLLO11.TIF \
  --sldem-medium /path/to/SLDEM2015_512_APOLLO11_ROWS_14874_15156_FLOAT.bin \
  --sldem-far /path/to/SLDEM2015_128_APOLLO11_ROWS_7038_8150_FLOAT.bin \
  --nac-ortho-a /path/to/NAC_DTM_APOLLO11_M150361817_50CM_ROWS_32100_36197.bin \
  --nac-ortho-b /path/to/NAC_DTM_APOLLO11_M150368601_50CM_ROWS_32100_36197.bin \
  --wac-medium /path/to/WAC_EMP_643NM_304P_N_ROWS_17951_18118_FLOAT.bin \
  --wac-far-north /path/to/WAC_EMP_643NM_064P_N_ROWS_3518_3839_FLOAT.bin \
  --wac-far-south /path/to/WAC_EMP_643NM_064P_S_ROWS_0_235_FLOAT.bin \
  --out LM/Terrain
```

The runtime retains measured heights at their native 2 m spacing. Below the
terminal-detail altitude, deterministic procedural residuals add only the
sub-resolution frequency band and remain exactly zero at every measured post.

## Global WAC map tier

Stage 1 of `Docs/LandAnywhereMoonPlan.md` uses the separate
`GlobalLunarMosaicGenerator` executable. Fetch the complete attached-label PDS
product into the ignored cache:

```sh
curl -L --fail \
  --output Tools/TerrainGenerator/cache/WAC_GLOBAL_E000N0000_016P.IMG \
  https://pds.lroc.im-ldi.com/data/LRO-L-LROC-5-RDR-V1.0/LROLRC_2001/DATA/BDR/WAC_GLOBAL/WAC_GLOBAL_E000N0000_016P.IMG

curl -L --fail \
  --output Tools/TerrainGenerator/cache/LDEM_16.IMG \
  https://imbrium.mit.edu/DATA/LOLA_GDR/CYLINDRICAL/IMG/LDEM_16.IMG

curl -L --fail \
  --output Tools/TerrainGenerator/cache/LDEM_16.LBL \
  https://imbrium.mit.edu/DATA/LOLA_GDR/CYLINDRICAL/IMG/LDEM_16.LBL
```

Then regenerate the bundled map and provenance sidecar:

```sh
swift run --package-path Tools/TerrainGenerator GlobalLunarMosaicGenerator \
  Tools/TerrainGenerator/cache/WAC_GLOBAL_E000N0000_016P.IMG \
  LM/Terrain/WACGlobal16PPD.png \
  LM/Terrain/WACGlobal16PPD.json \
  --elevation Tools/TerrainGenerator/cache/LDEM_16.IMG \
  --elevation-label Tools/TerrainGenerator/cache/LDEM_16.LBL \
  --normal-output LM/Terrain/LOLALDEM16MENormal.png
```

The executable rejects the input unless its byte count, SHA-256, attached PDS
label, sample layout, projection, dimensions, and longitude convention match
the pinned product. It uses a fixed reflectance transfer, so output does not
depend on the source image's observed extrema. Xcode may losslessly rewrite
PNG container metadata while copying resources; the manifest hash therefore
pins the generated repository artifact, while runtime tests separately verify
the bundled texture dimensions and manifest relationship.

The optional elevation arguments are all-or-nothing and independently verify
the exact LDEM image and label. LDEM longitude is rotated from 0...360 east to
the runtime's -180...+180 east convention. The generator differentiates only
height above the 1,737,400 m reference sphere, reconstructs each radial normal
in the Mean Earth/Polar-axis frame, and applies a five-degree polar reliability
taper where a cylindrical map's separately quantized longitude samples
converge. Runtime decodes this normal field only at the terminator mask's
512×256 working resolution. It perturbs the day/night multiplier; it is not a
PBR normal map and never shades the already illuminated WAC base a second time.

## Photo-derived crater candidate catalog

Workstream A in `Docs/TerrainRealismPlan.md` starts with a deterministic,
offline detector over the registered near-field reflectance. The detector
correlates the image with the runtime crater morphology shaded under the
source observation's acquisition illumination, then writes a versioned JSON
candidate catalog and a contrast-enhanced review overlay. Supply the source
solar geometry explicitly; the Apollo simulation's mission-sun direction is
not a substitute for LROC acquisition geometry:

```sh
uv run --with-requirements Tools/TerrainGenerator/crater-requirements.txt \
  python Tools/TerrainGenerator/detect_craters.py \
  --albedo LM/Terrain/near-field-albedo.png \
  --sun-elevation <source-degrees> \
  --sun-azimuth <source-degrees-clockwise-from-north> \
  --out /tmp/apollo11-crater-candidates.json \
  --preview /tmp/apollo11-crater-candidates.png
```

The source solar geometry and every detection threshold are recorded in the
JSON output for auditability. The output is intentionally marked `candidate`.
Do not copy it into
`LM/Terrain`, load it at runtime, or bump the geology model version until the
overlay has been visually reviewed against the registered NAC imagery. An
accepted catalog must also be pinned in `TerrainManifest.json` with both NAC
source IDs and the detector version.
