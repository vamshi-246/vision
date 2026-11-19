# Safe version: Zybo Z7-10, still-image edge-detection demo
Hardware-verified 2026-11-20 on a Zybo Z7-10 (HDMI TX -> monitor): picture shown, JTAG upload read-back PASS (76800 bytes),
RV32 firmware running, CPU edge count 4991 and 64-bin histogram match the model.
Program: `P7_BOARD=zybo_z7 P7_HW_DEBUG=1 vivado -mode batch -source scripts/program_hdmi.tcl`
Then: `build/venv/bin/python scripts/fpga_image.py send <photo.jpg>`
Bitstream SHA256: 698825d727563befe8841dac92b042cb98fb21d67d4a5900a4a7bb776abf106b
Git tag: `safe-z7-still-v1`. Return here if live-video work breaks anything.
