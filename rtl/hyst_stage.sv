`default_nettype none

// One K-stage conditional dilation pass.  Cascade K instances for K-stage
// hysteresis; K=0 bypasses this module.  Input class encoding is 00 none,
// 01 weak and 10 strong.  Each valid output is the centre pixel of a complete
// 3x3 input window, hence this stage contracts the valid region by one pixel.
module hyst_stage #(
  parameter int unsigned IMG_W = 640,
  parameter int unsigned IMG_H = 480,
  parameter int unsigned X_W = $clog2(IMG_W),
  parameter int unsigned Y_W = $clog2(IMG_H)
) (
  input  logic            clk,
  input  logic            rst,
  input  logic            in_valid,
  input  logic            in_sof,
  input  logic            in_eol,
  input  logic [1:0]      in_cls,
  output logic            out_valid,
  output logic            out_sof,
  output logic            out_eol,
  output logic [X_W-1:0]  out_x,
  output logic [Y_W-1:0]  out_y,
  output logic            out_edge
);
  logic [1:0] w00, w01, w02, w10, w11, w12, w20, w21, w22;
  logic any_strong;

  linebuf #(.IMG_W(IMG_W), .IMG_H(IMG_H), .DATA_W(2), .X_W(X_W), .Y_W(Y_W)) u_window (
    .clk, .rst, .pix_valid(in_valid), .pix_sof(in_sof), .pix_eol(in_eol),
    .pix_data(in_cls), .win_valid(out_valid), .win_x(out_x), .win_y(out_y),
    .w00, .w01, .w02, .w10, .w11, .w12, .w20, .w21, .w22
  );

  always_comb begin
    any_strong = (w00 == 2'b10) || (w01 == 2'b10) || (w02 == 2'b10) ||
                 (w10 == 2'b10) || (w11 == 2'b10) || (w12 == 2'b10) ||
                 (w20 == 2'b10) || (w21 == 2'b10) || (w22 == 2'b10);
    out_edge = (w11 == 2'b10) || ((w11 == 2'b01) && any_strong);
    out_sof = out_valid && (out_x == 1) && (out_y == 1);
    out_eol = out_valid && (out_x == IMG_W - 2);
  end
endmodule

`default_nettype wire
