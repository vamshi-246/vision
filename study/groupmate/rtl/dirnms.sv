// dirnms -- direction quantiser + NMS select.   See doc/n4_espresso_results.md for the minimisation run.
//
//  dirq_decision : the 4-input / 4-output decision (c0,c2,sx,sy)->one-hot sector, written as the SOP cover
//                  returned by Espresso (scripts/espresso_dirnms.py, don't-cares c0=c2=1 with sx|sy).
//  dir_quant     : 2-stage pipeline.  D1: c0 = (ay*32 <= ax*13), c2 = (ax*32 <= ay*13)   [ax*13 = 8ax+4ax+ax]
//                                      D2: sel = dirq_decision(...)
//  dirnms        : dir_quant -> line buffers over {sel,mag} (15 bit) -> neighbour-pair select -> compare.
//                  NMS rule (asymmetric ties):  keep m  iff  m >= a  AND  m > b,   (a,b) = the sector's neighbour pair
//                       sector0: a=W  b=E | sector1: a=NW b=SE | sector2: a=N b=S | sector3: a=NE b=SW
//                  Output is 0 outside the margin-3 valid region.
module dirq_decision (
  input  logic c0, c2, sx, sy,
  output logic [3:0] sel          // {s3,s2,s1,s0}
);
  // Espresso cover (6 product terms, 19 literals):
  assign sel[0] = c0;
  assign sel[2] = ~c0 & c2;
  assign sel[1] = (~c0 & ~c2 & ~sx & ~sy) | (~c0 & ~c2 &  sx &  sy);
  assign sel[3] = (~c0 & ~c2 &  sx & ~sy) | (~c0 & ~c2 & ~sx &  sy);
endmodule

module dir_quant #(parameter int XW = 10) (
  input  logic          clk,
  input  logic [9:0]    ax, ay,
  input  logic          sx, sy,
  input  logic [10:0]   mag,
  input  logic [XW-1:0] xi, yi,
  output logic [3:0]    sel_o,
  output logic [10:0]   mag_o,
  output logic [XW-1:0] xo, yo
);
  logic [14:0] ay32, ax32, ax13, ay13;
  always_comb begin
    ay32 = {ay, 5'b0};                         // ay*32
    ax32 = {ax, 5'b0};
    ax13 = {2'b0, ax, 3'b0} + {3'b0, ax, 2'b0} + {5'b0, ax};   // 8ax + 4ax + ax
    ay13 = {2'b0, ay, 3'b0} + {3'b0, ay, 2'b0} + {5'b0, ay};
  end
  logic c0, c2, sx1, sy1; logic [10:0] mag1; logic [XW-1:0] x1, y1;
  logic [3:0] dec;
  dirq_decision u_dec (.c0, .c2, .sx(sx1), .sy(sy1), .sel(dec));
  // synthesis translate_off
  initial begin
    c0 = 1'b1; c2 = 1'b0; sx1 = 1'b0; sy1 = 1'b0; mag1 = '0; x1 = '0; y1 = '0; sel_o = 4'b0001; mag_o = '0; xo = '0; yo = '0;
  end
  // synthesis translate_on
  always_ff @(posedge clk) begin
    c0 <= (ay32 <= ax13);
    c2 <= (ax32 <= ay13);
    sx1 <= sx; sy1 <= sy; mag1 <= mag; x1 <= xi; y1 <= yi;
    sel_o <= dec; mag_o <= mag1; xo <= x1; yo <= y1;
  end
endmodule

module dirnms #(
  parameter int W = 640, parameter int H = 480, parameter int WT = 800, parameter int HT = 525,
  parameter int XW = 10
) (
  input  logic          clk,
  input  logic [XW-1:0] xi, yi,
  input  logic [9:0]    ax, ay,
  input  logic          sx, sy,
  input  logic [10:0]   mag,
  output logic [10:0]   nms_o,
  output logic [1:0]    dir_o,        // sector code at the centre pixel (aligned with nms_o)
  output logic [XW-1:0] xo, yo,
  output logic          vo
);
  logic [3:0] sel_q; logic [10:0] mag_q; logic [XW-1:0] xq, yq;
  dir_quant #(.XW(XW)) u_dq (.clk, .ax, .ay, .sx, .sy, .mag, .xi, .yi, .sel_o(sel_q), .mag_o(mag_q), .xo(xq), .yo(yq));

  logic [9*15-1:0] win;
  logic [XW-1:0] xw, yw, xc, yc; logic vreg;
  linebuf #(.DW(15), .WT(WT), .XW(XW)) u_lb (.clk, .xi(xq), .yi(yq), .din({sel_q, mag_q}), .win, .xo(xw), .yo(yw));
  tag_center #(.W(W), .H(H), .WT(WT), .HT(HT), .M(3), .XW(XW)) u_tc (.xi(xw), .yi(yw), .xc, .yc, .vreg);

  logic [10:0] m [0:8];
  logic [3:0]  selc;
  genvar gi;
  generate for (gi = 0; gi < 9; gi++) begin : g_m
    assign m[gi] = win[gi*15 +: 11];
  end endgenerate
  assign selc = win[4*15 + 11 +: 4];

  // N1: neighbour-pair select (one-hot AND-OR)
  logic [10:0] a1, b1, c1; logic [3:0] s1; logic [XW-1:0] x1, y1; logic v1;
  // synthesis translate_off
  initial begin
    a1 = '0; b1 = '0; c1 = '0; s1 = 4'b0001; x1 = '0; y1 = '0; v1 = 1'b0; nms_o = '0; dir_o = '0; xo = '0; yo = '0; vo = 1'b0;
  end
  // synthesis translate_on
  always_ff @(posedge clk) begin
    a1 <= ({11{selc[0]}} & m[3]) | ({11{selc[1]}} & m[0]) | ({11{selc[2]}} & m[1]) | ({11{selc[3]}} & m[2]);
    b1 <= ({11{selc[0]}} & m[5]) | ({11{selc[1]}} & m[8]) | ({11{selc[2]}} & m[7]) | ({11{selc[3]}} & m[6]);
    c1 <= m[4];
    s1 <= selc; x1 <= xc; y1 <= yc; v1 <= vreg;
    // N2: asymmetric-tie compare, mask to the valid region
    nms_o <= (v1 && (c1 >= a1) && (c1 > b1)) ? c1 : 11'd0;
    dir_o <= {s1[2] | s1[3], s1[1] | s1[3]};
    xo <= x1; yo <= y1; vo <= v1;
  end
endmodule
