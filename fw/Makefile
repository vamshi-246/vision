# Build the PicoRV32 firmware.  TOOLCHAIN defaults to the xPack GCC fetched into build/tools.
TC ?= ../build/tools/xpack-riscv-none-elf-gcc-15.2.0-1/bin
CC := $(TC)/riscv-none-elf-gcc
OBJCOPY := $(TC)/riscv-none-elf-objcopy
SIZE := $(TC)/riscv-none-elf-size
CFLAGS := -march=rv32i -mabi=ilp32 -Os -ffreestanding -fno-builtin -nostdlib -Wall -Wextra
all: build/fw.bin build/fw.hex
build/fw.elf: src/start.S src/main.c src/link.ld
	mkdir -p build
	$(CC) $(CFLAGS) -T src/link.ld -Wl,--gc-sections -o $@ src/start.S src/main.c
	$(SIZE) $@
build/fw.bin: build/fw.elf
	$(OBJCOPY) -O binary $< $@
build/fw.hex: build/fw.bin
	python3 -c "import sys;d=open('$<','rb').read();d+=b'\0'*(-len(d)%4);print('\n'.join('%08x'%int.from_bytes(d[i:i+4],'little') for i in range(0,len(d),4)))" > $@
clean:
	rm -rf build
