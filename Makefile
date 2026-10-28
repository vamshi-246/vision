PYTHON ?= python

.PHONY: smoke golden sim formal synth impl bit report clean

smoke:
	$(PYTHON) -c "import numpy, PIL, matplotlib, cv2, pytest, scipy; print('PASS Python scientific stack')"
	iverilog -V
	$(PYTHON) -c "import shutil; tools = ('vivado','verilator','yosys','sby','nuXmv','NuSMV','espresso','riscv32-unknown-elf-gcc'); [print(('FOUND ' if shutil.which(t) else 'NOT RUN (missing) ') + t) for t in tools]"

golden:
	$(PYTHON) -m pytest model/tests -q

sim:
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
	iverilog -g2012 -Wall -s tb_edge_pipeline -o build/tb_edge_pipeline rtl/linebuf.sv rtl/gauss.sv rtl/sobel.sv rtl/dirnms.sv rtl/classify_hist.sv rtl/top.sv tb/unit/tb_edge_pipeline.sv
	vvp build/tb_edge_pipeline
	iverilog -g2012 -Wall -s tb_sobel -o build/tb_sobel rtl/sobel.sv tb/unit/tb_sobel.sv
	vvp build/tb_sobel
	iverilog -g2012 -Wall -s tb_dirnms -o build/tb_dirnms rtl/dirnms.sv tb/unit/tb_dirnms.sv
	vvp build/tb_dirnms

formal:
	@echo "NOT RUN: NuSMV/nuXmv and SymbiYosys are unavailable on this machine."

synth:
	@echo "NOT RUN: Vivado is unavailable on this machine. fpga/build.tcl will be added in P7."

impl: synth

bit: synth

report:
	$(PYTHON) study/make_report_assets.py

clean:
	@echo "Generated outputs are ignored by Git; remove only named generated directories manually."

