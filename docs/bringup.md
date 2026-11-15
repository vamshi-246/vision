# Board bring-up

> The Zybo Z7-10 built-in-pattern HDMI implementation is now in
> [HDMI_BRINGUP.md](HDMI_BRINGUP.md). Use that guide for the board project and
> programming commands; the broader integration work below remains a roadmap.

> For the tested core and current integration steps, use
> [FPGA_NEXT_STEPS.md](FPGA_NEXT_STEPS.md). The board/UART details below are
> historical planning assumptions; hardware deployment has not been tested.

## Target

Digilent Zybo Z7-10 Rev. B (`xc7z010clg400-1`), using its HDMI TX port.  The
board does not provide on-board VGA; the project therefore implements DVI/HDMI
transmit rather than a VGA resistor DAC.

## Optional UART loader wiring

Use a Digilent Pmod USBUART in the JE standard Pmod header.  Connect FPGA TX
(JE pin 2, `W16`) to the adapter RXD and FPGA RX (JE pin 3, `J15`) to adapter
TXD.  Leave RTS/CTS unused and set the adapter power jumper to `LCL`, because
the Zybo supplies its own 3.3 V rail.

The current repository contains planning collateral only; programming and
image-loader steps will be added after the M5/M6 integration gate.
