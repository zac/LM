# Apollo 11 terrain generator

This tool turns the official LROC `NAC_DTM_APOLLO11` GeoTIFF and hillshade
into the compact, offline assets bundled by the LM app. It crops a 2.048 km
east-west by 4.096 km north-south area around the Apollo 11 landing coordinate,
preserves true vertical scale, and samples the 2 m DTM at 8 m mesh spacing. The
longer approach axis keeps the checkpoint-resumed landing inside sourced relief
through contact instead of exposing the edge of the DTM crop.

The source files are intentionally not checked in. Download these products from
the LROC PDS archive:

- `NAC_DTM_APOLLO11.TIF`
- `NAC_DTM_APOLLO11_SHADE.TIF`
- `NAC_DTM_APOLLO11.LBL`
- `NAC_DTM_APOLLO11_README.TXT`

Run:

```sh
swift run Apollo11TerrainGenerator \
  /path/to/NAC_DTM_APOLLO11.TIF \
  /path/to/NAC_DTM_APOLLO11_SHADE.TIF \
  ../../LM
```

The generated manifest records the exact source hashes, crop, coordinate,
spacing, height encoding, and axis convention used by the runtime mesh.
