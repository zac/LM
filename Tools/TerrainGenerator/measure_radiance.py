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


def ownership_masks(path: Path, global_levels: bool = False) -> tuple[np.ndarray, np.ndarray]:
    hsv = np.asarray(Image.open(path).convert("HSV"))
    hue = hsv[..., 0].astype(np.float64)
    saturation = hsv[..., 1]
    terminal_distance = circular_hue_distance(hue, TERMINAL_HUE)
    landing_distance = circular_hue_distance(hue, LANDING_HUE)
    valid = saturation > 30
    if global_levels:
        # The Simulator still color-converts unlit tints. Verified output hues
        # are 32-33 for L0 and 79-80 for L1, versus input hues 33 and 92.
        # L5's other green is 68 on output / 71 on input. These disjoint bands
        # include both encodings and exclude every other global LOD; the old
        # broad two-class mask also counted L4 as terminal and L5 as landing.
        terminal = valid & (circular_hue_distance(hue, TERMINAL_HUE) < 7)
        landing = valid & (hue >= 75) & (hue <= 100)
        if not terminal.any() or not landing.any():
            raise ValueError("global tint does not contain both terminal and landing levels")
        return terminal, landing
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
        if not interior.any():
            raise ValueError(f"{label} has no interior after the required 16-pixel erosion")
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
    if not terminal_band.any() or not landing_band.any():
        raise ValueError("capture has no adjacent boundary at the required 8-30 pixel depth")
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


def parse_lod_pair(value: str) -> tuple[str, Path, Path]:
    label, separator, paths = value.partition("=")
    coarse, comma, fine = paths.partition(",")
    if not separator or not comma or not label or not coarse or not fine:
        raise argparse.ArgumentTypeError("use LABEL=COARSE_PATH,FINE_PATH")
    return label, Path(coarse), Path(fine)


def measure_lod_pair(
    coarse_path: Path,
    fine_path: Path,
    fine_region: np.ndarray,
) -> dict[str, object]:
    coarse = luminance(coarse_path)
    fine = luminance(fine_path)
    if coarse.shape != fine_region.shape or fine.shape != fine_region.shape:
        raise ValueError("LOD pair and tile tint must have identical dimensions")
    interior = binary_erosion(fine_region, iterations=16)
    coarse_mean = float(coarse[interior].mean())
    fine_mean = float(fine[interior].mean())
    coarse_high_pass = coarse - gaussian_filter(coarse, sigma=8)
    fine_high_pass = fine - gaussian_filter(fine, sigma=8)
    return {
        "coarseImage": str(coarse_path),
        "fineImage": str(fine_path),
        "pixels": int(interior.sum()),
        "coarseMeanLuminance": coarse_mean,
        "fineMeanLuminance": fine_mean,
        "fineVsCoarsePercent": (fine_mean / coarse_mean - 1) * 100,
        "coarseHighPassSD": float(coarse_high_pass[interior].std()),
        "fineHighPassSD": float(fine_high_pass[interior].std()),
        "note": (
            "Same camera and lunar pixels; the tint's fine-LOD ownership "
            "region is applied to both captures."
        ),
    }


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
    parser.add_argument(
        "--lod-pair",
        action="append",
        type=parse_lod_pair,
        default=[],
        help=(
            "same-camera LOD pair as LABEL=COARSE_PATH,FINE_PATH; repeatable"
        ),
    )
    parser.add_argument("--global-levels", action="store_true",
                        help="Segment the unlit seven-level global palette; reject unrelated LODs")
    arguments = parser.parse_args()
    terminal, landing = ownership_masks(arguments.tint, arguments.global_levels)
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
    if arguments.lod_pair:
        result["sameRegionLODComparisons"] = {
            label: measure_lod_pair(coarse, fine, landing)
            for label, coarse, fine in arguments.lod_pair
        }
    print(json.dumps(result, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
