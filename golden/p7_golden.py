#!/usr/bin/env python3
"""Compatibility entry point for the active RTL contract in model/golden.py.

The original root-level 'p7 golden.py' is legacy evidence and has different
borders, direction constants and hysteresis semantics. It is not the RTL oracle.
"""
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from model.golden import *  # noqa: F401,F403
from model.golden import _main

if __name__ == "__main__":
    _main()

