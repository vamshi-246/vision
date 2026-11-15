`default_nettype none
// BASELINE for the comparison: plain Sobel (|Gx|+|Gy|) on the unsmoothed gray stream with ONE global threshold: no Gaussian, no
// direction-based NMS, no double threshold.  Uses the same line buffer and the same hand-HLS Sobel as the main design.
module baseline_top #(
  parameter int unsigned IMG_W = 640, parameter int unsigned IMG_H = 480, parameter int unsigned THR = 192,
  parameter int unsigned X_W = $clog2(IMG_W), parameter int unsigned Y_W = $clog2(IMG_H)
) (
  input wire clk, rst, in_valid, in_sof, in_eol, input wire [7:0] in_gray,
  output logic out_valid, output logic edge_o
);
  logic wv; logic [X_W-1:0] wx; logic [Y_W-1:0] wy;
  logic [7:0] w00,w01,w02,w10,w11,w12,w20,w21,w22;
  linebuf #(.IMG_W(IMG_W), .IMG_H(IMG_H), .DATA_W(8), .X_W(X_W), .Y_W(Y_W)) lb (
    .clk, .rst, .pix_valid(in_valid), .pix_sof(in_sof), .pix_eol(in_eol), .pix_data(in_gray),
    .win_valid(wv), .win_x(wx), .win_y(wy), .w00, .w01, .w02, .w10, .w11, .w12, .w20, .w21, .w22);
  logic sv; logic [10:0] mag;
  sobel sb(.clk, .in_valid(wv), .w00, .w01, .w02, .w10, .w11, .w12, .w20, .w21, .w22, .out_valid(sv), .magnitude(mag), .direction());
  always_ff @(posedge clk) begin out_valid <= sv; edge_o <= sv && (mag >= 11'(THR)); end
endmodule
`default_nettype wire
