# Rebuilding the P7 live-video design in the Vivado GUI (Zybo Z7-10)

This guide rebuilds the hardware-verified **live webcam** design from scratch in the Vivado 2024.2 GUI. You create the project, add the RTL and the
IP cores, run the testbenches, build the bitstream and program the board, all without the build scripts.

Every step below was dry-run on 2026-11-20 in Vivado project mode, the same engine the GUI buttons drive. Results of that run:
- **Simulations:** `tb_rx_live`, `tb_core_regression` (31x23, 42 frames) and `tb_gauss` all print PASS.
- **Build:** synthesis, implementation and the bitstream complete.
- **Timing:** met, WNS +1.26 ns and WHS +0.03 ns.

**How hard is it?** It's moderate. There's no block design and no PS7/Vitis, only RTL plus four IP cores configured through dialogs.

| Phase | Your time | Tool time |
|---|---|---|
| Create the project and add sources | 15 min | |
| Configure the four IP cores | 20 min | 2 min |
| Simulations | 15 min | 2–6 min each |
| Synthesis + implementation + bitstream | | 8–12 min |
| Program and demo | 10 min | 1 min |

Plan about 1.5–2 hours the first time and about 45 minutes once you know it.

`<repo>` means the project folder (the one with `rtl/`, `tb/`, `fpga/`, `third_party/`).

---

## 0. Before you start
1. **Create the GUI project in a path without spaces**, for example `~/p7_gui`. The repository path (`IIT Mandi Academic Folder/...`) has
   spaces, and some simulator steps fail with spaces in a path. Always tick **Copy sources into project** when adding files. The copies then
   live in the space-free project folder.
2. **Regression vectors (optional, for section 4.2):** the image regression testbench reads golden vectors made by the Python model. If
   `<repo>/build/core_regression/31x23/` does not exist, run this once in a terminal:
   `cd <repo> && build/venv/bin/python scripts/core_regression.py --quick`.
   Then copy the `*.hex` files of `build/core_regression/31x23/` into `~/p7_gui/vectors_31x23/`. You can also copy `.../320x240/` (23 frames) for a
   bigger demo.

## 1. Create the project
1. Start Vivado 2024.2, then **Create Project**, then **Next**.
2. **Project name:** `p7_live`. **Location:** `~/p7_gui`. Tick *Create project subdirectory*.
3. Choose **RTL Project** and tick *Do not specify sources at this time*.
4. **Default Part:** select **Parts**, search `xc7z010clg400-1` and pick it (the Zybo Z7-10).
   You can also pick the Digilent board file if it's installed. The part is what matters.
5. Click **Finish**.
6. **Settings** (gear icon or *Tools > Settings*), then **General**, then set **Target language: Verilog**.

## 2. Add the IP repository (for Digilent's HDMI transmitter IP)
1. Open **Settings > IP > Repository** and click **+**, then select `<repo>/third_party`.
   Vivado reports the IPs it found, including *RGB to DVI Video Encoder (Source)*.
2. Click **OK**.

The HDMI **receiver** (`dvi2rgb`) is *not* used as a packaged IP. Its VHDL is added as plain sources in step 3, because the project uses a
locally modified copy that adds a debug port and the 800x600 EDID.

## 3. Add the design sources
1. In **Flow Navigator**, click **Add Sources**, then **Add or create design sources**, then **Add Files**.
2. Add the following files and tick **Copy sources into project**.

| Folder | Files |
|---|---|
| `<repo>/rtl/` | `linebuf.sv gauss.sv dir_decide.sv sobel.sv dirnms.sv classify_hist.sv top.sv vga_timing.sv apb_regs.sv` |
| `<repo>/rtl/video/` | `video_delay.sv edge_video.sv video_soc.sv frame_store.sv rx_timing.sv rx_downscale.sv zybo_hdmi_top.sv` |
| `<repo>/rtl/soc/` | `soc_ram.sv cpu_subsys.sv` |
| `<repo>/third_party/picorv32/` | `picorv32.v` |
| `<repo>/third_party/dvi2rgb/src/` | **all `*.vhd`** (14 files) **and `dgl_800x600.data`** (the EDID the receiver shows to the laptop) |

   Leave out `rtl/study/`, the `tb/` files (they go into simulation sets later) and the other `.data` EDID files.

3. **Add Sources > Add or create constraints > Add Files**, ticking **Copy constraints files into project**:
   - `<repo>/fpga/zybo_z7_hdmi.xdc`: board clock, switches, buttons, LEDs, HDMI TX pins.
   - `<repo>/fpga/zybo_z7_live_rx.xdc`: HDMI RX pins, the 40 MHz RX clock and the 125 MHz board clock, the receiver's IDELAY group,
     and the asynchronous clock groups.
   - `<repo>/fpga/zybo_z7_gui_extra.xdc`: clock uncertainty and unused-pin pull-ups. The scripted build sets these in Tcl.
4. **Turn on the live build:** open **Settings > General > Language Options > Verilog options > `...`**. Under **Defines**, click **+** and add
   `LIVE_RX` with value `1`.
   - **Why:** `zybo_hdmi_top.sv` contains the live path inside `` `ifdef LIVE_RX``. Without this define Vivado builds the still-image design and
     quietly drops the receiver files.
5. In **Sources**, right-click `zybo_hdmi_top` and choose **Set as Top**.

At this point the hierarchy shows four modules in red: `video_clocks`, `hdmi_tx`, `jtag_axi_master` and `frame_axi_ctrl`. Those are the IP
cores, made in the next step under exactly these names.

## 4. Create the four IP cores (IP Catalog)
For each one: open **IP Catalog**, search for the name, and double-click it. Set **Component Name** exactly as shown, because the RTL
instantiates it by that name. When asked to generate output products, choose **Synthesis Options: Global**, then **Generate**.

### 4.1 `video_clocks`: Clocking Wizard (pixel clock 25.175 MHz and 5x serial clock)
- **Clocking Options:**
  - Primitive **MMCM**.
  - **Input Clock Information**, Primary: input frequency **125.000** MHz, Source **No buffer**.
  - No buffer is used because the RTL has its own IBUF+BUFG, shared with the receiver's reference PLL.
- **Output Clocks:**
  - `clk_out1` = **25.175** MHz.
  - Tick `clk_out2` = **125.875** MHz.
  - Wizard reports pixel 25.178571 MHz, ratio exactly 5:1 (expected).
- **Output Clocks tab, bottom:**
  - Tick **reset** and **locked**.
  - Reset Type: **Active High**.
- **Port names:** keep the defaults (`clk_in1 reset clk_out1 clk_out2 locked`).

### 4.2 `hdmi_tx`: RGB to DVI Video Encoder (Source) (Digilent, from the repository you added)
- **Untick** *Generate SerialClk internally from pixel clock*. The serial clock comes from `video_clocks`.
- **Reset active high:** ticked.

### 4.3 `jtag_axi_master`: JTAG to AXI Master
- Defaults (AXI4, 32-bit data). This lets the laptop upload photos and firmware and read status over the USB-JTAG cable.

### 4.4 `frame_axi_ctrl`: AXI BRAM Controller
- AXI Protocol **AXI4**, Data Width **32**, Memory Depth **32768**.
- Number of BRAM interfaces **1**, ECC **none**, Read Latency **1**.
- Untick *Support narrow bursts* (if shown).

After all four, the hierarchy has no red modules.

## 5. Simulation (behavioural, Vivado Simulator)
Each testbench gets its own simulation set, so you can switch between them.

### 5.1 Live-input path: `tb_rx_live` (recommended first; about 3–6 min)
This is what it checks:
- A synthetic 800x600@60 HDMI raster goes through `rx_timing` (raster rebuild and gray conversion) and `rx_downscale` (2.5:1 decimation,
  4-pixel packing, async FIFO into the 25 MHz domain) into a model of the frame buffer.
- Reset is released mid-frame, so the half frame must be ignored.
- It then compares all 76,800 bytes of the next frame with the expected decimated grayscale picture.

Steps:
1. Open **Add Sources > Add or create simulation sources**, set **Specify simulation set: Create Simulation Set...** to `sim_live`, then
   **Add Files** `<repo>/tb/video/tb_rx_live.sv` (copy into project).
2. In the Sources window, under *Simulation Sources > sim_live*, right-click `tb_rx_live` and choose **Set as Top**. Then right-click `sim_live`
   and choose **Make active**.
3. Open **Settings > Simulation**, with Target simulation set `sim_live`. On the **Simulation** tab set `xsim.simulate.runtime` = `all`.
4. Click **Run Simulation > Run Behavioral Simulation**. The Tcl console ends with:
   ```
   frame 1: 19200 word writes so far, 0 byte mismatches, timing_bad=0
   TB_RX_LIVE PASS
   ```
5. **Waveforms to show:**
   - In the *Scope* panel, expand `tb_rx_live > front` (`rx_timing`) and drag `x`, `y`, `o_de`, `o_sof`, `gray` onto the wave window.
   - Expand `dut` (`rx_downscale`) and drag `keep`, `push`, `din`, then `valid`, `waddr`, `wdata` (the 25 MHz side).
   - Click **Restart** then **Run All**, or *Run for* `20 ms`.
   - Zoom on one line: `push` pulses on every 4th kept pixel, and on the 25 MHz side `waddr` steps by one per word.

### 5.2 Edge pipeline vs. the Python golden model: `tb_core_regression` (about 1–3 min at 31x23)
1. Create simulation set `sim_core` and add `<repo>/tb/system/tb_core_regression.sv`. Set it as top and make `sim_core` active.
2. Open **Settings > Simulation** for set `sim_core`:
   - **Compilation** tab: **Generics/Parameters options** = `W=31 H=23 FRAMES=42`. For `vectors_320x240` use `W=320 H=240 FRAMES=23`;
     that run takes longer.
   - **Elaboration** tab: `xsim.elaborate.xelab.more_options` = `-timescale 1ns/1ps`. Some RTL files have no `` `timescale`` line, and
     without this the elaborator stops.
   - **Simulation** tab: `xsim.simulate.xsim.more_options` = `-testplusarg BASE=/home/<you>/p7_gui/vectors_31x23 -testplusarg MODE=0`,
     and `xsim.simulate.runtime` = `all`.
3. Run Behavioral Simulation. Expected:
   `PASS core W=31 H=23 frames=42 mode=0 g=25578 s=21546 n=17850 out=17850 first_latency=203`.
   - It checks every pixel of every stage (Gaussian, Sobel magnitude and direction, NMS, classes, histogram) against the model.
   - `MODE=1` and `MODE=2` add input gaps and back-pressure-like stalls. They should also PASS.

### 5.3 Unit testbenches (seconds each)
In `sim_core`, also add `<repo>/tb/unit/tb_gauss.sv`, `tb_sobel.sv` and `tb_edge_pipeline.sv`. Set one as top, clear the generics field, and
run. Each prints `PASS tb_<name>`.

## 6. Synthesis, implementation, bitstream
1. **Flow Navigator > Generate Bitstream**. Say *Yes* to run synthesis and implementation first.
   - On an 8-core laptop it takes 8–12 min.
2. Open **Implemented Design > Report Timing Summary** to check the result:
   - All constraints are met. The dry run gave WNS +1.26 ns and WHS +0.03 ns.
   - **Utilization:** about 49 % LUTs and 24 of 60 RAMB36.
3. The file is `~/p7_gui/p7_live/p7_live.runs/impl_1/zybo_hdmi_top.bit`.

Warnings you can ignore: PS7 block required (no Zynq PS is used), unconnected `sl_iport0/sl_oport0` of the JTAG-AXI core, and
SLICE_PairEqSame DRC notes.

## 7. Program the board (Hardware Manager)
1. Connect the Zybo Z7:
   - Micro-USB into **PROG/UART**.
   - Power on.
   - Monitor on **HDMI TX**.
   - Laptop USB-C-to-HDMI cable into **HDMI RX (J10)**. Push it in firmly; a loose plug was the cause of one failed session.
2. Go to **Flow Navigator > Open Hardware Manager > Open Target > Auto Connect**, which finds `xc7z010_1`.
3. **Program Device**, then choose the `.bit` from section 6 and **Program**. Leave the probes file empty.
4. **On the laptop:**
   1. Unplug and replug the J10 cable once, so the laptop re-reads the board's EDID.
   2. Check the new display (`DP-1`) is 800x600; if not, run `xrandr --output DP-1 --mode 800x600 --scale 1x1`.
   3. Start the viewer: `python3 <repo>/scripts/live_camera.py`. **Keep that window open**: it is the video source, shown on the FPGA's display.
5. **What you should see:**
   - LD0 lit (clock locked), LD1 lit (video), LD2 blinking (frames), LD3 lit (live input active).
   - The monitor shows the live webcam.
   - SW1:0 = original / smoothed / strong edges / classes. SW3:2 = threshold presets. BTN2 = live off/on. BTN0 = reset.

Photo upload and the RV32 firmware still use the command-line tool: `build/venv/bin/python scripts/fpga_image.py send photo.jpg`.
It drives Vivado's hardware server itself, so close the GUI Hardware Manager first.

## 8. Building the still-image version instead (no live input)
Same project steps with three differences:
- **Define:** don't set the `LIVE_RX` define.
- **Sources:** don't add `rx_timing.sv`, `rx_downscale.sv`, the `dvi2rgb` files, `zybo_z7_live_rx.xdc` or `zybo_z7_gui_extra.xdc`. Do add the
  `set_clock_uncertainty` and `UNUSEDPIN Pullup` lines if you want identical settings.
- **Clocking Wizard:** set `video_clocks` input **Source = Single ended clock capable pin** (the default). Here the wizard owns the input
  buffer and creates the 125 MHz clock constraint.

## 9. Troubleshooting
| Symptom | Cause / fix |
|---|---|
| `module 'dvi2rgb' not found`, or receiver files greyed out | the `LIVE_RX=1` define is missing (section 3, step 4) |
| `module 'video_clocks' not found` | the IP component name differs from the RTL name, or output products were not generated |
| xelab: *module ... doesn't have a timescale* | add `-timescale 1ns/1ps` to the elaboration options (5.2) |
| simulator cannot find files / "Mandi" in an error | the project or vector path contains spaces; use `~/p7_gui` |
| Monitor black, LD3 off | laptop not sending: replug J10, check `xrandr` shows `DP-1` at 800x600, keep the viewer window open |
| Monitor black, LD3 on | the viewer window was closed or moved; restart `scripts/live_camera.py` |
| Monitor shows the checker pattern | live switched off with BTN2; press BTN2 |
