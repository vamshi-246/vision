from __future__ import annotations

import cv2
import numpy as np

from model.run_image import run_image


def test_run_image_writes_evaluation_artifacts(tmp_path):
    source = np.zeros((16, 18, 3), dtype=np.uint8)
    source[:, 9:] = (255, 255, 255)
    input_path = tmp_path / "step.png"
    assert cv2.imwrite(str(input_path), source)
    report = run_image(input_path, tmp_path / "out", resize=(18, 16))
    assert report["output_resolution"] == {"width": 18, "height": 16}
    assert report["strong_edges"] > 0
    for filename in report["outputs"].values():
        assert (tmp_path / "out" / filename).is_file()
    assert (tmp_path / "out" / "results.json").is_file()
