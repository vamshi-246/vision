// gauss -- 3x3 Gaussian [1 2 1;2 4 2;1 2 1]/16, integer shift-add only, rounded (sum+8)>>4.
// Pipeline (II=1; every cycle accepts one pixel):
//   t   : din + tag in      t+2 : window regs valid (linebuf)
//   t+3 : row sums rt/rm/rb = p0 + 2*p1 + p2        (shift = wiring, 2 adders per row)
//   t+4 : dout = ((rt + 2*rm + rb + 8) >> 4), masked to 0 outside the valid region (margin 1)
// Latency from newest-sample-in to output = 4 cycles.  Output tag is the CENTRE tag.
module gauss #(
  parameter int W = 640, parameter int H = 480, parameter int WT = 800, parameter int HT = 525,
  parameter int XW = 10
) (
  input  logic          clk,
  input  logic [XW-1:0] xi, yi,
  input  logic [7:0]    din,
  output logic [7:0]    dout,
  output logic [XW-1:0] xo, yo,
  output logic          vo
);
  logic [71:0] win;
  logic [XW-1:0] xw, yw, xc, yc;
  logic vreg;
  linebuf #(.DW(8), .WT(WT), .XW(XW)) u_lb (.clk, .xi, .yi, .din, .win, .xo(xw), .yo(yw));
  tag_center #(.W(W), .H(H), .WT(WT), .HT(HT), .M(1), .XW(XW)) u_tc (.xi(xw), .yi(yw), .xc, .yc, .vreg);

  logic [7:0] p [0:8];
  always_comb for (int i = 0; i < 9; i++) p[i] = win[i*8 +: 8];

  logic [9:0]  rt, rm, rb;          // max 4*255 = 1020
  logic [XW-1:0] xa, ya; logic va;
  logic [11:0] s;
  always_comb s = {2'b0, rt} + {1'b0, rm, 1'b0} + {2'b0, rb} + 12'd8;   // <= 4088

  // synthesis translate_off
  initial begin
    rt = '0; rm = '0; rb = '0; xa = '0; ya = '0; va = 1'b0; dout = '0; xo = '0; yo = '0; vo = 1'b0;
  end
  // synthesis translate_on
  always_ff @(posedge clk) begin
    rt <= {2'b0, p[0]} + {1'b0, p[1], 1'b0} + {2'b0, p[2]};
    rm <= {2'b0, p[3]} + {1'b0, p[4], 1'b0} + {2'b0, p[5]};
    rb <= {2'b0, p[6]} + {1'b0, p[7], 1'b0} + {2'b0, p[8]};
    xa <= xc; ya <= yc; va <= vreg;
    dout <= va ? s[11:4] : 8'd0;
    xo <= xa; yo <= ya; vo <= va;
  end
endmodule
