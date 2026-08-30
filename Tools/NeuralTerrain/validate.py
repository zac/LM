#!/usr/bin/env python3
"""Validate the committed neural terrain model and accepted evaluation record."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

import coremltools as ct


ROOT = Path(__file__).resolve().parents[2]
MODEL = ROOT / "LM/LunarTerrainSR.mlpackage"
METRICS = Path(__file__).with_name("accepted-metrics.json")
WEIGHTS = MODEL / "Data/com.apple.CoreML/weights/weight.bin"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        while block := source.read(1024 * 1024):
            digest.update(block)
    return digest.hexdigest()


def main() -> None:
    metrics = json.loads(METRICS.read_text())
    actual_weights_hash = sha256(WEIGHTS)
    if actual_weights_hash != metrics["weights_sha256"]:
        raise RuntimeError("Core ML weights do not match accepted metrics")
    if metrics["psnr_gain_db"] < 0.5:
        raise RuntimeError("accepted model does not clear the PSNR quality gate")
    if metrics["gradient_error_reduction"] <= 0:
        raise RuntimeError("accepted model regresses held-out gradient error")
    if metrics["parameter_count"] > 100_000:
        raise RuntimeError("accepted model exceeds the compact runtime budget")

    spec = ct.models.MLModel(str(MODEL), skip_model_load=True).get_spec()
    inputs = {feature.name: feature for feature in spec.description.input}
    outputs = {feature.name: feature for feature in spec.description.output}
    input_shape = list(inputs["low_resolution"].type.multiArrayType.shape)
    output_shape = list(outputs["super_resolution"].type.multiArrayType.shape)
    if input_shape != [1, 1, 128, 128]:
        raise RuntimeError(f"unexpected Core ML input shape: {input_shape}")
    if output_shape != [1, 1, 512, 512]:
        raise RuntimeError(f"unexpected Core ML output shape: {output_shape}")
    print(
        f"validated {metrics['model_id']}: "
        f"{metrics['parameter_count']:,} parameters, "
        f"{metrics['psnr_gain_db']:.3f} dB held-out gain"
    )


if __name__ == "__main__":
    main()
