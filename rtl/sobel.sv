`default_nettype none

// Hand-HLS Sobel arithmetic core.  V/W column sharing is exposed as pipeline
// stages; a new valid window can enter each clock (II=1).
module sobel #(
  parameter int unsigned PIX_W = 8
) (
  input  logic             clk,
  input  logic             in_valid,
  input  logic [PIX_W-1:0] w00,
  input  logic [PIX_W-1:0] w01,
  input  logic [PIX_W-1:0] w02,
  input  logic [PIX_W-1:0] w10,
  input  logic [PIX_W-1:0] w11,
  input  logic [PIX_W-1:0] w12,
  input  logic [PIX_W-1:0] w20,
  input  logic [PIX_W-1:0] w21,
  input  logic [PIX_W-1:0] w22,
  output logic             out_valid,
  output logic [10:0]      magnitude,
  output logic [1:0]       direction
);
  logic valid_0, valid_1, valid_2;
  logic [9:0] v_left_0, v_right_0;
  logic signed [9:0] w_left_0, w_mid_0, w_right_0;
  logic signed [10:0] gx_1, gy_1;
  logic signed [10:0] gx_2, gy_2;
  logic [10:0] ax_2, ay_2;
  logic sx_2, sy_2;
  logic [15:0] lhs_h, rhs_h, lhs_v, rhs_v;

  function automatic logic [10:0] abs11(input logic signed [10:0] value);
    if (value < 0) begin
      abs11 = -value;
    end else begin
      abs11 = value;
    end
  endfunction

  always_comb begin
    lhs_h = {5'b0, ay_2} << 5;
    rhs_h = ({5'b0, ax_2} << 3) + ({5'b0, ax_2} << 2) + {5'b0, ax_2};
    lhs_v = {5'b0, ax_2} << 5;
    rhs_v = ({5'b0, ay_2} << 3) + ({5'b0, ay_2} << 2) + {5'b0, ay_2};
  end

  always_ff @(posedge clk) begin
    // Stage 0: shared column sums/differences.
    v_left_0  <= w00 + (w10 << 1) + w20;
    v_right_0 <= w02 + (w12 << 1) + w22;
    w_left_0  <= $signed({1'b0, w20}) - $signed({1'b0, w00});
    w_mid_0   <= $signed({1'b0, w21}) - $signed({1'b0, w01});
    w_right_0 <= $signed({1'b0, w22}) - $signed({1'b0, w02});
    valid_0   <= in_valid;

    // Stage 1: Gx and tree-height-reduced Gy.
    gx_1    <= $signed({1'b0, v_right_0}) - $signed({1'b0, v_left_0});
    gy_1    <= $signed(w_left_0) + $signed(w_right_0) + ($signed(w_mid_0) <<< 1);
    valid_1 <= valid_0;

    // Stage 2: absolute values and signs.
    gx_2    <= gx_1;
    gy_2    <= gy_1;
    ax_2    <= abs11(gx_1);
    ay_2    <= abs11(gy_1);
    sx_2    <= gx_1 < 0;
    sy_2    <= gy_1 < 0;
    valid_2 <= valid_1;

    // Stage 3: Appendix-A L1 magnitude and direction comparator tree.
    magnitude <= ax_2 + ay_2;
    if (lhs_h <= rhs_h) begin
      direction <= 2'b00;
    end else if (lhs_v <= rhs_v) begin
      direction <= 2'b10;
    end else if (sx_2 == sy_2) begin
      direction <= 2'b01;
    end else begin
      direction <= 2'b11;
    end
    out_valid <= valid_2;
  end
endmodule

`default_nettype wire

