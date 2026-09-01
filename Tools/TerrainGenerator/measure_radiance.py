#!/usr/bin/env python3
"""Measure progressive-terrain radiance from matched Simulator captures.

The tile-tint image supplies ownership masks. Every measured image must use
the same camera, terrain state, dimensions, and settled residency generation.
The adjacent-boundary result is the LOD acceptance measurement; whole-region
means are also reported, but naturally include different lunar features.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image
from scipy.ndimage import binary_erosion, distance_transform_edt, gaussian_filter


TERMINAL_HUE = 0.13 * 255
LANDING_HUE = 0.34 * 255


def circular_hue_distance(hue: np.ndarray, target: float) -> np.ndarray:
    distance = np.abs(hue - target)
    return np.minimum(distance, 255 - distance)


def ownership_masks(path: Path) -> tuple[np.ndarray, np.ndarray]:
    hsv = np.asarray(Image.open(path).convert("HSV"))
    hue = hsv[..., 0].astype(np.float64)
    saturation = hsv[..., 1]
    terminal_distance = circular_hue_distance(hue, TERMINAL_HUE)
    landing_distance = circular_hue_distance(hue, LANDING_HUE)
    valid = saturation > 30
    terminal = valid & (terminal_distance < landing_distance) & (terminal_distance < 24)
    landing = valid & (landing_distance < terminal_distance) & (landing_distance < 35)
    if not terminal.any() or not landing.any():
        raise ValueError("tile-tint capture does not contain both expected LOD hues")
    return terminal, landing


def luminance(path: Path) -> np.ndarray:
    rgb = np.asarray(Image.open(path).convert("RGB"), dtype=np.float64) / 255
    return 0.2126 * rgb[..., 0] + 0.7152 * rgb[..., 1] + 0.0722 * rgb[..., 2]


def measure(
    image_path: Path,
    terminal: np.ndarray,
    landing: np.ndarray,
) -> dict[str, object]:
    values = luminance(image_path)
    if values.shape != terminal.shape:
        raise ValueError(
            f"{image_path} is {values.shape}; tile tint is {terminal.shape}"
        )

    blurred = gaussian_filter(values, sigma=8)
    high_pass = values - blurred
    regions: dict[str, dict[str, float | int]] = {}
    for label, mask in (("terminal", terminal), ("landing", landing)):
        interior = binary_erosion(mask, iterations=16)
        regions[label] = {
            "pixels": int(interior.sum()),
            "meanLuminance": float(values[interior].mean()),
            "highPassSD": float(high_pass[interior].std()),
        }

    terminal_depth = distance_transform_edt(terminal)
    landing_depth = distance_transform_edt(landing)
    distance_to_landing = distance_transform_edt(~landing)
    distance_to_terminal = distance_transform_edt(~terminal)
    terminal_band = (
        terminal
        & (terminal_depth >= 8)
        & (terminal_depth < 30)
        & (distance_to_landing < 80)
    )
    landing_band = (
        landing
        & (landing_depth >= 8)
        & (landing_depth < 30)
        & (distance_to_terminal < 80)
    )
    terminal_mean = float(values[terminal_band].mean())
    landing_mean = float(values[landing_band].mean())
    boundary = {
        "terminalPixels": int(terminal_band.sum()),
        "landingPixels": int(landing_band.sum()),
        "terminalMeanLuminance": terminal_mean,
        "landingMeanLuminance": landing_mean,
        "landingVsTerminalPercent": (landing_mean / terminal_mean - 1) * 100,
    }
    return {
        "image": str(image_path),
        "regions": regions,
        "adjacentBoundary": boundary,
    }


def parse_image(value: str) -> tuple[str, Path]:
    label, separator, path = value.partition("=")
    if not separator or not label or not path:
        raise argparse.ArgumentTypeError("use LABEL=PATH")
    return label, Path(path)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--tint", type=Path, required=True)
    parser.add_argument(
        "--image",
        action="append",
        type=parse_image,
        required=True,
        help="matched capture as LABEL=PATH; repeat for each presentation grade",
    )
    arguments = parser.parse_args()
    terminal, landing = ownership_masks(arguments.tint)
    result = {
        "tileTint": str(arguments.tint),
        "protocol": {
            "interiorErosionPixels": 16,
            "highPassGaussianSigmaPixels": 8,
            "boundaryInteriorBandPixels": [8, 30],
            "maximumOppositeRegionDistancePixels": 80,
            "note": (
                "Adjacent-boundary step is the LOD acceptance result. "
                "Whole-region means include different lunar features."
            ),
        },
        "measurements": {
            label: measure(path, terminal, landing)
            for label, path in arguments.image
        },
    }
    print(json.dumps(result, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
