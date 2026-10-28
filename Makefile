PYTHON ?= python

.PHONY: smoke golden sim formal synth impl bit report clean

smoke:
	$(PYTHON) -c "import numpy, PIL, matplotlib, cv2, pytest, scipy; print('PASS Python scientific stack')"
	iverilog -V
	$(PYTHON) -c "import shutil; tools = ('vivado','verilator','yosys','sby','nuXmv','NuSMV','espresso','riscv32-unknown-elf-gcc'); [print(('FOUND ' if shutil.which(t) else 'NOT RUN (missing) ') + t) for t in tools]"

golden:
	$(PYTHON) -m pytest model/tests -q

sim:
	@echo "NOT RUN: P4 RTL and testbench regression has not been implemented yet."

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

