#!/usr/bin/env python3
"""Detect sub-DTM crater candidates in registered lunar reflectance imagery.

This deterministic offline generator correlates the image against the runtime
bowl-and-rim morphology shaded under the source observation's acquisition
illumination. Its output stays a candidate catalog until the diagnostic overlay
has been reviewed by a human.
"""

from __future__ import annotations

import argparse
import json
import math
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageEnhance
from scipy import ndimage, signal


CATALOG_SCHEMA_VERSION = 1
GENERATOR_VERSION = "nac-parametric-correlation-v1"
DEFAULT_SOURCE_IDS = (
    "nac-ortho-m150361817-50cm-slab",
    "nac-ortho-m150368601-50cm-slab",
)


@dataclass(frozen=True)
class Candidate:
    column: int
    row: int
    diameter_meters: float
    score: float


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate an auditable crater candidate catalog from lunar albedo."
    )
    parser.add_argument("--albedo", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--preview", type=Path)
    parser.add_argument(
        "--catalog-id",
        default="apollo11-near-field-nac-craters-v1-candidate",
        help="Stable catalog identifier written into the generated artifact.",
    )
    parser.add_argument("--meters-per-pixel", type=float, default=0.5)
    parser.add_argument("--minimum-diameter", type=float, default=2.0)
    parser.add_argument("--maximum-diameter", type=float, default=8.0)
    parser.add_argument("--diameter-steps", type=int, default=9)
    parser.add_argument("--minimum-score", type=float, default=0.70)
    parser.add_argument("--coverage-radius", type=float, default=900.0)
    parser.add_argument("--max-candidates", type=int, default=1200)
    parser.add_argument(
        "--sun-elevation",
        type=float,
        required=True,
        help="Source-observation solar elevation in degrees.",
    )
    parser.add_argument(
        "--sun-azimuth",
        type=float,
        required=True,
        help="Source-observation solar azimuth clockwise from local north.",
    )
    parser.add_argument(
        "--source-id",
        action="append",
        dest="source_ids",
        help="Manifest source ID; may be repeated.",
    )
    return parser.parse_args()


def srgb_to_linear(value: np.ndarray) -> np.ndarray:
    return np.where(
        value <= 0.04045,
        value / 12.92,
        np.power((value + 0.055) / 1.055, 2.4),
    ).astype(np.float32)


def load_reflectance(path: Path) -> np.ndarray:
    with Image.open(path) as image:
        gray = np.asarray(image.convert("L"), dtype=np.float32) / 255.0
    return srgb_to_linear(gray)


def crater_template(
    diameter_meters: float,
    meters_per_pixel: float,
    sun_elevation_degrees: float,
    sun_azimuth_degrees: float,
) -> np.ndarray:
    radius_pixels = diameter_meters / (2 * meters_per_pixel)
    half_size = max(3, math.ceil(radius_pixels * 1.8))
    axis = np.arange(-half_size, half_size + 1, dtype=np.float32)
    east_pixels, south_pixels = np.meshgrid(axis, axis)
    normalized_radius = np.hypot(east_pixels, south_pixels) / radius_pixels

    sharpness = 0.75
    depth = diameter_meters * (0.025 + sharpness * 0.060)
    rim_height = diameter_meters * (0.006 + sharpness * 0.014)
    relief = np.zeros_like(normalized_radius, dtype=np.float32)
    inside = normalized_radius < 1
    relief[inside] -= depth * np.power(
        1 - normalized_radius[inside] * normalized_radius[inside], 1.15
    )
    rim_width = 0.10 + (1 - sharpness) * 0.16
    relief += rim_height * np.exp(-np.square((normalized_radius - 1) / rim_width))
    relief[normalized_radius >= 1.65] = 0

    derivative_south, derivative_east = np.gradient(relief, meters_per_pixel)
    elevation = math.radians(sun_elevation_degrees)
    azimuth = math.radians(sun_azimuth_degrees)
    sun_north = math.cos(elevation) * math.cos(azimuth)
    sun_east = math.cos(elevation) * math.sin(azimuth)
    sun_up = math.sin(elevation)
    # Image rows increase southward, hence dz/dnorth = -dz/dsouth.
    shading = derivative_south * sun_north - derivative_east * sun_east + sun_up
    support = normalized_radius < 1.65
    template = np.where(support, shading, 0).astype(np.float32)
    template[support] -= float(template[support].mean())
    norm = float(np.linalg.norm(template))
    if norm == 0:
        raise ValueError("degenerate crater template")
    return template / norm


def correlation_response(image: np.ndarray, template: np.ndarray) -> np.ndarray:
    numerator = signal.fftconvolve(image, template[::-1, ::-1], mode="same")
    local_mean = ndimage.uniform_filter(image, size=template.shape, mode="reflect")
    local_square_mean = ndimage.uniform_filter(
        image * image, size=template.shape, mode="reflect"
    )
    local_variance = np.maximum(local_square_mean - local_mean * local_mean, 1e-12)
    local_energy = np.sqrt(local_variance * template.size)
    return (numerator / local_energy).astype(np.float32)


def scale_candidates(
    image: np.ndarray,
    diameter_meters: float,
    arguments: argparse.Namespace,
) -> list[Candidate]:
    template = crater_template(
        diameter_meters,
        arguments.meters_per_pixel,
        arguments.sun_elevation,
        arguments.sun_azimuth,
    )
    response = correlation_response(image, template)
    radius_pixels = diameter_meters / (2 * arguments.meters_per_pixel)
    neighborhood = max(3, int(round(radius_pixels)))
    local_maximum = ndimage.maximum_filter(
        response, size=neighborhood * 2 + 1, mode="nearest"
    )
    selected = (response >= arguments.minimum_score) & (response == local_maximum)

    rows, columns = np.nonzero(selected)
    half_width = (image.shape[1] - 1) / 2
    half_height = (image.shape[0] - 1) / 2
    east = (columns - half_width) * arguments.meters_per_pixel
    north = (half_height - rows) * arguments.meters_per_pixel
    coverage = east * east + north * north <= arguments.coverage_radius**2
    edge = template.shape[0] // 2 + 1
    coverage &= columns >= edge
    coverage &= rows >= edge
    coverage &= columns < image.shape[1] - edge
    coverage &= rows < image.shape[0] - edge

    return [
        Candidate(
            column=int(column),
            row=int(row),
            diameter_meters=diameter_meters,
            score=float(response[row, column]),
        )
        for row, column in zip(rows[coverage], columns[coverage])
    ]


def suppress_overlaps(
    candidates: list[Candidate],
    meters_per_pixel: float,
    maximum_count: int,
) -> list[Candidate]:
    accepted: list[Candidate] = []
    for candidate in sorted(
        candidates,
        key=lambda item: (-item.score, item.row, item.column, item.diameter_meters),
    ):
        overlaps = False
        for existing in accepted:
            separation = math.hypot(
                candidate.column - existing.column,
                candidate.row - existing.row,
            ) * meters_per_pixel
            minimum_separation = 0.45 * (
                candidate.diameter_meters + existing.diameter_meters
            )
            if separation < minimum_separation:
                overlaps = True
                break
        if not overlaps:
            accepted.append(candidate)
            if len(accepted) >= maximum_count:
                break
    return sorted(accepted, key=lambda item: (item.row, item.column))


def catalog_entry(
    candidate: Candidate,
    index: int,
    image_shape: tuple[int, int],
    arguments: argparse.Namespace,
) -> dict[str, float | str]:
    half_width = (image_shape[1] - 1) / 2
    half_height = (image_shape[0] - 1) / 2
    east = (candidate.column - half_width) * arguments.meters_per_pixel
    north = (half_height - candidate.row) * arguments.meters_per_pixel
    sharpness = np.clip(
        0.25
        + 0.75
        * (candidate.score - arguments.minimum_score)
        / max(0.75 - arguments.minimum_score, 1e-6),
        0.25,
        1.0,
    )
    return {
        "id": f"nac-crater-{index + 1:05d}",
        "eastMeters": round(float(east), 3),
        "northMeters": round(float(north), 3),
        "diameterMeters": round(candidate.diameter_meters, 3),
        "sharpness": round(float(sharpness), 4),
        "confidence": round(float(np.clip(candidate.score, 0, 1)), 4),
    }


def write_catalog(
    path: Path,
    candidates: list[Candidate],
    image_shape: tuple[int, int],
    arguments: argparse.Namespace,
) -> None:
    payload = {
        "schemaVersion": CATALOG_SCHEMA_VERSION,
        "catalogID": arguments.catalog_id,
        "generatorVersion": GENERATOR_VERSION,
        "sourceIDs": arguments.source_ids or list(DEFAULT_SOURCE_IDS),
        "coordinateFrame": "landing-origin-local-north-east-meters",
        "detectionParameters": {
            "metersPerPixel": arguments.meters_per_pixel,
            "minimumDiameterMeters": arguments.minimum_diameter,
            "maximumDiameterMeters": arguments.maximum_diameter,
            "diameterSteps": arguments.diameter_steps,
            "minimumScore": arguments.minimum_score,
            "coverageRadiusMeters": arguments.coverage_radius,
            "maximumCandidates": arguments.max_candidates,
            "sunElevationDegrees": arguments.sun_elevation,
            "sunAzimuthDegreesClockwiseFromNorth": arguments.sun_azimuth,
        },
        "entries": [
            catalog_entry(candidate, index, image_shape, arguments)
            for index, candidate in enumerate(candidates)
        ],
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")


def write_preview(
    input_path: Path,
    output_path: Path,
    candidates: list[Candidate],
    meters_per_pixel: float,
) -> None:
    with Image.open(input_path) as source:
        image = source.convert("L")
    image = ImageEnhance.Contrast(image).enhance(3.0).convert("RGB")
    draw = ImageDraw.Draw(image)
    for candidate in candidates:
        radius = candidate.diameter_meters / (2 * meters_per_pixel)
        bounds = (
            candidate.column - radius,
            candidate.row - radius,
            candidate.column + radius,
            candidate.row + radius,
        )
        color = (255, 80, 40) if candidate.score >= 0.5 else (255, 210, 40)
        draw.ellipse(bounds, outline=color, width=1)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    image.save(output_path)


def main() -> None:
    arguments = parse_arguments()
    if arguments.minimum_diameter <= 0:
        raise ValueError("minimum diameter must be positive")
    if arguments.maximum_diameter < arguments.minimum_diameter:
        raise ValueError("maximum diameter must not be smaller than minimum diameter")
    if arguments.diameter_steps < 1:
        raise ValueError("diameter steps must be positive")

    reflectance = load_reflectance(arguments.albedo)
    diameters = np.geomspace(
        arguments.minimum_diameter,
        arguments.maximum_diameter,
        arguments.diameter_steps,
    )
    detected: list[Candidate] = []
    for diameter in diameters:
        scale = scale_candidates(reflectance, float(diameter), arguments)
        detected.extend(scale)
        print(f"diameter {diameter:.2f} m: {len(scale)} local candidates")

    candidates = suppress_overlaps(
        detected,
        meters_per_pixel=arguments.meters_per_pixel,
        maximum_count=arguments.max_candidates,
    )
    write_catalog(arguments.out, candidates, reflectance.shape, arguments)
    if arguments.preview:
        write_preview(
            arguments.albedo,
            arguments.preview,
            candidates,
            arguments.meters_per_pixel,
        )
    print(f"wrote {len(candidates)} candidates to {arguments.out}")


if __name__ == "__main__":
    main()
