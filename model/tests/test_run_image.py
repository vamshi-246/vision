from __future__ import annotations

import cv2
import numpy as np

from model.run_image import run_image
from model.golden import edge_frame


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


def test_no_resize_preserves_contract_rgb_weighting(tmp_path):
    rgb=np.random.default_rng(291).integers(0,256,(13,17,3),dtype=np.uint8)
    source=tmp_path/"rgb.png"
    assert cv2.imwrite(str(source),cv2.cvtColor(rgb,cv2.COLOR_RGB2BGR))
    run_image(source,tmp_path/"out",resize=None)
    actual=cv2.imread(str(tmp_path/"out/input_gray.png"),cv2.IMREAD_GRAYSCALE)
    np.testing.assert_array_equal(actual,edge_frame(rgb)["gray"])
