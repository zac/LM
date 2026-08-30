# Neural terrain detail trainer

This tool trains the compact 4x image model used by LM's streamed terrain
detail pipeline. Its preferred source is the pair of repository-pinned LROC
NAC 0.5 m orthophoto slabs in `Tools/TerrainGenerator/cache`. They are two
registered, independently exposed views of the same terrain. The trainer
normalizes each exposure, averages them to suppress sensor noise, and creates
the low-resolution partner by area downsampling and 8-bit quantization.
`--degradation realistic` adds randomized blur and sensor noise after the
paired baseline has passed fidelity checks.

If the ignored NAC slabs have not been downloaded, the trainer falls back to
`LM/Terrain/near-field-albedo.png`. That path is useful as an export smoke
test, but its narrow tonal and frequency range does not establish a visual
quality improvement over bilinear scaling.

The geographic split is deliberate. Training crops come from the western 75%
of the Apollo 11 near-field image. Validation crops come from the eastern 25%.
Adjacent random crops must not leak across that boundary.

The model predicts a bounded residual over bilinear upsampling. This keeps the
low-frequency measured reflectance recognizable while allowing learned lunar
texture in the missing frequency band. The current loss combines pixel,
gradient, and Laplacian terms. It is a compact fidelity-first student model,
not the final adversarial or diffusion teacher.

Run from the LM repository root:

```sh
python3 Tools/NeuralTerrain/train.py \
  --steps 500 \
  --export-coreml LM/LunarTerrainSR.mlpackage
```

Outputs under `Tools/NeuralTerrain/output` include a checkpoint, metrics JSON,
and a preview comparing the held-out target, degraded input, bilinear baseline,
and model result. The output directory is ignored. The exported Core ML package
is a source asset and is intentionally tracked when it passes runtime checks.
Export is refused unless held-out PSNR improves by at least 0.5 dB and gradient
error also improves; `--minimum-psnr-gain-db` can raise that bar.

The Core ML contract is fixed:

- input `low_resolution`: Float16 `[1, 1, 128, 128]`, reflectance in `0...1`
- output `super_resolution`: Float16 `[1, 1, 512, 512]`, reflectance in `0...1`
- scale: 4x
- color: single-channel normalized lunar reflectance

Use `--steps 2 --batch-size 1` for an export smoke test.

Validate that the committed package still matches the accepted weight hash,
quality gates, parameter budget, and Core ML tensor contract with:

```sh
uv run --with-requirements Tools/NeuralTerrain/requirements.txt \
  python Tools/NeuralTerrain/validate.py
```
