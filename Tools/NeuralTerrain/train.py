#!/usr/bin/env python3
"""Train and export LM's compact 4x lunar terrain detail model."""

from __future__ import annotations

import argparse
import json
import math
import random
import shutil
import time
from dataclasses import asdict, dataclass
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
import torch
from torch import Tensor, nn
import torch.nn.functional as F


class ResidualBlock(nn.Module):
    def __init__(self, channels: int) -> None:
        super().__init__()
        self.first = nn.Conv2d(channels, channels, 3, padding=1)
        self.second = nn.Conv2d(channels, channels, 3, padding=1)

    def forward(self, value: Tensor) -> Tensor:
        residual = F.silu(self.first(value))
        return value + self.second(residual) * 0.2


class LunarTerrainSR(nn.Module):
    """Small one-pass 4x student with an exactly preserved bilinear base."""

    def __init__(self, features: int = 24, blocks: int = 4) -> None:
        super().__init__()
        self.head = nn.Conv2d(1, features, 3, padding=1)
        self.body = nn.Sequential(*[ResidualBlock(features) for _ in range(blocks)])
        self.body_tail = nn.Conv2d(features, features, 3, padding=1)
        self.up2a = nn.Conv2d(features, features * 4, 3, padding=1)
        self.up2b = nn.Conv2d(features, features * 4, 3, padding=1)
        self.output = nn.Conv2d(features, 1, 3, padding=1)
        nn.init.zeros_(self.output.weight)
        nn.init.zeros_(self.output.bias)

    def forward(self, low_resolution: Tensor) -> Tensor:
        base = F.interpolate(
            low_resolution,
            scale_factor=4,
            mode="bilinear",
            align_corners=False,
        )
        features = F.silu(self.head(low_resolution))
        features = features + self.body_tail(self.body(features))
        features = F.silu(F.pixel_shuffle(self.up2a(features), 2))
        features = F.silu(F.pixel_shuffle(self.up2b(features), 2))
        residual = torch.tanh(self.output(features)) * 0.12
        return torch.clamp(base + residual, 0.0, 1.0)


@dataclass
class Metrics:
    source: str
    seed: int
    steps: int
    batch_size: int
    features: int
    blocks: int
    training_seconds: float
    validation_crop_count: int
    bilinear_psnr_db: float
    model_psnr_db: float
    psnr_gain_db: float
    bilinear_gradient_error: float
    model_gradient_error: float
    gradient_error_reduction: float
    parameter_count: int
    device: str


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--source",
        type=Path,
        help="Fallback high-resolution image when the paired NAC slabs are unavailable",
        default=Path("LM/Terrain/near-field-albedo.png"),
    )
    parser.add_argument(
        "--nac-ortho-a",
        type=Path,
        default=Path(
            "Tools/TerrainGenerator/cache/"
            "NAC_DTM_APOLLO11_M150361817_50CM_ROWS_32100_36197.bin"
        ),
    )
    parser.add_argument(
        "--nac-ortho-b",
        type=Path,
        default=Path(
            "Tools/TerrainGenerator/cache/"
            "NAC_DTM_APOLLO11_M150368601_50CM_ROWS_32100_36197.bin"
        ),
    )
    parser.add_argument("--output-dir", type=Path, default=Path("Tools/NeuralTerrain/output"))
    parser.add_argument("--export-coreml", type=Path)
    parser.add_argument("--steps", type=int, default=500)
    parser.add_argument("--batch-size", type=int, default=4)
    parser.add_argument("--crop-size", type=int, default=256)
    parser.add_argument("--features", type=int, default=24)
    parser.add_argument("--blocks", type=int, default=4)
    parser.add_argument("--learning-rate", type=float, default=2e-4)
    parser.add_argument("--validation-crops", type=int, default=8)
    parser.add_argument(
        "--minimum-psnr-gain-db",
        type=float,
        default=0.5,
        help="Quality gate applied before Core ML export",
    )
    parser.add_argument(
        "--degradation",
        choices=("paired", "realistic"),
        default="paired",
    )
    parser.add_argument("--seed", type=int, default=11_1969)
    parser.add_argument("--device", choices=("auto", "cpu", "mps"), default="auto")
    return parser.parse_args()


def select_device(requested: str) -> torch.device:
    if requested == "mps":
        if not torch.backends.mps.is_available():
            raise RuntimeError("MPS was requested but is unavailable")
        return torch.device("mps")
    if requested == "auto" and torch.backends.mps.is_available():
        return torch.device("mps")
    return torch.device("cpu")


def load_image_source(path: Path) -> tuple[Tensor, str]:
    image = Image.open(path).convert("L")
    pixels = np.asarray(image, dtype=np.float32) / 255.0
    return torch.from_numpy(pixels).unsqueeze(0).unsqueeze(0), str(path)


def load_nac_source(first_path: Path, second_path: Path) -> tuple[Tensor, str]:
    """Load two registered 0.5 m observations into one reflectance proxy."""
    rows = 4_098
    columns = 8_440
    expected_bytes = rows * columns * np.dtype("<i2").itemsize
    for path in (first_path, second_path):
        if path.stat().st_size != expected_bytes:
            raise ValueError(f"unexpected NAC slab size: {path}")
    first = np.memmap(first_path, dtype="<i2", mode="r", shape=(rows, columns))
    second = np.memmap(second_path, dtype="<i2", mode="r", shape=(rows, columns))
    valid = (first > -32_764) & (second > -32_764)
    complete_columns = np.flatnonzero(valid.all(axis=0))
    if complete_columns.size == 0 or np.max(np.diff(complete_columns)) != 1:
        raise ValueError("NAC slabs do not contain one contiguous fully valid footprint")
    west = int(complete_columns[0])
    east = int(complete_columns[-1]) + 1

    def normalized(source: np.ndarray) -> np.ndarray:
        values = np.asarray(source[:, west:east], dtype=np.float32)
        sample = values[::16, ::16]
        mean = float(sample.mean())
        standard_deviation = float(sample.std())
        if standard_deviation <= 0:
            raise ValueError("NAC exposure has degenerate statistics")
        return (values - mean) / standard_deviation

    texture = (normalized(first) + normalized(second)) * 0.5
    # Runtime reflectance sits near 0.25. This bounded contrast envelope makes
    # source texture visible without baking illumination into the albedo.
    reflectance = np.clip(0.25 + texture * 0.045, 0.08, 0.45).astype(np.float32)
    tensor = torch.from_numpy(reflectance).unsqueeze(0).unsqueeze(0)
    label = f"paired-nac:{first_path.name}+{second_path.name}"
    return tensor, label


def load_source(args: argparse.Namespace) -> tuple[Tensor, str]:
    first_exists = args.nac_ortho_a.exists()
    second_exists = args.nac_ortho_b.exists()
    if first_exists != second_exists:
        raise FileNotFoundError("both paired NAC slabs are required when either is present")
    if first_exists:
        return load_nac_source(args.nac_ortho_a, args.nac_ortho_b)
    return load_image_source(args.source)


def training_batch(
    source: Tensor,
    batch_size: int,
    crop_size: int,
    split_x: int,
    generator: random.Random,
    device: torch.device,
) -> Tensor:
    height, width = source.shape[-2:]
    patches = []
    for _ in range(batch_size):
        x = generator.randint(0, split_x - crop_size)
        y = generator.randint(0, height - crop_size)
        patch = source[..., y : y + crop_size, x : x + crop_size]
        if generator.random() < 0.5:
            patch = torch.flip(patch, dims=(-1,))
        if generator.random() < 0.5:
            patch = torch.flip(patch, dims=(-2,))
        rotation = generator.randrange(4)
        patch = torch.rot90(patch, rotation, dims=(-2, -1))
        patches.append(patch)
    return torch.cat(patches, dim=0).to(device)


def degrade(
    high_resolution: Tensor,
    generator: random.Random,
    mode: str,
) -> Tensor:
    kernel = generator.choice((1, 3, 5)) if mode == "realistic" else 1
    value = high_resolution
    if kernel > 1:
        value = F.avg_pool2d(value, kernel_size=kernel, stride=1, padding=kernel // 2)
    low_size = high_resolution.shape[-1] // 4
    value = F.interpolate(value, size=(low_size, low_size), mode="area")
    sigma = generator.uniform(0.0, 1.5) / 255.0 if mode == "realistic" else 0.0
    if sigma > 0:
        value = value + torch.randn_like(value) * sigma
    value = torch.round(torch.clamp(value, 0.0, 1.0) * 255.0) / 255.0
    return value


def image_gradients(value: Tensor) -> tuple[Tensor, Tensor]:
    return value[..., :, 1:] - value[..., :, :-1], value[..., 1:, :] - value[..., :-1, :]


def laplacian(value: Tensor) -> Tensor:
    kernel = value.new_tensor([[0.0, 1.0, 0.0], [1.0, -4.0, 1.0], [0.0, 1.0, 0.0]])
    return F.conv2d(value, kernel.view(1, 1, 3, 3), padding=1)


def reconstruction_loss(prediction: Tensor, target: Tensor) -> Tensor:
    pixel = F.mse_loss(prediction, target)
    prediction_dx, prediction_dy = image_gradients(prediction)
    target_dx, target_dy = image_gradients(target)
    gradient = F.l1_loss(prediction_dx, target_dx) + F.l1_loss(prediction_dy, target_dy)
    frequency = F.l1_loss(laplacian(prediction), laplacian(target))
    return pixel + gradient * 0.12 + frequency * 0.05


def validation_pairs(
    source: Tensor,
    crop_size: int,
    split_x: int,
    count: int,
    seed: int,
    device: torch.device,
    degradation: str,
) -> list[tuple[Tensor, Tensor]]:
    height, width = source.shape[-2:]
    generator = random.Random(seed + 77)
    pairs = []
    for _ in range(count):
        x = generator.randint(split_x, width - crop_size)
        y = generator.randint(0, height - crop_size)
        high = source[..., y : y + crop_size, x : x + crop_size].to(device)
        low = degrade(high, generator, degradation)
        pairs.append((low, high))
    return pairs


def psnr(prediction: Tensor, target: Tensor) -> float:
    mse = F.mse_loss(prediction, target).item()
    return 99.0 if mse == 0 else 10.0 * math.log10(1.0 / mse)


def gradient_error(prediction: Tensor, target: Tensor) -> float:
    prediction_dx, prediction_dy = image_gradients(prediction)
    target_dx, target_dy = image_gradients(target)
    return (
        F.l1_loss(prediction_dx, target_dx) + F.l1_loss(prediction_dy, target_dy)
    ).item()


def evaluate(
    model: nn.Module,
    pairs: list[tuple[Tensor, Tensor]],
) -> tuple[float, float, float, float]:
    bilinear_psnr = []
    model_psnr = []
    bilinear_gradient = []
    model_gradient = []
    model.eval()
    with torch.no_grad():
        for low, high in pairs:
            baseline = F.interpolate(low, scale_factor=4, mode="bilinear", align_corners=False)
            prediction = model(low)
            bilinear_psnr.append(psnr(baseline, high))
            model_psnr.append(psnr(prediction, high))
            bilinear_gradient.append(gradient_error(baseline, high))
            model_gradient.append(gradient_error(prediction, high))
    return (
        float(np.mean(bilinear_psnr)),
        float(np.mean(model_psnr)),
        float(np.mean(bilinear_gradient)),
        float(np.mean(model_gradient)),
    )


def tensor_image(value: Tensor) -> Image.Image:
    pixels = value.detach().cpu().squeeze().clamp(0, 1).numpy()
    return Image.fromarray(np.round(pixels * 255).astype(np.uint8))


def write_preview(model: nn.Module, pair: tuple[Tensor, Tensor], path: Path) -> None:
    low, high = pair
    with torch.no_grad():
        baseline = F.interpolate(low, scale_factor=4, mode="bilinear", align_corners=False)
        prediction = model(low)
    panels = [
        ("target", tensor_image(high)),
        ("degraded input", tensor_image(low).resize(high.shape[-2:][::-1], Image.Resampling.NEAREST)),
        ("bilinear", tensor_image(baseline)),
        ("model", tensor_image(prediction)),
    ]
    label_height = 24
    width = sum(image.width for _, image in panels)
    canvas = Image.new("L", (width, high.shape[-2] + label_height), color=18)
    draw = ImageDraw.Draw(canvas)
    offset = 0
    for label, image in panels:
        canvas.paste(image, (offset, label_height))
        draw.text((offset + 5, 5), label, fill=240)
        offset += image.width
    canvas.save(path)


def export_coreml(model: nn.Module, path: Path) -> None:
    import coremltools as ct

    model = model.cpu().eval()
    example = torch.zeros(1, 1, 128, 128)
    traced = torch.jit.trace(model, example)
    converted = ct.convert(
        traced,
        inputs=[ct.TensorType(name="low_resolution", shape=example.shape)],
        outputs=[ct.TensorType(name="super_resolution")],
        compute_precision=ct.precision.FLOAT16,
        minimum_deployment_target=ct.target.iOS17,
    )
    converted.author = "LM neural terrain trainer"
    converted.short_description = "Compact 4x lunar reflectance super-resolution student"
    converted.version = "1"
    converted.input_description["low_resolution"] = "1x1x128x128 lunar reflectance in 0...1"
    converted.output_description["super_resolution"] = "1x1x512x512 reconstructed reflectance in 0...1"
    if path.exists():
        if path.is_dir():
            shutil.rmtree(path)
        else:
            path.unlink()
    path.parent.mkdir(parents=True, exist_ok=True)
    converted.save(str(path))


def main() -> None:
    args = arguments()
    if args.crop_size % 4 != 0:
        raise ValueError("crop size must be divisible by four")
    torch.manual_seed(args.seed)
    np.random.seed(args.seed)
    random.seed(args.seed)
    torch.set_num_threads(max(1, min(8, torch.get_num_threads())))
    generator = random.Random(args.seed)
    device = select_device(args.device)
    source, source_label = load_source(args)
    split_x = int(source.shape[-1] * 0.75)
    model = LunarTerrainSR(features=args.features, blocks=args.blocks).to(device)
    optimizer = torch.optim.Adam(model.parameters(), lr=args.learning_rate)
    validation = validation_pairs(
        source,
        crop_size=args.crop_size,
        split_x=split_x,
        count=args.validation_crops,
        seed=args.seed,
        device=device,
        degradation=args.degradation,
    )

    started = time.perf_counter()
    model.train()
    report_every = max(1, args.steps // 10)
    for step in range(1, args.steps + 1):
        high = training_batch(
            source,
            batch_size=args.batch_size,
            crop_size=args.crop_size,
            split_x=split_x,
            generator=generator,
            device=device,
        )
        low = degrade(high, generator, args.degradation)
        prediction = model(low)
        loss = reconstruction_loss(prediction, high)
        optimizer.zero_grad(set_to_none=True)
        loss.backward()
        torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
        optimizer.step()
        if step == 1 or step % report_every == 0 or step == args.steps:
            print(f"step={step}/{args.steps} loss={loss.item():.6f}", flush=True)

    training_seconds = time.perf_counter() - started
    baseline_psnr, trained_psnr, baseline_gradient, trained_gradient = evaluate(
        model,
        validation,
    )
    args.output_dir.mkdir(parents=True, exist_ok=True)
    torch.save(
        {
            "model": model.state_dict(),
            "features": args.features,
            "blocks": args.blocks,
            "scale": 4,
            "seed": args.seed,
        },
        args.output_dir / "LunarTerrainSR.pt",
    )
    write_preview(model, validation[0], args.output_dir / "preview.png")

    metrics = Metrics(
        source=source_label,
        seed=args.seed,
        steps=args.steps,
        batch_size=args.batch_size,
        features=args.features,
        blocks=args.blocks,
        training_seconds=training_seconds,
        validation_crop_count=len(validation),
        bilinear_psnr_db=baseline_psnr,
        model_psnr_db=trained_psnr,
        psnr_gain_db=trained_psnr - baseline_psnr,
        bilinear_gradient_error=baseline_gradient,
        model_gradient_error=trained_gradient,
        gradient_error_reduction=baseline_gradient - trained_gradient,
        parameter_count=sum(parameter.numel() for parameter in model.parameters()),
        device=str(device),
    )
    (args.output_dir / "metrics.json").write_text(
        json.dumps(asdict(metrics), indent=2, sort_keys=True) + "\n"
    )
    print(json.dumps(asdict(metrics), indent=2, sort_keys=True), flush=True)

    if args.export_coreml:
        if metrics.psnr_gain_db < args.minimum_psnr_gain_db:
            raise RuntimeError(
                "refusing Core ML export: held-out PSNR gain "
                f"{metrics.psnr_gain_db:.3f} dB is below "
                f"{args.minimum_psnr_gain_db:.3f} dB"
            )
        if metrics.gradient_error_reduction <= 0:
            raise RuntimeError(
                "refusing Core ML export: held-out gradient error regressed"
            )
        export_coreml(model, args.export_coreml)
        print(f"exported_coreml={args.export_coreml}", flush=True)


if __name__ == "__main__":
    main()
