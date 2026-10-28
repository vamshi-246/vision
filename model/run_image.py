#!/usr/bin/env python3
"""Run the Appendix-A software model on one image and save visual evidence.

Examples
--------
python -m model.run_image my_photo.jpg
python -m model.run_image my_photo.png --outdir results/demo --thr-lo 60 --thr-hi 180
python -m model.run_image my_photo.png --no-resize
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import cv2
import numpy as np

from model.golden import Config, edge_frame, frame_crc, resize_gray


def _write_png(path: Path, image: np.ndarray) -> None:
    if not cv2.imwrite(str(path), image):
        raise RuntimeError(f"could not write {path}")


def _label(image: np.ndarray, text: str) -> np.ndarray:
    labelled = image.copy()
    cv2.rectangle(labelled, (0, 0), (180, 28), (0, 0, 0), thickness=-1)
    cv2.putText(labelled, text, (8, 20), cv2.FONT_HERSHEY_SIMPLEX, 0.58, (255, 255, 255), 1, cv2.LINE_AA)
    return labelled


def run_image(
    input_path: Path,
    outdir: Path,
    cfg: Config = Config(),
    resize: tuple[int, int] | None = (640, 480),
) -> dict[str, object]:
    """Execute the contract model and write visual and machine-readable results."""
    raw_bgr = cv2.imread(str(input_path), cv2.IMREAD_COLOR)
    if raw_bgr is None:
        raise ValueError(f"cannot read image: {input_path}")
    # golden._u8_gray defines the RGB weighting, while OpenCV returns BGR.
    raw_rgb = cv2.cvtColor(raw_bgr, cv2.COLOR_BGR2RGB)
    image = resize_gray(raw_rgb, *resize) if resize else cv2.cvtColor(raw_bgr, cv2.COLOR_BGR2GRAY)
    result = edge_frame(image, cfg)
    outdir.mkdir(parents=True, exist_ok=True)

    gray = result["gray"].astype(np.uint8)
    smooth = result["smooth"].astype(np.uint8)
    magnitude = result["mag"].astype(np.uint16)
    nms = result["nms"].astype(np.uint16)
    classes = result["cls"].astype(np.uint8)
    edges = result["edge"].astype(np.uint8)
    max_mag = max(1, (1 << cfg.mag_bits) - 1)
    magnitude_png = cv2.applyColorMap(cv2.convertScaleAbs(magnitude, alpha=255.0 / max_mag), cv2.COLORMAP_TURBO)
    nms_png = cv2.applyColorMap(cv2.convertScaleAbs(nms, alpha=255.0 / max_mag), cv2.COLORMAP_TURBO)
    classes_png = np.zeros((*classes.shape, 3), dtype=np.uint8)
    classes_png[classes == 1] = (0, 191, 255)  # weak: amber in OpenCV BGR
    classes_png[classes == 2] = (255, 255, 255)  # strong: white
    edge_png = (edges * 255).astype(np.uint8)

    _write_png(outdir / "input_gray.png", gray)
    _write_png(outdir / "gaussian.png", smooth)
    _write_png(outdir / "magnitude.png", magnitude_png)
    _write_png(outdir / "nms.png", nms_png)
    _write_png(outdir / "classes.png", classes_png)
    _write_png(outdir / "edges.png", edge_png)
    panel_top = np.hstack((_label(cv2.cvtColor(gray, cv2.COLOR_GRAY2BGR), "Input grayscale"),
                           _label(cv2.cvtColor(smooth, cv2.COLOR_GRAY2BGR), "Gaussian 3x3"),
                           _label(magnitude_png, "Sobel L1 magnitude")))
    panel_bottom = np.hstack((_label(nms_png, "Non-max suppression"),
                              _label(classes_png, "Threshold classes"),
                              _label(cv2.cvtColor(edge_png, cv2.COLOR_GRAY2BGR), "Final strong edges")))
    _write_png(outdir / "result_panel.png", np.vstack((panel_top, panel_bottom)))

    metadata: dict[str, object] = {
        "input": str(input_path),
        "output_resolution": {"width": int(gray.shape[1]), "height": int(gray.shape[0])},
        "config": {
            "gauss_n": cfg.gauss_n,
            "thr_lo": cfg.thr_lo,
            "thr_hi": cfg.thr_hi,
            "hyst_k": cfg.hyst_k,
            "dir_num": cfg.dir_num,
            "dir_den": cfg.dir_den,
        },
        "final_margin_pixels": int(result["margin"]),
        "nms_survivors": int(np.count_nonzero(nms)),
        "weak_pixels": int(np.count_nonzero(classes == 1)),
        "strong_edges": int(np.count_nonzero(edges)),
        "edge_crc32": f"{frame_crc(edges):08x}",
        "outputs": {
            "panel": "result_panel.png",
            "input": "input_gray.png",
            "gaussian": "gaussian.png",
            "magnitude": "magnitude.png",
            "nms": "nms.png",
            "classes": "classes.png",
            "edges": "edges.png",
        },
    }
    (outdir / "results.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    return metadata


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path, help="input image (PNG, JPG, BMP, ...)")
    parser.add_argument("--outdir", type=Path, default=Path("results"), help="directory for PNGs and results.json")
    parser.add_argument("--thr-lo", type=int, default=80)
    parser.add_argument("--thr-hi", type=int, default=200)
    parser.add_argument("--hyst-k", type=int, default=0)
    parser.add_argument("--no-resize", action="store_true", help="retain the source image resolution")
    args = parser.parse_args()
    cfg = Config(thr_lo=args.thr_lo, thr_hi=args.thr_hi, hyst_k=args.hyst_k)
    cfg.check()
    report = run_image(args.image, args.outdir, cfg, None if args.no_resize else (640, 480))
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
