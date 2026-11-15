# Pipeline latency (arithmetic, from the RTL)

Raster = WT x HT = 800 x 525, 1 pixel / clock, never stalled (II = 1).

| stage | latency from newest sample (clk) | source |
|---|---|---|
| input register (core_top din_q) | 1 | rtl/core_top.sv |
| gauss 3x3 (linebuf 2 + window/adder 2) | 4 | tb_gauss measured |
| sobel (S1..S6 + output reg) | 7 | doc/hand_hls_sobel.md schedule, tb_sobel |
| dirnms (dir_quant 2 + linebuf 2 + N1,N2 2) | 6 | tb_dirnms |
| classify | 1 | tb_classify |

Each 3x3 stage also has to wait for the pixel BELOW-RIGHT of its centre, i.e. one raster line plus one pixel:
(WT+1) = 801 clk, three times (gauss, sobel, dirnms).

K = 3 x (WT+1) + 19 = 3 x 801 + 19 = 2403 + 19 = 2422 clk
K / WT = 2422/800 = 3.0275 lines  (= 3 lines + 22 pixels)

The pipeline-register part is 1+4+7+6+1 = 19 clk; the testbench `tb_top` confirms K by checking that the
view outputs line up with the delayed gray/blur streams from cycle t0+K onward (0 mismatches, see sim/reports/tb_top_*.log).
At 25.175 MHz pixel clock: K x 39.72 ns = 96206.6 ns = 96.21 us.
