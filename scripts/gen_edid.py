#!/usr/bin/env python3
"""Generate a 800x600@60 Hz-only EDID (128-byte base block, padded to 256 lines) for dvi2rgb's DDC EEPROM emulation.
Output: third_party/dvi2rgb/src/dgl_800x600.data (one 8-bit binary string per line, like Digilent's files)."""
from pathlib import Path
e = bytearray(128)
e[0:8] = bytes([0, 255, 255, 255, 255, 255, 255, 0])
mid = ((ord('P') - 64) << 10) | ((ord('7') - 64 if False else 0) << 5)  # manufacturer id: "PLV"
mid = ((ord('P') - 64) << 10) | ((ord('L') - 64) << 5) | (ord('V') - 64)
e[8:10] = mid.to_bytes(2, 'big'); e[10:12] = (1).to_bytes(2, 'little'); e[12:16] = (1).to_bytes(4, 'little')
e[16] = 1; e[17] = 34          # week 1 of 2024
e[18] = 1; e[19] = 3           # EDID 1.3
e[20] = 0x80                   # digital input
e[21] = 34; e[22] = 27         # 34 x 27 cm
e[23] = 120                    # gamma 2.2
e[24] = 0x0A                   # RGB, preferred timing in first descriptor
e[25:35] = bytes([0xEE, 0x91, 0xA3, 0x54, 0x4C, 0x99, 0x26, 0x0F, 0x50, 0x54])  # chromaticity (sRGB-like)
e[35] = 0x00; e[36] = 0x01; e[37] = 0   # established timings: 800x600@60 only
for i in range(38, 54, 2): e[i] = 0x01; e[i + 1] = 0x01       # standard timings unused
# Detailed timing descriptor: 800x600@60 (VESA DMT), 40.000 MHz (4000 x 10 kHz), +hsync +vsync
d = bytearray(18)
d[0:2] = (4000).to_bytes(2, 'little')
d[2] = 800 & 255; d[3] = 256 & 255; d[4] = ((800 >> 8) << 4) | (256 >> 8)
d[5] = 600 & 255; d[6] = 28 & 255; d[7] = ((600 >> 8) << 4) | (28 >> 8)
d[8] = 40; d[9] = 128; d[10] = (1 << 4) | 4; d[11] = 0
d[12] = 340 & 255; d[13] = 270 & 255; d[14] = ((340 >> 8) << 4) | (270 >> 8)
d[15] = 0; d[16] = 0; d[17] = 0x1E
e[54:72] = d
# Monitor range limits: V 55-65 Hz, H 35-40 kHz, max pixel clock 50 MHz
e[72:90] = bytes([0, 0, 0, 0xFD, 0, 55, 65, 35, 40, 5, 0, 0x0A] + [0x20] * 6)
# Monitor name
name = b"P7 LIVE\n".ljust(13, b" ")
e[90:108] = bytes([0, 0, 0, 0xFC, 0]) + name
e[108:126] = bytes([0, 0, 0, 0x10, 0] + [0] * 13)
e[126] = 0
e[127] = (-sum(e[:127])) & 255
lines = [format(b, '08b') for b in e] + ['00000000'] * 128
out = Path(__file__).resolve().parent.parent / 'third_party' / 'dvi2rgb' / 'src' / 'dgl_800x600.data'
out.write_text('\n'.join(lines) + '\n')
print('wrote', out, len(lines), 'lines, checksum', hex(e[127]))
