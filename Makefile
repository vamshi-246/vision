PYTHON ?= $(if $(wildcard build/venv/bin/python),build/venv/bin/python,python3)
VIVADO ?= vivado
XILINX_VIVADO ?= /tools/Xilinx/Vivado/2024.2

.PHONY: smoke golden vectors sim stress regression netlist formal espresso soc video study verify synth impl bit report clean

smoke:
	$(PYTHON) -c "import numpy, PIL, matplotlib, cv2, pytest, scipy; print('PASS Python scientific stack')"
	iverilog -V
	$(PYTHON) -c "import shutil; tools = ('vivado','verilator','yosys','sby','nuXmv','NuSMV','espresso','riscv32-unknown-elf-gcc'); [print(('FOUND ' if shutil.which(t) else 'NOT RUN (missing) ') + t) for t in tools]"

golden:
	$(PYTHON) -m pytest model/tests -q

vectors:
	$(PYTHON) -m model.gen_vectors --outdir tb/vectors/generated

image:
	@echo "Usage: python -m model.run_image INPUT_IMAGE --outdir results/NAME"

sim:
	mkdir -p build
	iverilog -g2012 -Wall -s tb_vga_timing -o build/tb_vga_timing rtl/vga_timing.sv tb/unit/tb_vga_timing.sv
	vvp build/tb_vga_timing
	iverilog -g2012 -Wall -s tb_gauss -o build/tb_gauss rtl/gauss.sv tb/unit/tb_gauss.sv
	vvp build/tb_gauss
	iverilog -g2012 -Wall -s tb_linebuf -o build/tb_linebuf rtl/linebuf.sv tb/unit/tb_linebuf.sv
	vvp build/tb_linebuf
	iverilog -g2012 -Wall -s tb_classify_hist -o build/tb_classify_hist rtl/classify_hist.sv tb/unit/tb_classify_hist.sv
	vvp build/tb_classify_hist
	iverilog -g2012 -Wall -s tb_hyst_stage -o build/tb_hyst_stage rtl/linebuf.sv rtl/hyst_stage.sv tb/unit/tb_hyst_stage.sv
	vvp build/tb_hyst_stage
	iverilog -g2012 -Wall -s tb_crc32 -o build/tb_crc32 rtl/crc32.sv tb/unit/tb_crc32.sv
	vvp build/tb_crc32
	iverilog -g2012 -Wall -s tb_apb_regs -o build/tb_apb_regs rtl/apb_regs.sv tb/unit/tb_apb_regs.sv
	vvp build/tb_apb_regs
	iverilog -g2012 -Wall -s tb_ctrl_sync -o build/tb_ctrl_sync rtl/ctrl_sync.sv tb/unit/tb_ctrl_sync.sv
	vvp build/tb_ctrl_sync
	iverilog -g2012 -Wall -s tb_edge_pipeline -o build/tb_edge_pipeline rtl/linebuf.sv rtl/gauss.sv rtl/dir_decide.sv rtl/sobel.sv rtl/dirnms.sv rtl/classify_hist.sv rtl/top.sv tb/unit/tb_edge_pipeline.sv
	vvp build/tb_edge_pipeline
	iverilog -g2012 -Wall -s tb_sobel -o build/tb_sobel rtl/dir_decide.sv rtl/sobel.sv tb/unit/tb_sobel.sv
	vvp build/tb_sobel
	iverilog -g2012 -Wall -s tb_dirnms -o build/tb_dirnms rtl/dirnms.sv tb/unit/tb_dirnms.sv
	vvp build/tb_dirnms

formal:
	$(PYTHON) formal/run_ctl.py
	$(PYTHON) formal/abstract/run_formal.py | sed -n '/SUMMARY/,$$p'

espresso:
	$(PYTHON) logic/espresso_direction.py

soc:
	$(PYTHON) scripts/soc_regression.py

video:
	$(PYTHON) scripts/video_regression.py

study:
	$(PYTHON) scripts/gen_study_rtl.py
	$(PYTHON) scripts/baseline_check.py
	$(PYTHON) scripts/paper_quality.py
	$(PYTHON) scripts/otsu_check.py
	$(PYTHON) scripts/compare_resources.py

verify: sim stress regression video soc formal

stress:
	$(PYTHON) scripts/run_stress.py

regression:
	$(PYTHON) scripts/core_regression.py

netlist:
	$(PYTHON) scripts/netlist_regression.py --vivado-bin "$$(dirname "$$(command -v $(VIVADO))")"

synth:
	mkdir -p build
	P7_SYNTH_ONLY=1 $(VIVADO) -mode batch -source scripts/check_core.tcl -log build/vivado_core.log -journal build/vivado_core.jou

impl:
	mkdir -p build
	P7_REGISTERED_SHELL=1 P7_REPORT_DIR=build/vivado_registered $(VIVADO) -mode batch -source scripts/check_core.tcl -log build/vivado_registered.log -journal build/vivado_registered.jou

bit:
	@echo "NOT IMPLEMENTED: a board wrapper, clocking and validated constraints are required."
	@false

report:
	@echo "Review: docs/CORE_RTL_REVIEW.md; next steps: docs/FPGA_NEXT_STEPS.md"
	@echo "Machine-readable regression results: build/core_regression/summary.json"

clean:
	@echo "Generated outputs are ignored by Git; remove only named generated directories manually."


.PHONY: hdmi hdmi-sim hdmi-timing ila
hdmi:
	mkdir -p build
	$(VIVADO) -mode batch -source scripts/build_hdmi.tcl -log build/hdmi_build.log -journal build/hdmi_build.jou

live:
	mkdir -p build
	P7_BOARD=zybo_z7 P7_LIVE=1 $(VIVADO) -mode batch -source scripts/build_hdmi.tcl -log build/live_build.log -journal build/live_build.jou

ila:
	mkdir -p build
	P7_BOARD=zybo_z7 P7_ILA=1 $(VIVADO) -mode batch -source scripts/build_hdmi.tcl -log build/ila_build.log -journal build/ila_build.jou

live-sim:
	mkdir -p build/sim_rx_live
	cd build/sim_rx_live && $(XILINX_VIVADO)/bin/xvlog -sv ../../rtl/video/rx_timing.sv ../../rtl/video/rx_downscale.sv ../../tb/video/tb_rx_live.sv $(XILINX_VIVADO)/data/verilog/src/glbl.v > xvlog.log && $(XILINX_VIVADO)/bin/xelab -L xpm -L unisims_ver tb_rx_live glbl -s tbsim -timescale 1ns/1ps > xelab.log && $(XILINX_VIVADO)/bin/xsim tbsim -R | tee xsim.log | grep -E "TB_RX_LIVE|MISMATCH|frame"

hdmi-sim:
	$(PYTHON) scripts/video_regression.py

hdmi-timing:
	$(PYTHON) scripts/hdmi_timing_sim.py --corner functional
	$(PYTHON) scripts/hdmi_timing_sim.py --corner max
	$(PYTHON) scripts/hdmi_timing_sim.py --corner min
