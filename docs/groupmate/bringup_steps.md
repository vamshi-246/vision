# Bring-up on the Zybo Z7-10 (to be done by hand - nothing here has been run on hardware)

**Status of this package.** No Vivado and no board were available while this package was produced. The Vivado scripts in
`scripts/vivado/` and the Clocking-Wizard TCL have therefore **never been executed**; the HDMI/ILA parts are untested.
Everything that could be run (iverilog simulation of the whole demo data path, Yosys resource estimates, NuSMV) was run and is
reported in `doc/FINAL_MAIN_PIPELINE_REPORT.md`. Expect to fix small tool-version issues when you run the scripts first
(for example the `clk_wiz` IP version number in `scripts/vivado/make_clkwiz.tcl`).

## 1. Build
1. Install Vivado (any 2020.x - 2023.x), open a shell in the project folder.
2. `vivado -mode batch -source scripts/vivado/build_all.tcl` (10-20 min). Outputs `build/zybo_top.bit` and the reports.
3. Open `build/post_route_timing_summary.rpt`: **WNS and WHS must both be >= 0** (all constraints met). If not, do not program.
4. Open the Clocking Wizard summary (IP Sources > clk_wiz_0) and write down the real output frequencies (target 25.175 and 125.875 MHz).
   The MMCM cannot hit them exactly; 25.2 MHz +/-0.5 % is accepted by monitors (VESA tolerance).

## 2. Program
1. Connect the board with USB (PROG/UART), HDMI cable from the board's HDMI **OUT** connector (the transmit one, not HDMI IN) to a monitor. Check the board's boot-mode jumper is set for JTAG programming (see the Zybo Z7 reference manual).
2. Vivado > Open Hardware Manager > Open Target > Auto Connect.
3. Right-click `xc7z010_1` > Program Device > bitstream `build/zybo_top.bit` (probe file `build/zybo_top.ltx` if you built with ILA).
4. Expected: the monitor shows a 640x480 picture; LD1 lights (core locked) within one frame; LD0 blinks (~1.8 Hz).
5. SW0/SW1: 00 original, 01 smoothed, 10 edges (white = strong, grey = weak), 11 edge overlay in red. SW2 toggles the threshold preset
   (the edge map visibly gets sparser). The picture alternates between two test images every 128 frames (~2.1 s).

## 3. ILA (click by click)
`scripts/vivado/add_ila.tcl` is sourced by `build_all.tcl` automatically and marks the debug nets (`o_cls`, `o_locked`, `o_sync_err`,
`o_frame_end`, APB `psel/penable/pwdata`, `vid_de`, `vid_vs`) on the 25.175 MHz clock. If you prefer the GUI:

1. After synthesis: Flow Navigator > Synthesis > **Open Synthesized Design**.
2. Menu Tools > **Set Up Debug**. Next.
3. In the net list click **Find Nets to Add...** > filter "Name contains `u_demo/o_cls`" > Find > Select all > OK. Repeat for `o_locked`, `o_frame_end`, `psel`, `penable`.
4. Next > Clock domain: pick `pclk` (output of clk_wiz_0, 25.175 MHz) for all probes > Next.
5. Sample depth 4096, tick "Capture control" and "Advanced trigger" > Next > Finish. Save constraints (Ctrl+S) when asked (this writes `debug` constraints to your XDC copy, not to `constraints/zybo.xdc` unless you tell it to).
6. Run Implementation, Generate Bitstream, then program the device as in section 2 and tick the `.ltx` file.
7. In the Hardware window `hw_ila_1` > Trigger Setup: `+` > `u_demo/o_frame_end` == `R` (rising) > Run Trigger (the play-with-arrow icon).
8. Expected: a trigger fires about once per frame (every 16.7 ms); in the waveform `o_locked`=1 and `o_cls` toggles between 0/1/2 inside the active region.
9. APB check: trigger on `psel` == 1 (flip SW2 first): see two writes (PADDR 0x04 then 0x08, PWDATA = 300/120 or 192/64).
