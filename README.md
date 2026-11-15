# vision - real-time edge-detection video pipeline on a Zynq FPGA

A streaming, Canny-style edge detector in SystemVerilog that processes **640x480 video at 60 Hz, one pixel per clock**, shows its result over
**HDMI/DVI**, takes **photos from a laptop over the JTAG cable**, and is supervised by a small **RISC-V (RV32) CPU** that reads the pipeline's
statistics and sets its thresholds. Course project P7 (RTL Design and Verification, IIT Mandi).

```
photo (laptop) --JTAG--> 320x240 frame store (BRAM) --2x--> grayscale -> Gaussian 3x3 -> Sobel |Gx|+|Gy| + direction -> NMS -> double threshold
                                                                                                     |                          |
                                              monitor <-- HDMI <-- views: original / smoothed / edges / classes     APB registers <--> PicoRV32 (RV32I)
```

**Hardware-tested on the original Digilent Zybo** (xc7z010clg400-1). The **Zybo Z7-10** variant builds and passes functional netlist simulation
but has **not** been run on a board. Full results, evidence and limitations: **[docs/FINAL_REPORT.md](docs/FINAL_REPORT.md)**.

## Highlights
* Bit-exact against a Python/NumPy golden model: 33 frames at 640x480 (incl. 10 natural/synthetic corpus images), exhaustive 4.17-million-case
  direction test, deliberate-bug (mutation) checks, routed-netlist TMDS simulation.
* Hand-HLS Sobel (shared subexpressions, 8 adders, 4-stage II=1 schedule) and an **Espresso-minimised** direction/NMS-select block (10 terms/40 literals -> 4/10).
* 2,108 LUT / 3,080 FF / 3 BRAM tiles / 0 DSP for the core; whole board design meets timing at 25.18 MHz with margin.
* CTL model checking (NuSMV) of the shipped raster-timing RTL + mutants; comparison against the adaptive-Otsu edge detector of Guo & Wu (2023).
* A PicoRV32 firmware (600 bytes) reads the edge count and all 64 histogram bins and applies thresholds; the laptop can override them live.

## Quick start (original Zybo)
```bash
python3 -m venv build/venv && build/venv/bin/pip install -r requirements-verification.txt   # + pillow
make -C fw                                                                                 # firmware (needs the xPack RISC-V GCC in build/tools)
P7_BOARD=zybo vivado -mode batch -source scripts/build_hdmi.tcl                            # bitstream (Vivado 2024.2)
P7_BOARD=zybo P7_HW_DEBUG=1 vivado -mode batch -source scripts/program_hdmi.tcl            # program over JTAG
build/venv/bin/python scripts/fpga_image.py send my_photo.jpg                              # upload, start the CPU, verify against the model
build/venv/bin/python scripts/fpga_image.py threshold 30 90                                # laptop sets edge thresholds (0..2047)
```
Switches/buttons, troubleshooting and a talking script for a live demo: **[docs/DEMO_GUIDE.md](docs/DEMO_GUIDE.md)**.
Use `P7_BOARD=zybo_z7` for the Zybo Z7-10 build (untested on hardware). Both boards share the same FPGA ID, so the programming script refuses to run
without `P7_BOARD`.

## Verify without hardware
```bash
make verify      # unit benches, stress, full-frame core regression, video regression, RV32 SoC acceptance test, CTL proofs
make espresso    # regenerate rtl/dir_decide.sv with Espresso
make study       # paper/baseline/resource comparison (needs Vivado for the resource numbers)
```

## Repository map
| Path | Contents |
|---|---|
| `rtl/` | pipeline core: `linebuf`, `gauss`, `sobel` (+ generated `dir_decide`), `dirnms`, `classify_hist`, `apb_regs`, `vga_timing`, `top` (`edge_pipeline`) |
| `rtl/video/` | board top (`zybo_hdmi_top`), `edge_video`, `video_soc`, `frame_store`, `video_delay` |
| `rtl/soc/`, `fw/` | PicoRV32 subsystem (RAM, mailbox, APB master) and its C firmware |
| `rtl/study/` | paper's adaptive-Otsu engine (supplied reference RTL), generated PAPER system and BASELINE for the comparison |
| `model/` | Python golden model, test corpus, vector generators |
| `tb/` , `scripts/` | testbenches; regressions, upload tool, Vivado flows, report generator |
| `formal/`, `logic/`, `hls/` | CTL proofs (RTL-derived + abstract), Espresso flow, hand-HLS derivation |
| `fpga/` | constraints for both boards |
| `third_party/` | Digilent `rgb2dvi` (HDMI/DVI transmitter, BSD), PicoRV32 (ISC) - unmodified, with licences |
| `study/groupmate/`, `docs/groupmate/` | preserved parts of the team-mate's independent implementation and documents |
| `docs/` | **FINAL_REPORT**, DEMO_GUIDE, MERGE_STATUS, core review, older notes in `docs/archive/` |

## Status and honest limitations
* Post-route **SDF timing simulation is unresolved** (boards are programmed with `P7_HW_DEBUG=1`); static timing, CDC/DRC and functional netlist simulation pass.
* **No DDR/DMA, no camera**: photos are stored at 320x240 in on-chip BRAM (a full 8-bit 640x480 frame does not fit) and shown 2x enlarged.
* Zybo Z7-10 not run on hardware. The APB CRC register is not wired to a CRC of the edge map.
* The paper comparison uses the paper's adaptive-threshold *engine* only; see section 6 of the report for exactly what is and is not reproduced.

## Credits and licences
Written by the two team members (main tree and an independent implementation, merged here - see `docs/MERGE_STATUS.md`) with AI assistance (Claude Code).
Third-party code keeps its own licence: Digilent `rgb2dvi` (BSD-style, `third_party/rgb2dvi`), PicoRV32 (ISC, `third_party/picorv32`); the Zybo constraint
files derive from Digilent's master XDCs. No licence has been chosen for the project's own code yet.
