// tag_center -- converts the tag of the NEWEST window column (xi,yi) into the tag of the window
// CENTRE and says whether the centre lies inside this stage's valid region.
//   centre linear index = newest linear index - (WT+1)   (one line + one pixel back), modulo WT*HT.
//   valid region        = M <= xc < W-M  and  M <= yc < H-M   (M = stage margin 1/2/3)
module tag_center #(
  parameter int W  = 640, parameter int H  = 480,
  parameter int WT = 800, parameter int HT = 525,
  parameter int M  = 1,
  parameter int XW = 10
) (
  input  logic [XW-1:0] xi, yi,
  output logic [XW-1:0] xc, yc,
  output logic          vreg
);
  logic [XW:0] ym0, ym;
  assign xc  = (xi == '0) ? XW'(WT - 1) : xi - 1'b1;
  // yc = (yi - 1 - (xi==0)) mod HT
  assign ym0 = {1'b0, yi} + (XW+1)'(HT) - (XW+1)'(1) - ((xi == '0) ? (XW+1)'(1) : (XW+1)'(0));
  assign ym  = (ym0 >= (XW+1)'(HT)) ? (ym0 - (XW+1)'(HT)) : ym0;
  assign yc  = ym[XW-1:0];
  assign vreg = (xc >= XW'(M)) && (xc < XW'(W - M)) && (yc >= XW'(M)) && (yc < XW'(H - M));
endmodule
