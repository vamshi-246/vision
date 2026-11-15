import json
from pathlib import Path
import subprocess
import sys

import cv2
import numpy as np
import pytest

from model.golden import Config
from model.rtl_image_test import prepare


def test_image_regression_rejects_unsupported_rtl_configuration(tmp_path):
    with pytest.raises(ValueError,match="only the baseline"):
        prepare(tmp_path/"unused.png",tmp_path/"out","test",Config(gauss_n=5))


def test_report_cli_exits_unsuccessfully_on_a_single_pixel_mismatch(tmp_path):
    source=tmp_path/"flat.png"
    assert cv2.imwrite(str(source),np.full((9,11,3),91,np.uint8))
    out=tmp_path/"out"
    prepare(source,out,"flat",Config())
    expected=(out/"flat_expected_output.hex").read_text()
    (out/"flat_rtl_output.hex").write_text("ff"+expected[2:])
    root=Path(__file__).resolve().parents[2]
    result=subprocess.run([sys.executable,"-m","model.rtl_image_test","report","--outdir",str(out),"--name","flat"],cwd=root,capture_output=True,text=True)
    assert result.returncode==1,result.stderr
    assert json.loads(result.stdout)["pixel_mismatches"]==1
