	.section .text.start
	.globl _start
_start:
	li   sp, 0x2000        # top of the 8 KB RAM
	call main
1:	j    1b
