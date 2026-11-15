// baseline_top -- BASELINE of the 3-way comparison: plain Sobel (|Gx|+|Gy|) on the gray stream, ONE global fixed
// threshold, no Gaussian smoothing, no direction, no non-maximum suppression, no double threshold.  1-bit edge output.
// Re-uses the project's frame-sync tracker and the same hand-HLS sobel so the comparison isolates the algorithm stages.
module baseline_top #(
  parameter int W = 640, H = 480, WT = 800, HT = 525, XW = 10,
  parameter int THR = 192
) (
  input  logic          clk, rst, sof,
  input  logic [7:0]    pix_data,
  output logic          edge_o,
  output logic [XW-1:0] o_x, o_y
);
  logic [XW-1:0] sx, sy; logic locked, pix_ok, in_act, frame_start, frame_end, sync_err;
  ctrl_sync #(.W(W), .H(H), .WT(WT), .HT(HT), .XW(XW)) u_sync (.clk, .rst, .run_en(1'b1), .sof, .locked, .x(sx), .y(sy), .pix_ok, .in_act, .frame_start, .frame_end, .sync_err);
  logic [7:0] din_q; logic [XW-1:0] xq, yq;
  always_ff @(posedge clk) begin din_q <= in_act ? pix_data : 8'd0; xq <= sx; yq <= sy; end
  logic signed [10:0] gx, gy; logic [10:0] mag; logic [9:0] ax, ay; logic sxs, sys_; logic [XW-1:0] xs, ys; logic vs;
  sobel #(.W(W), .H(H), .WT(WT), .HT(HT), .XW(XW)) u_sobel (.clk, .xi(xq), .yi(yq), .din(din_q), .gx_o(gx), .gy_o(gy), .mag_o(mag),
    .ax_o(ax), .ay_o(ay), .sx_o(sxs), .sy_o(sys_), .xo(xs), .yo(ys), .vo(vs));
  always_ff @(posedge clk) begin edge_o <= vs && (mag >= 11'(THR)); o_x <= xs; o_y <= ys; end
endmodule
