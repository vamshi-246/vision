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

