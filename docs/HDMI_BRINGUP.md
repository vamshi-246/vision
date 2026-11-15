# HDMI bring-up (current)

Everything current lives in two documents:
* **docs/DEMO_GUIDE.md** - step-by-step: programming, uploading a photo, switches/buttons, troubleshooting.
* **docs/FINAL_REPORT.md** - build/timing/resource numbers, verification, boards.

Key facts for bring-up:
* Boards: `P7_BOARD=zybo` (original Digilent Zybo, one HDMI I/O port J8, 125 MHz clock on L16, `hdmi_out_en` F17 driven high) is hardware-tested.
  `P7_BOARD=zybo_z7` (Zybo Z7-10, HDMI TX connector, clock K17) is built and simulated but **not yet run on a board**.
  Both share the xc7z010 JTAG ID, so `scripts/program_hdmi.tcl` refuses to run without `P7_BOARD`.
* The Ethernet PHY supplies the 125 MHz reference on both boards, so the design drives `eth_rst_b` (E17) high.
* Constraints: `fpga/zybo_hdmi.xdc` (original Zybo), `fpga/zybo_z7_hdmi.xdc` (Z7). Build: `P7_BOARD=<board> vivado -mode batch -source scripts/build_hdmi.tcl`.
* Output is DVI-compatible RGB (no audio, no EDID/HPD handling, fixed 640x480@59.95 Hz from a 25.178571 MHz pixel clock).
* The first Zybo bring-up failed (no LEDs) because Z7 pins had been used on the original Zybo; LD0 (MMCM lock) not lighting is the quick symptom of a wrong clock pin.
* Open: post-route SDF timing simulation; programming uses `P7_HW_DEBUG=1` until it is resolved.
