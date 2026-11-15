#!/usr/bin/env python3
"""Generate deterministic per-stage hex vectors and a CRC manifest for RTL.

The exporter intentionally delegates all arithmetic to ``model.golden``.  It
therefore cannot silently introduce a second image-processing interpretation.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Iterable

import numpy as np

from model.golden import Config, dump_result, edge_frame, natural_images, synthetic_images, write_hex


def generate(
    outdir: Path,
    images: Iterable[tuple[str, np.ndarray]],
    cfg: Config = Config(),
) -> dict[str, object]:
    """Write input/stage hex files and return the deterministic manifest."""
    outdir.mkdir(parents=True, exist_ok=True)
    entries: list[dict[str, object]] = []
    for name, image in images:
        result = edge_frame(image, cfg)
        write_hex(outdir / f"{name}_input.hex", result["gray"], 2)
        entry = dump_result(outdir, name, result, cfg)
        entry["files"]["input"] = f"{name}_input.hex"
        entries.append(entry)
    manifest: dict[str, object] = {
        "format": 1,
        "description": "Appendix-A golden per-stage raster-order hex vectors",
        "images": entries,
    }
    (outdir / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--outdir", type=Path, default=Path("tb/vectors/generated"))
    parser.add_argument("--width", type=int, default=640)
    parser.add_argument("--height", type=int, default=480)
    parser.add_argument("--set", choices=("synthetic", "natural", "all"), default="all")
    parser.add_argument("--limit", type=int, default=None, help="limit images for a quick local smoke run")
    args = parser.parse_args()
    image_set: list[tuple[str, np.ndarray]] = []
    if args.set in ("natural", "all"):
        image_set.extend(natural_images(args.width, args.height))
    if args.set in ("synthetic", "all"):
        image_set.extend(synthetic_images(args.width, args.height))
    if args.limit is not None:
        image_set = image_set[:args.limit]
    manifest = generate(args.outdir, image_set)
    print(f"PASS wrote {len(manifest['images'])} vector sets to {args.outdir}")


if __name__ == "__main__":
    main()
