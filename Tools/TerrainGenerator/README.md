# Apollo 11 terrain generator

This tool converts the source-pinned LROC `NAC_DTM_APOLLO11` v1.9 GeoTIFF
into the measured terrain foundation bundled by the LM app:

- a 2 m/post, 2.046 km near-field tile around the Apollo 11 retroreflector;
- a curvature-corrected 32 m/post, 16.352 km horizon tile;
- lossless 16-bit centimeter height maps; and
- a manifest containing the source URL and checksum, PDS projection, landing
  origin, sampling, mission-sun geometry, encodings, and generator checksum.
  No wall-clock timestamp is emitted, so identical inputs produce identical
  committed assets.

The committed albedo images are deliberately flat neutral regolith. The PDS
volume does not contain a photometric orthophoto, so diagnostic hillshade is
not represented as measured albedo. Orthophoto ingestion will be added only
after a source and its registration are pinned.

The 118 MB source file remains outside Git. Download
`NAC_DTM_APOLLO11.TIF` from the URL recorded in
`LM/Terrain/TerrainManifest.json`; the generator rejects a file whose byte
count or SHA-256 does not match the pinned product. The matching PDS label is
committed next to the generator and is independently checked before output.

Run from the repository root:

```sh
swift run --package-path Tools/TerrainGenerator Apollo11TerrainGenerator \
  --dtm /path/to/NAC_DTM_APOLLO11.TIF \
  --out LM/Terrain
```

The runtime retains measured heights at their native 2 m spacing. Below the
terminal-detail altitude, deterministic procedural residuals add only the
sub-resolution frequency band and remain exactly zero at every measured post.
