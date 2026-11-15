# Architecture decisions

## D-001 — Target board and video connector

The supplied master constraints identify a Digilent Zybo Z7 Rev. B.  The
required `xc7z010clg400-1` device identifies the Z7-10 variant, so this
project targets its HDMI transmitter, not VGA.  The top-level constraints will
use the HDMI TX pins from `Zybo-Z7-Master.xdc`.

## D-002 — Optional PL UART connection

Zybo Z7-10 has no Pmod JB connector.  An optional Digilent Pmod USBUART is
assigned to the standard JE Pmod header: JE pin 2 (`W16`) is FPGA TX and JE
pin 3 (`J15`) is FPGA RX.  Its signals cross to the module's RXD/TXD,
respectively.  RTS/CTS are unused.  This does not use the Zynq PS UART.

## D-003 — Replaceable CPU boundary

VL326 RTL is unavailable.  The M6 wrapper will use PicoRV32's native memory
interface, preserving a small decoder/APB boundary so a VL326 RV32I core can
replace it without changing video peripherals.

## D-004 — Golden-model migration

The supplied `p7 golden.py` remains the only arithmetic source of truth during
M0.  `golden/p7_golden.py` is a forwarding entry point to avoid an unsound
duplicate while M1 adds the prescribed golden extensions.  It will be made
self-contained before the M1 vector gate is declared passed.
