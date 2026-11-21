# ILA capture on the Zybo Z7 (for the report screenshot)

The ILA build is the normal still-image design (HDMI out on J11, JTAG photo upload, RV32 CPU) plus one Integrated Logic Analyzer
on the 25.175 MHz pixel clock. The demo bitstreams are not changed by it.

| ILA probe | signal | meaning |
|---|---|---|
| sof, sde, eol | core input strobes | start of frame, pixel valid (display enable), end of line |
| gray[7:0] | core input pixel | the uploaded photo (or test pattern) |
| sobel_valid, sobel_mag[10:0], sobel_dir[1:0] | inside the core | Sobel L1 magnitude and quantised direction (0=0°,1=45°,2=90°,3=135°) |
| cv, cs, ce | core output strobes | classified pixel valid / start of frame / end of line |
| cx[9:0], cy[8:0] | core output coordinates | position of the classified pixel |
| cls[1:0] | core output | 0 = none, 1 = weak, 2 = strong edge |
| lo, hi | thresholds in use | from the switches or from the RV32 firmware |
| running_edges[19:0] | edge counter | strong edges so far in this frame |

## Steps (about 10 minutes, at the board)

1. Build once (≈20 min, already done if `build/hdmi_z7_ila/zybo_edge_hdmi.ltx` exists):

```bash
make ila VIVADO=/tools/Xilinx/Vivado/2024.2/bin/vivado
```

2. Power the Zybo Z7, USB-JTAG cable in, monitor on J11 (HDMI TX). Program the ILA bitstream:

```bash
P7_BOARD=zybo_z7 /tools/Xilinx/Vivado/2024.2/bin/vivado -mode batch -nojournal -nolog -source scripts/ila_capture.tcl -tclargs program
```

3. Upload a photo (the monitor shows it; set switches SW1:SW0 = 11 for the class view):

```bash
build/venv/bin/python scripts/fpga_image.py send demo_photos/amar.png
```

4. Open the Vivado GUI with the capture already armed, triggered and displayed:

```bash
P7_BOARD=zybo_z7 /tools/Xilinx/Vivado/2024.2/bin/vivado -mode gui -nojournal -nolog -source scripts/ila_capture.tcl -tclargs capture 240
```

The trigger is `cv == 1 && cy == 240 && cx == 3`: the first classified pixel of the middle output row. The waveform window opens
with all 16 probes (unsigned radix). Zoom to about 100–200 samples around the trigger (the red marker) so the `gray`,
`sobel_mag`, `cls` values are readable, then take the screenshot (Print Screen) and save it as `report/ila.png`.

To capture again from the GUI: Hardware Manager → hw_ila_1 → "Run trigger" (▶). Other rows: change the `cy` compare value in the
Trigger Setup window, or re-run step 4 with another row number.

The capture is also written to `build/hdmi_z7_ila/capture.ila` (re-open in Vivado: `read_hw_ila_data` + `display_hw_ila_data`)
and `capture.csv`.
