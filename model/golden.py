#!/usr/bin/env python3
"""Appendix-A fixed-point reference model for the P7 edge pipeline.

This file is the arithmetic contract for RTL.  It intentionally uses a
zero-padded *and forced-invalid* border: each spatial stage shrinks the valid
region, rather than applying a replicated-image convolution.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import zlib
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Iterable

import numpy as np


GAUSS3 = np.array(((1, 2, 1), (2, 4, 2), (1, 2, 1)), dtype=np.int32)
GAUSS5_1D = np.array((1, 4, 6, 4, 1), dtype=np.int32)
GAUSS5 = np.outer(GAUSS5_1D, GAUSS5_1D).astype(np.int32)
KX = np.array(((-1, 0, 1), (-2, 0, 2), (-1, 0, 1)), dtype=np.int32)
KY = np.array(((-1, -2, -1), (0, 0, 0), (1, 2, 1)), dtype=np.int32)


@dataclass(frozen=True)
class Config:
    """Every fixed-point control that has an RTL counterpart."""

    gauss_n: int = 3
    dir_num: int = 13
    dir_den: int = 32
    thr_lo: int = 80
    thr_hi: int = 200
    hyst_k: int = 0
    mag_bits: int = 11
    input_trunc_bits: int = 0

    def check(self) -> None:
        if self.gauss_n not in (3, 5):
            raise ValueError("gauss_n must be 3 or 5")
        if self.dir_num <= 0 or self.dir_den <= 0:
            raise ValueError("direction constant must be positive")
        if not (0 <= self.thr_lo <= self.thr_hi < (1 << self.mag_bits)):
            raise ValueError("thresholds must satisfy 0 <= lo <= hi < 2**mag_bits")
        if self.hyst_k < 0:
            raise ValueError("hyst_k must be non-negative")
        if not (0 <= self.input_trunc_bits <= 7):
            raise ValueError("input_trunc_bits must be in 0..7")

    @property
    def gaussian_radius(self) -> int:
        return self.gauss_n // 2

    @property
    def final_margin(self) -> int:
        """Gaussian radius plus one Sobel and one NMS radius."""
        return self.gaussian_radius + 2


def _u8_gray(image: np.ndarray) -> np.ndarray:
    a = np.asarray(image)
    if a.ndim == 2:
        return np.clip(a, 0, 255).astype(np.uint8, copy=False)
    if a.ndim != 3 or a.shape[-1] < 3:
        raise ValueError("image must be HxW gray or HxWx3 RGB")
    # Plan section 2: no rounding term in the optional RGB converter.
    r, g, b = (a[..., i].astype(np.int32) for i in range(3))
    return ((77 * r + 150 * g + 29 * b) >> 8).astype(np.uint8)


def _interior_slices(height: int, width: int, margin: int) -> tuple[slice, slice]:
    if height <= 2 * margin or width <= 2 * margin:
        return slice(0, 0), slice(0, 0)
    return slice(margin, height - margin), slice(margin, width - margin)


def _window_slice(a: np.ndarray, margin: int, dy: int, dx: int) -> np.ndarray:
    h, w = a.shape
    return a[margin + dy:h - margin + dy, margin + dx:w - margin + dx]


def gaussian_frame(gray: np.ndarray, cfg: Config) -> np.ndarray:
    """Appendix-A Gaussian with forced-zero invalid border."""
    cfg.check()
    src = _u8_gray(gray).astype(np.int32)
    if cfg.input_trunc_bits:
        src = (src >> cfg.input_trunc_bits) << cfg.input_trunc_bits
    h, w = src.shape
    radius = cfg.gaussian_radius
    out = np.zeros((h, w), dtype=np.uint8)
    ys, xs = _interior_slices(h, w, radius)
    if ys.stop == 0:
        return out
    kernel = GAUSS3 if cfg.gauss_n == 3 else GAUSS5
    acc = np.zeros((h - 2 * radius, w - 2 * radius), dtype=np.int32)
    for kr in range(cfg.gauss_n):
        for kc in range(cfg.gauss_n):
            weight = int(kernel[kr, kc])
            if weight:
                dy, dx = kr - radius, kc - radius
                acc += weight * _window_slice(src, radius, dy, dx)
    rounding = 8 if cfg.gauss_n == 3 else 128
    shift = 4 if cfg.gauss_n == 3 else 8
    out[ys, xs] = np.clip((acc + rounding) >> shift, 0, 255).astype(np.uint8)
    return out


def quantise_direction(gx: np.ndarray, gy: np.ndarray, cfg: Config) -> np.ndarray:
    """Appendix-A direction encoding: 00, 01, 10, 11."""
    ax = np.abs(gx.astype(np.int32))
    ay = np.abs(gy.astype(np.int32))
    horizontal = cfg.dir_den * ay <= cfg.dir_num * ax
    vertical = cfg.dir_den * ax <= cfg.dir_num * ay
    same_sign = (gx < 0) == (gy < 0)
    return np.where(horizontal, 0, np.where(vertical, 2, np.where(same_sign, 1, 3))).astype(np.uint8)


def sobel_frame(smooth: np.ndarray, input_margin: int, cfg: Config) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Sobel L1 magnitude and direction, valid one pixel inside Gaussian."""
    a = _u8_gray(smooth).astype(np.int32)
    h, w = a.shape
    margin = input_margin + 1
    gx = np.zeros((h, w), dtype=np.int16)
    gy = np.zeros((h, w), dtype=np.int16)
    direction = np.zeros((h, w), dtype=np.uint8)
    ys, xs = _interior_slices(h, w, margin)
    if ys.stop == 0:
        return gx, gy, direction
    local_gx = np.zeros((h - 2 * margin, w - 2 * margin), dtype=np.int32)
    local_gy = np.zeros_like(local_gx)
    for kr in range(3):
        for kc in range(3):
            local_gx += int(KX[kr, kc]) * _window_slice(a, margin, kr - 1, kc - 1)
            local_gy += int(KY[kr, kc]) * _window_slice(a, margin, kr - 1, kc - 1)
    gx[ys, xs] = local_gx.astype(np.int16)
    gy[ys, xs] = local_gy.astype(np.int16)
    direction[ys, xs] = quantise_direction(local_gx, local_gy, cfg)
    return gx, gy, direction


def magnitude_frame(gx: np.ndarray, gy: np.ndarray, cfg: Config) -> np.ndarray:
    mag = np.abs(gx.astype(np.int32)) + np.abs(gy.astype(np.int32))
    maximum = (1 << cfg.mag_bits) - 1
    return np.minimum(mag, maximum).astype(np.uint16)


def nms_frame(mag: np.ndarray, direction: np.ndarray, input_margin: int) -> np.ndarray:
    """Appendix-A non-maximum suppression with raster-asymmetric ties."""
    m = np.asarray(mag, dtype=np.uint16)
    d = np.asarray(direction, dtype=np.uint8)
    h, w = m.shape
    margin = input_margin + 1
    out = np.zeros((h, w), dtype=np.uint16)
    ys, xs = _interior_slices(h, w, margin)
    if ys.stop == 0:
        return out
    centre = _window_slice(m, margin, 0, 0)
    dirs = _window_slice(d, margin, 0, 0)
    # Earlier/later follow the raster ordering exactly.
    west, east = _window_slice(m, margin, 0, -1), _window_slice(m, margin, 0, 1)
    north, south = _window_slice(m, margin, -1, 0), _window_slice(m, margin, 1, 0)
    nw, se = _window_slice(m, margin, -1, -1), _window_slice(m, margin, 1, 1)
    ne, sw = _window_slice(m, margin, -1, 1), _window_slice(m, margin, 1, -1)
    earlier = np.where(dirs == 0, west, np.where(dirs == 1, nw, np.where(dirs == 2, north, ne)))
    later = np.where(dirs == 0, east, np.where(dirs == 1, se, np.where(dirs == 2, south, sw)))
    keep = (centre > 0) & (centre >= earlier) & (centre > later)
    out[ys, xs] = np.where(keep, centre, 0).astype(np.uint16)
    return out


def classify_frame(nms: np.ndarray, cfg: Config) -> np.ndarray:
    n = np.asarray(nms, dtype=np.uint16)
    return np.where((n > 0) & (n >= cfg.thr_hi), 2, np.where((n > 0) & (n >= cfg.thr_lo), 1, 0)).astype(np.uint8)


def dilate3x3(binary: np.ndarray) -> np.ndarray:
    """Boolean 8-connected dilation, with zero outside the image."""
    b = np.asarray(binary, dtype=bool)
    h, w = b.shape
    p = np.pad(b, 1, mode="constant", constant_values=False)
    out = np.zeros((h, w), dtype=bool)
    for dy in range(3):
        for dx in range(3):
            out |= p[dy:dy + h, dx:dx + w]
    return out


def hysteresis_k(cls: np.ndarray, k: int) -> np.ndarray:
    """K conditional-dilation stages from Appendix A; K=0 is baseline."""
    if k < 0:
        raise ValueError("k must be non-negative")
    strong = np.asarray(cls) == 2
    weak = np.asarray(cls) == 1
    for _ in range(k):
        promoted = weak & dilate3x3(strong)
        strong |= promoted
        weak &= ~strong
    return strong.astype(np.uint8)


def full_hysteresis(cls: np.ndarray) -> np.ndarray:
    """Software-only converged hysteresis oracle for quality studies."""
    strong = np.asarray(cls) == 2
    weak = np.asarray(cls) == 1
    while True:
        promoted = weak & dilate3x3(strong)
        if not promoted.any():
            break
        strong |= promoted
        weak &= ~strong
    return strong.astype(np.uint8)


def edge_frame(image: np.ndarray, cfg: Config = Config()) -> dict[str, np.ndarray | int]:
    """Execute the complete Appendix-A baseline or K-stage variant."""
    cfg.check()
    gray = _u8_gray(image)
    smooth = gaussian_frame(gray, cfg)
    gx, gy, direction = sobel_frame(smooth, cfg.gaussian_radius, cfg)
    mag = magnitude_frame(gx, gy, cfg)
    nms = nms_frame(mag, direction, cfg.gaussian_radius + 1)
    cls = classify_frame(nms, cfg)
    edge = hysteresis_k(cls, cfg.hyst_k)
    return {
        "gray": gray,
        "smooth": smooth,
        "gx": gx,
        "gy": gy,
        "mag": mag,
        "dir": direction,
        "nms": nms,
        "cls": cls,
        "edge": edge,
        "margin": cfg.final_margin,
    }


def edge_bytes(edge: np.ndarray) -> bytes:
    return np.where(np.asarray(edge, dtype=bool), 0xFF, 0x00).astype(np.uint8).tobytes()


def frame_crc(edge: np.ndarray) -> int:
    """zlib-compatible CRC-32/IEEE of row-major active-area edge bytes."""
    return zlib.crc32(edge_bytes(edge)) & 0xFFFFFFFF


def histogram64(nms: np.ndarray) -> tuple[np.ndarray, int]:
    values = np.asarray(nms, dtype=np.uint16)
    survivor = values[values > 0]
    bins = np.minimum(63, survivor.astype(np.int32) >> 5)
    return np.bincount(bins, minlength=64).astype(np.uint32), int(survivor.size)


def percentile_threshold(hist: np.ndarray, nonzero: int, minimum: int = 16) -> tuple[int, int]:
    """N1 hardware-FSM rule: select the strongest ~18.75% histogram bin."""
    if nonzero <= 0:
        return minimum, (minimum >> 2) + (minimum >> 3)
    target = max(1, (nonzero >> 3) + (nonzero >> 4))
    cumulative = 0
    high = minimum
    for idx in range(63, -1, -1):
        cumulative += int(hist[idx])
        if cumulative >= target:
            high = max(minimum, idx << 5)
            break
    return high, (high >> 2) + (high >> 3)


def otsu_threshold(nms: np.ndarray) -> int:
    """Same-frame 64-bin Otsu oracle, not an RTL algorithm."""
    hist, total = histogram64(nms)
    if total == 0:
        return 0
    levels = np.arange(64, dtype=np.float64)
    weight0 = np.cumsum(hist, dtype=np.float64)
    weight1 = total - weight0
    sum0 = np.cumsum(hist * levels, dtype=np.float64)
    total_sum = float(sum0[-1])
    with np.errstate(divide="ignore", invalid="ignore"):
        mean0 = sum0 / weight0
        mean1 = (total_sum - sum0) / weight1
    between = weight0 * weight1 * (mean0 - mean1) ** 2
    return int(np.nanargmax(between)) << 5


def psnr(test: np.ndarray, reference: np.ndarray, peak: float = 255.0) -> float:
    a = np.asarray(test, dtype=np.float64)
    b = np.asarray(reference, dtype=np.float64)
    mse = float(np.mean((a - b) ** 2))
    return float("inf") if mse == 0.0 else float(10.0 * np.log10((peak * peak) / mse))


def fscore(test: np.ndarray, reference: np.ndarray, tolerance: int = 0) -> dict[str, float | int]:
    """Binary edge precision/recall/F-score with optional Chebyshev tolerance."""
    t, r = np.asarray(test, dtype=bool), np.asarray(reference, dtype=bool)
    if t.shape != r.shape or tolerance < 0:
        raise ValueError("matching shapes and non-negative tolerance are required")
    if tolerance:
        near_r, near_t = r.copy(), t.copy()
        for _ in range(tolerance):
            near_r, near_t = dilate3x3(near_r), dilate3x3(near_t)
        true_for_precision = int((t & near_r).sum())
        true_for_recall = int((r & near_t).sum())
    else:
        true_for_precision = true_for_recall = int((t & r).sum())
    predicted, expected = int(t.sum()), int(r.sum())
    precision = true_for_precision / max(predicted, 1)
    recall = true_for_recall / max(expected, 1)
    score = 0.0 if precision + recall == 0.0 else 2.0 * precision * recall / (precision + recall)
    return {"precision": precision, "recall": recall, "fscore": score, "predicted": predicted, "expected": expected}


def float_canny_reference(image: np.ndarray, low: int, high: int) -> np.ndarray:
    """Optional OpenCV float-reference orientation for quality studies only."""
    try:
        import cv2
    except ImportError as exc:  # pragma: no cover - environment dependent
        raise RuntimeError("OpenCV is required for the float reference") from exc
    gray = _u8_gray(image)
    # Sobel L1 magnitudes reach 2040; OpenCV thresholds use the 8-bit image scale.
    return (cv2.Canny(gray, low / 8.0, high / 8.0, L2gradient=False) > 0).astype(np.uint8)


def resize_gray(image: np.ndarray, width: int = 640, height: int = 480) -> np.ndarray:
    try:
        import cv2
    except ImportError as exc:  # pragma: no cover - environment dependent
        raise RuntimeError("OpenCV is required to create the fixed-size corpus") from exc
    return cv2.resize(_u8_gray(image), (width, height), interpolation=cv2.INTER_AREA)


def natural_images(width: int = 640, height: int = 480) -> list[tuple[str, np.ndarray]]:
    """Seven versioned scikit-image sample photographs/textures, made gray."""
    try:
        from skimage import data
    except ImportError as exc:  # pragma: no cover - dependency checked by P0
        raise RuntimeError("scikit-image is required for the natural-image corpus") from exc
    source = (
        ("camera", data.camera),
        ("coins", data.coins),
        ("astronaut", data.astronaut),
        ("moon", data.moon),
        ("page", data.page),
        ("brick", data.brick),
        ("gravel", data.gravel),
    )
    return [(name, resize_gray(loader(), width, height)) for name, loader in source]


def synthetic_images(width: int = 640, height: int = 480, seed: int = 20261028) -> list[tuple[str, np.ndarray]]:
    """Deterministic directed patterns for boundary, direction and NMS tests."""
    rng = np.random.default_rng(seed)
    y, x = np.mgrid[0:height, 0:width]
    checker = np.where(((x // 16) + (y // 16)) & 1, 205, 45).astype(np.float64)
    checker += rng.normal(0, 10, checker.shape)
    gradient = 20 + 180 * x / max(width - 1, 1)
    circles = gradient + 70 * np.sin(np.hypot(x - width / 2, y - height / 2) / 8.0)
    angle = np.arctan2(y - height / 2, x - width / 2)
    siemens = np.where(np.cos(24 * angle) >= 0, 230, 25).astype(np.float64)
    lines = np.zeros((height, width), dtype=np.float64) + 20
    lines[np.abs(y - x * height / max(width, 1)) <= 1] = 240
    lines[np.abs(y - (height - 1 - x * height / max(width, 1))) <= 1] = 180
    lines[:, width // 2 - 1:width // 2 + 1] = 255
    flat = np.full((height, width), 91, dtype=np.float64)
    return [
        ("checker_noise", np.clip(checker, 0, 255).astype(np.uint8)),
        ("circles_gradient", np.clip(circles, 0, 255).astype(np.uint8)),
        ("siemens_star", siemens.astype(np.uint8)),
        ("single_pixel_lines", lines.astype(np.uint8)),
        ("flat", flat.astype(np.uint8)),
    ]


def sequences(width: int = 640, height: int = 480) -> dict[str, list[np.ndarray]]:
    """V1–V5 deterministic sequences from the plan, generated on demand."""
    natural = dict(natural_images(width, height))
    base = natural["camera"].astype(np.float64)
    alternate = natural["astronaut"].astype(np.float64)
    rng = np.random.default_rng(20261028)
    ramp = [np.clip(base * g, 0, 255).astype(np.uint8) for g in np.r_[np.linspace(1.0, 0.4, 45), np.linspace(0.4, 1.0, 45)]]
    hard_cut = [base.astype(np.uint8) if (i // 30) % 2 == 0 else alternate.astype(np.uint8) for i in range(90)]
    noise = [np.clip(base + rng.normal(0, sigma, base.shape), 0, 255).astype(np.uint8) for sigma in (2,) * 30 + (10,) * 30 + (2,) * 30]
    pan = [np.roll(base, i - 30, axis=1).astype(np.uint8) for i in range(60)]
    static = [np.clip(base + rng.normal(0, 1, base.shape), 0, 255).astype(np.uint8) for _ in range(60)]
    return {"V1_exposure_ramp": ramp, "V2_hard_cut": hard_cut, "V3_noise_step": noise, "V4_pan": pan, "V5_static": static}


def write_hex(path: Path, array: np.ndarray, digits: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    values = np.asarray(array).ravel()
    with path.open("w", encoding="ascii", newline="\n") as f:
        for value in values:
            f.write(f"{int(value) & ((1 << (4 * digits)) - 1):0{digits}x}\n")


def dump_result(outdir: Path, name: str, result: dict[str, np.ndarray | int], cfg: Config) -> dict[str, object]:
    """Emit per-stage RTL hex files and a manifest entry."""
    fields = (("gray", 2), ("smooth", 2), ("gx", 3), ("gy", 3), ("mag", 3), ("dir", 1), ("nms", 3), ("cls", 1), ("edge", 2))
    entry: dict[str, object] = {"name": name, "config": asdict(cfg), "margin": result["margin"], "files": {}}
    for field, digits in fields:
        value = result[field]
        assert isinstance(value, np.ndarray)
        file_name = f"{name}_{field}.hex"
        write_hex(outdir / file_name, value, digits)
        entry["files"][field] = file_name
    edge = result["edge"]
    assert isinstance(edge, np.ndarray)
    entry["crc32"] = f"{frame_crc(edge):08x}"
    entry["sha256_edge_hex"] = hashlib.sha256((outdir / f"{name}_edge.hex").read_bytes()).hexdigest()
    return entry


def selftest() -> bool:
    cfg = Config()
    flat = np.full((32, 40), 91, dtype=np.uint8)
    result = edge_frame(flat, cfg)
    checks = [
        (int(result["mag"].sum()) == 0, "flat image has zero magnitude"),
        (int(result["edge"].sum()) == 0, "flat image has no edges"),
        (frame_crc(result["edge"]) == zlib.crc32(bytes(32 * 40)), "CRC uses zero/FF edge bytes"),
    ]
    for ok, description in checks:
        print(("PASS" if ok else "FAIL"), description)
    return all(ok for ok, _ in checks)


def _main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("selftest", "describe"))
    args = parser.parse_args()
    if args.command == "selftest":
        raise SystemExit(0 if selftest() else 1)
    print(json.dumps(asdict(Config()), indent=2))


if __name__ == "__main__":
    _main()

