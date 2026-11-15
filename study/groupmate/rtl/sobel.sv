// sobel -- Sobel Gx/Gy + L1 magnitude from the hand-HLS in doc/hand_hls_sobel.md.
//   CSE:  E1 = p22-p00 (shared)   E2 = p02-p20 (shared, opposite sign in Gy)   F = p12-p10   G = p21-p01
//         Gx = E1 + E2 + 2F       Gy = E1 - E2 + 2G              (8 adders, height 3, II = 1)
// Schedule (t = cycle the pixel enters linebuf):
//   t+2 S1 window   t+3 S2 E1,E2,F,G   t+4 S3 P=E1+E2, Q=E1-E2   t+5 S4 Gx,Gy (0 outside valid)
//   t+6 S5 |Gx|,|Gy|,signs             t+7 S6 mag = ax+ay        => latency 7, one result per cycle.
// All outputs are registered at S6 time and carry the CENTRE tag; outside the valid region (margin 2) they are 0.
module sobel #(
  parameter int W = 640, parameter int H = 480, parameter int WT = 800, parameter int HT = 525,
  parameter int XW = 10
) (
  input  logic                 clk,
  input  logic [XW-1:0]        xi, yi,
  input  logic [7:0]           din,          // blurred pixel stream
  output logic signed [10:0]   gx_o, gy_o,
  output logic [10:0]          mag_o,
  output logic [9:0]           ax_o, ay_o,
  output logic                 sx_o, sy_o,
  output logic [XW-1:0]        xo, yo,
  output logic                 vo
);
  logic [71:0] win;
  logic [XW-1:0] xw, yw, xc, yc;
  logic vreg;
  linebuf #(.DW(8), .WT(WT), .XW(XW)) u_lb (.clk, .xi, .yi, .din, .win, .xo(xw), .yo(yw));
  tag_center #(.W(W), .H(H), .WT(WT), .HT(HT), .M(2), .XW(XW)) u_tc (.xi(xw), .yi(yw), .xc, .yc, .vreg);

  logic signed [8:0] p [0:8];
  always_comb for (int i = 0; i < 9; i++) p[i] = $signed({1'b0, win[i*8 +: 8]});

  // S2
  logic signed [8:0] e1, e2, f2, g2;
  logic [XW-1:0] x2, y2; logic v2;
  // S3
  logic signed [9:0] pp, qq; logic signed [8:0] f3, g3;
  logic [XW-1:0] x3, y3; logic v3;
  // S4
  logic signed [10:0] gx4, gy4;
  logic [XW-1:0] x4, y4; logic v4;
  // S5
  logic signed [10:0] gx5, gy5; logic [9:0] ax5, ay5; logic sx5, sy5;
  logic [XW-1:0] x5, y5; logic v5;

  // synthesis translate_off
  initial begin
    e1 = '0; e2 = '0; f2 = '0; g2 = '0; x2 = '0; y2 = '0; v2 = 1'b0; pp = '0; qq = '0; f3 = '0; g3 = '0; x3 = '0; y3 = '0; v3 = 1'b0;
    gx4 = '0; gy4 = '0; x4 = '0; y4 = '0; v4 = 1'b0; gx5 = '0; gy5 = '0; ax5 = '0; ay5 = '0; sx5 = 1'b0; sy5 = 1'b0; x5 = '0; y5 = '0; v5 = 1'b0;
    mag_o = '0; gx_o = '0; gy_o = '0; ax_o = '0; ay_o = '0; sx_o = 1'b0; sy_o = 1'b0; xo = '0; yo = '0; vo = 1'b0;
  end
  // synthesis translate_on
  always_ff @(posedge clk) begin
    // S2: level-1 differences
    e1 <= p[8] - p[0];
    e2 <= p[2] - p[6];
    f2 <= p[5] - p[3];
    g2 <= p[7] - p[1];
    x2 <= xc; y2 <= yc; v2 <= vreg;
    // S3: level-2 sums sharing E1/E2
    pp <= e1 + e2;
    qq <= e1 - e2;
    f3 <= f2; g3 <= g2;
    x3 <= x2; y3 <= y2; v3 <= v2;
    // S4: level-3 (2F, 2G are shifts); zeroed outside the valid region
    gx4 <= v3 ? (11'(pp) + {f3[8], f3, 1'b0}) : 11'sd0;
    gy4 <= v3 ? (11'(qq) + {g3[8], g3, 1'b0}) : 11'sd0;
    x4 <= x3; y4 <= y3; v4 <= v3;
    // S5: absolute values
    gx5 <= gx4; gy5 <= gy4;
    ax5 <= gx4[10] ? 10'(-gx4) : 10'(gx4);
    ay5 <= gy4[10] ? 10'(-gy4) : 10'(gy4);
    sx5 <= gx4[10]; sy5 <= gy4[10];
    x5 <= x4; y5 <= y4; v5 <= v4;
    // S6: magnitude, everything else delayed one register
    mag_o <= {1'b0, ax5} + {1'b0, ay5};
    gx_o <= gx5; gy_o <= gy5; ax_o <= ax5; ay_o <= ay5; sx_o <= sx5; sy_o <= sy5;
    xo <= x5; yo <= y5; vo <= v5;
  end
endmodule
