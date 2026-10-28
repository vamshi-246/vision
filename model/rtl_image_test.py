#!/usr/bin/env python3
"""Prepare and score a full-frame, bit-exact RTL image regression.

This program is deliberately split into ``prepare`` and ``report`` so the RTL
simulator is the only producer of ``*_rtl_output.hex``.

Typical use:
  python -m model.rtl_image_test prepare photo.jpg --outdir randomtests --name photo
  vvp build/tb_image_scoreboard +INPUT_HEX=randomtests/photo_input.hex +OUT_HEX=randomtests/photo_rtl_output.hex
  python -m model.rtl_image_test report --outdir randomtests --name photo
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import cv2
import numpy as np

from model.golden import Config, edge_bytes, edge_frame, frame_crc, resize_gray, write_hex

WIDTH = 640
HEIGHT = 480


def _read_gray(path: Path) -> np.ndarray:
    bgr = cv2.imread(str(path), cv2.IMREAD_COLOR)
    if bgr is None:
        raise ValueError(f"cannot read image: {path}")
    return resize_gray(cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB), WIDTH, HEIGHT)


def prepare(image_path: Path, outdir: Path, name: str, cfg: Config) -> dict[str, object]:
    """Write 640x480 grayscale input and byte-encoded golden edge expected map."""
    cfg.check()
    outdir.mkdir(parents=True, exist_ok=True)
    gray = _read_gray(image_path)
    result = edge_frame(gray, cfg)
    expected_bytes = np.frombuffer(edge_bytes(result["edge"]), dtype=np.uint8).reshape(HEIGHT, WIDTH)
    input_file = outdir / f"{name}_input.hex"
    expected_file = outdir / f"{name}_expected_output.hex"
    write_hex(input_file, gray, 2)
    write_hex(expected_file, expected_bytes, 2)
    manifest: dict[str, object] = {
        "image_source": str(image_path),
        "resolution": {"width": WIDTH, "height": HEIGHT},
        "encoding": {"input": "8-bit grayscale 00..ff", "output": "00=no edge, ff=strong edge"},
        "config": {"gauss_n": cfg.gauss_n, "thr_lo": cfg.thr_lo, "thr_hi": cfg.thr_hi, "hyst_k": cfg.hyst_k,
                   "dir_num": cfg.dir_num, "dir_den": cfg.dir_den},
        "golden": {
            "final_margin_pixels": int(result["margin"]),
            "nms_survivors": int(np.count_nonzero(result["nms"])),
            "weak_pixels": int(np.count_nonzero(result["cls"] == 1)),
            "strong_edges": int(np.count_nonzero(result["edge"])),
            "crc32": f"{frame_crc(result["edge"]):08x}",
        },
        "files": {"input_hex": input_file.name, "expected_output_hex": expected_file.name,
                  "rtl_output_hex": f"{name}_rtl_output.hex"},
    }
    (outdir / f"{name}_manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    return manifest


def _load_hex(path: Path) -> np.ndarray:
    values = np.fromiter(
        (int(line.strip(), 16) for line in path.read_text(encoding="ascii").splitlines() if line.strip()),
        dtype=np.uint8,
    )
    if values.size != WIDTH * HEIGHT:
        raise ValueError(f"{path} has {values.size} pixels; expected {WIDTH * HEIGHT}")
    return values.reshape(HEIGHT, WIDTH)


def report(outdir: Path, name: str) -> dict[str, object]:
    """Compare RTL-written output with golden data and create the single report."""
    manifest_path = outdir / f"{name}_manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    expected = _load_hex(outdir / str(manifest["files"]["expected_output_hex"]))
    actual_path = outdir / str(manifest["files"]["rtl_output_hex"])
    actual = _load_hex(actual_path)
    mismatch = expected != actual
    mismatch_count = int(np.count_nonzero(mismatch))
    first: list[dict[str, int]] = []
    for y, x in np.argwhere(mismatch)[:50]:
        first.append({"x": int(x), "y": int(y), "expected_hex": int(expected[y, x]), "rtl_hex": int(actual[y, x])})
    expected_edge = expected != 0
    actual_edge = actual != 0
    report_data: dict[str, object] = {
        "match": mismatch_count == 0,
        "pixel_mismatches": mismatch_count,
        "match_percent": 100.0 * (1.0 - mismatch_count / expected.size),
        "expected_strong_edges": int(np.count_nonzero(expected_edge)),
        "rtl_strong_edges": int(np.count_nonzero(actual_edge)),
        "expected_crc32": f"{frame_crc(expected_edge):08x}",
        "rtl_crc32": f"{frame_crc(actual_edge):08x}",
        "first_mismatches": first,
    }
    summary = [
        f"# RTL image-regression report: {name}",
        "",
        "## Summary",
        "",
        f"- **Result:** {'PASS — bit exact match' if report_data['match'] else 'FAIL — mismatch detected'}",
        f"- **Source image:** `{manifest['image_source']}`",
        f"- **Resolution:** 640×480 (307,200 pixels)",
        f"- **Input encoding:** {manifest['encoding']['input']}",
        f"- **Output encoding:** {manifest['encoding']['output']}",
        f"- **Input hex:** `{manifest['files']['input_hex']}`",
        f"- **Golden expected-output hex:** `{manifest['files']['expected_output_hex']}`",
        f"- **RTL output hex:** `{manifest['files']['rtl_output_hex']}`",
        "",
        "## Algorithm/configuration",
        "",
        "- Fixed-point grayscale → exact 3×3 Gaussian → Sobel L1 magnitude → four-direction quantisation → asymmetric NMS → double threshold.",
        f"- Gaussian: {manifest['config']['gauss_n']}×{manifest['config']['gauss_n']}; thresholds: low={manifest['config']['thr_lo']}, high={manifest['config']['thr_hi']}; hysteresis K={manifest['config']['hyst_k']}.",
        f"- Direction comparator: {manifest['config']['dir_den']}·|Gy| ≤ {manifest['config']['dir_num']}·|Gx| (and reciprocal vertical test).",
        f"- Forced-zero final border margin: {manifest['golden']['final_margin_pixels']} pixels.",
        "",
        "## Detailed results",
        "",
        f"| Metric | Golden | RTL |",
        f"| --- | ---: | ---: |",
        f"| NMS survivors | {manifest['golden']['nms_survivors']} | n/a (not exported) |",
        f"| Weak threshold pixels | {manifest['golden']['weak_pixels']} | n/a (final edge hex encodes strong only) |",
        f"| Strong edge pixels | {report_data['expected_strong_edges']} | {report_data['rtl_strong_edges']} |",
        f"| Edge-map CRC32 | `{report_data['expected_crc32']}` | `{report_data['rtl_crc32']}` |",
        f"| Pixel mismatches | 0 | {report_data['pixel_mismatches']} |",
        f"| Match rate | 100.000000% | {report_data['match_percent']:.6f}% |",
        "",
        "## First mismatches (maximum 50)",
        "",
    ]
    if first:
        summary.extend(["| x | y | Expected | RTL |", "| ---: | ---: | ---: | ---: |"])
        summary.extend(f"| {p['x']} | {p['y']} | `0x{p['expected_hex']:02x}` | `0x{p['rtl_hex']:02x}` |" for p in first)
    else:
        summary.append("None. Every output byte matches the software golden map.")
    summary.extend(["", "## Reproduction", "", "```powershell",
                    f"python -m model.rtl_image_test prepare \"{manifest['image_source']}\" --outdir {outdir} --name {name}",
                    "# Compile/run tb/system/tb_image_scoreboard.sv, then:",
                    f"python -m model.rtl_image_test report --outdir {outdir} --name {name}", "```,".rstrip(","), ""])
    report_path = outdir / f"{name}_rtl_comparison.md"
    report_path.write_text("\n".join(summary), encoding="utf-8")
    return report_data


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    prep = sub.add_parser("prepare")
    prep.add_argument("image", type=Path)
    prep.add_argument("--outdir", type=Path, default=Path("randomtests"))
    prep.add_argument("--name", default="image")
    prep.add_argument("--thr-lo", type=int, default=80)
    prep.add_argument("--thr-hi", type=int, default=200)
    rep = sub.add_parser("report")
    rep.add_argument("--outdir", type=Path, default=Path("randomtests"))
    rep.add_argument("--name", default="image")
    args = parser.parse_args()
    if args.command == "prepare":
        print(json.dumps(prepare(args.image, args.outdir, args.name, Config(thr_lo=args.thr_lo, thr_hi=args.thr_hi)), indent=2))
    else:
        print(json.dumps(report(args.outdir, args.name), indent=2))


if __name__ == "__main__":
    main()
