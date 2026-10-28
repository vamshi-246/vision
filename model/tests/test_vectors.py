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
