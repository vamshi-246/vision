`default_nettype none

// Hand-HLS Sobel arithmetic core (derivation and schedule: hls/hand_hls_sobel.md).
// CSE: E1=p22-p00 and E2=p02-p20 are shared by Gx and Gy (Gx=E1+E2+2F, Gy=E1-E2+2G): 8 adders instead of 10.
// Four registered stages, a new valid window can enter each clock (II=1).
module sobel #(
  parameter int unsigned PIX_W = 8
) (
  input  wire              clk,
  input  wire              in_valid,
  input  wire  [PIX_W-1:0] w00,
  input  wire  [PIX_W-1:0] w01,
  input  wire  [PIX_W-1:0] w02,
  input  wire  [PIX_W-1:0] w10,
  input  wire  [PIX_W-1:0] w11,
  input  wire  [PIX_W-1:0] w12,
  input  wire  [PIX_W-1:0] w20,
  input  wire  [PIX_W-1:0] w21,
  input  wire  [PIX_W-1:0] w22,
  output logic             out_valid,
  output logic [10:0]      magnitude,
  output logic [1:0]       direction
);
  logic valid_0, valid_1, valid_2;
  logic signed [9:0] e1_0, e2_0, f_0, g_0;
  logic signed [10:0] gx_1, gy_1;
  logic [10:0] ax_2, ay_2;
  logic sx_2, sy_2;
  logic [15:0] lhs_h, rhs_h, lhs_v, rhs_v;

  initial begin
    if (PIX_W != 8) $fatal(1, "Sobel's 11-bit output contract requires PIX_W=8");
  end

  function automatic logic [10:0] abs11(input logic signed [10:0] value);
    if (value < 0) begin
      abs11 = -value;
    end else begin
      abs11 = value;
    end
  endfunction

  // Comparators stay arithmetic; the logic after them is the Espresso block.
  wire cmp_c0 = (lhs_h <= rhs_h);   // 32|Gy| <= 13|Gx|  -> horizontal gradient
  wire cmp_c2 = (lhs_v <= rhs_v);   // 32|Gx| <= 13|Gy|  -> vertical gradient
  wire [1:0] dir_w;
  dir_decide u_dir_decide(.c0(cmp_c0), .c2(cmp_c2), .sx(sx_2), .sy(sy_2), .dir(dir_w));

  always_comb begin
    lhs_h = {5'b0, ay_2} << 5;
    rhs_h = ({5'b0, ax_2} << 3) + ({5'b0, ax_2} << 2) + {5'b0, ax_2};
    lhs_v = {5'b0, ax_2} << 5;
    rhs_v = ({5'b0, ay_2} << 3) + ({5'b0, ay_2} << 2) + {5'b0, ay_2};
  end

  always_ff @(posedge clk) begin
    // Stage 0: the four shared/own differences (CSE).
    e1_0    <= $signed({1'b0, w22}) - $signed({1'b0, w00});
    e2_0    <= $signed({1'b0, w02}) - $signed({1'b0, w20});
    f_0     <= $signed({1'b0, w12}) - $signed({1'b0, w10});
    g_0     <= $signed({1'b0, w21}) - $signed({1'b0, w01});
    valid_0 <= in_valid;

    // Stage 1: P=E1+E2 and Q=E1-E2 (shared), then Gx=P+2F, Gy=Q+2G: two-level adder trees.
    gx_1    <= ($signed({e1_0[9], e1_0}) + $signed({e2_0[9], e2_0})) + ($signed({f_0[9], f_0}) <<< 1);
    gy_1    <= ($signed({e1_0[9], e1_0}) - $signed({e2_0[9], e2_0})) + ($signed({g_0[9], g_0}) <<< 1);
    valid_1 <= valid_0;

    // Stage 2: absolute values and signs.
    ax_2    <= abs11(gx_1);
    ay_2    <= abs11(gy_1);
    sx_2    <= gx_1 < 0;
    sy_2    <= gy_1 < 0;
    valid_2 <= valid_1;

    // Stage 3: Appendix-A L1 magnitude and direction comparator tree.
    magnitude <= ax_2 + ay_2;
    direction <= dir_w;   // Espresso-minimised decision (logic/espresso_direction.py)
    out_valid <= valid_2;
  end
endmodule

`default_nettype wire

