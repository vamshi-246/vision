from __future__ import annotations

import json

import numpy as np

from model.gen_vectors import generate
from model.golden import Config, edge_frame, frame_crc


def test_vector_exporter_writes_stage_files_and_crc_manifest(tmp_path):
    image = np.zeros((12, 14), dtype=np.uint8)
    image[:, 7:] = 255
    manifest = generate(tmp_path, [("step", image)], Config(thr_lo=80, thr_hi=200))
    disk_manifest = json.loads((tmp_path / "manifest.json").read_text(encoding="utf-8"))
    assert disk_manifest == manifest
    entry = manifest["images"][0]
    result = edge_frame(image, Config(thr_lo=80, thr_hi=200))
    expected_crc = frame_crc(result["edge"])
    assert entry["crc32"] == f"{expected_crc:08x}"
    for file_name in entry["files"].values():
        assert (tmp_path / file_name).is_file()


def test_rgb_vectors_export_one_grayscale_sample_per_pixel(tmp_path):
    rgb=np.random.default_rng(789).integers(0,256,(9,11,3),dtype=np.uint8)
    generate(tmp_path,[("rgb",rgb)])
    lines=(tmp_path/"rgb_input.hex").read_text().splitlines()
    actual=np.array([int(x,16) for x in lines],np.uint8).reshape(9,11)
    np.testing.assert_array_equal(actual,edge_frame(rgb)["gray"])
