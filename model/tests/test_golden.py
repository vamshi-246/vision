import hashlib
import zlib

import numpy as np

from model.golden import Config, edge_frame, frame_crc, full_hysteresis, hysteresis_k, nms_frame, quantise_direction


def test_flat_image_has_no_response():
    result = edge_frame(np.full((48, 64), 91, np.uint8))
    assert result["mag"].max() == 0
    assert result["edge"].sum() == 0


def test_three_pixel_border_is_forced_zero():
    image = np.zeros((40, 48), np.uint8)
    image[0, :] = 255
    image[:, 0] = 255
    result = edge_frame(image)
    edge = result["edge"]
    assert not edge[:3, :].any()
    assert not edge[-3:, :].any()
    assert not edge[:, :3].any()
    assert not edge[:, -3:].any()
    assert result["margin"] == 3


def test_direction_boundary_and_sign_rules():
    cfg = Config()
    gx = np.array([[32, 0, 10, -10]], dtype=np.int16)
    gy = np.array([[13, 32, 10, 10]], dtype=np.int16)
    # h equality -> horizontal, v equality -> vertical, equal signs -> \\, unlike -> /.
    assert quantise_direction(gx, gy, cfg).tolist() == [[0, 2, 1, 3]]


def test_nms_keeps_raster_later_end_of_a_horizontal_plateau():
    mag = np.zeros((12, 16), np.uint16)
    direction = np.zeros_like(mag, dtype=np.uint8)
    mag[6, 5:8] = 100
    out = nms_frame(mag, direction, input_margin=2)
    assert np.flatnonzero(out[6]).tolist() == [7]


def test_k_stage_hysteresis_has_bounded_geodesic_reach():
    cls = np.zeros((9, 11), np.uint8)
    cls[4, 2] = 2
    cls[4, 3:7] = 1
    assert hysteresis_k(cls, 0)[4, 3] == 0
    assert hysteresis_k(cls, 1)[4, 3] == 1
    assert hysteresis_k(cls, 3)[4, 5] == 1
    assert hysteresis_k(cls, 3)[4, 6] == 0
    assert full_hysteresis(cls)[4, 6] == 1


def test_crc_matches_python_zlib_definition():
    edge = np.array([[0, 1, 0], [1, 1, 0]], dtype=np.uint8)
    expected = zlib.crc32(bytes((0, 255, 0, 255, 255, 0))) & 0xFFFFFFFF
    assert frame_crc(edge) == expected


def test_deterministic_hash_on_directed_image():
    image = np.zeros((48, 64), np.uint8)
    image[:, 32:] = 200
    first = edge_frame(image, Config(thr_lo=20, thr_hi=40))
    second = edge_frame(image, Config(thr_lo=20, thr_hi=40))
    assert hashlib.sha256(first["edge"].tobytes()).digest() == hashlib.sha256(second["edge"].tobytes()).digest()

