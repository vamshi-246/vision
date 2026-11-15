// paper_system -- resource-comparison wrapper (synthesis estimate only): OUR front end (ctrl_sync, gauss, sobel, dirnms)
// feeding the PAPER re-implementation's adaptive-threshold engine (paper_top: frame buffer + histogram + Otsu + classify)
// instead of our streaming classifier + APB registers.  Needs the reference zip's paper_*.sv files.
module paper_system #(parameter int W = 640, H = 480, WT = 800, HT = 525, XW = 10) (
  input  logic clk, rst, sof, input logic [7:0] pix_data, input logic start,
  output logic done, output logic [7:0] t_hi, t_lo, output logic class_valid, output logic [1:0] class_out, output logic [31:0] edge_count
);
  logic [XW-1:0] sx, sy; logic locked, pix_ok, in_act, frame_start, frame_end, sync_err;
  ctrl_sync #(.W(W), .H(H), .WT(WT), .HT(HT), .XW(XW)) u_sync (.clk, .rst, .run_en(1'b1), .sof, .locked, .x(sx), .y(sy), .pix_ok, .in_act, .frame_start, .frame_end, .sync_err);
  logic [7:0] din_q; logic [XW-1:0] xq, yq;
  always_ff @(posedge clk) begin din_q <= in_act ? pix_data : 8'd0; xq <= sx; yq <= sy; end
  logic [7:0] blur; logic [XW-1:0] xb, yb; logic vb;
  gauss #(.W(W), .H(H), .WT(WT), .HT(HT), .XW(XW)) u_gauss (.clk, .xi(xq), .yi(yq), .din(din_q), .dout(blur), .xo(xb), .yo(yb), .vo(vb));
  logic signed [10:0] gx, gy; logic [10:0] mag; logic [9:0] ax, ay; logic sxs, sys_; logic [XW-1:0] xs, ys; logic vs;
  sobel #(.W(W), .H(H), .WT(WT), .HT(HT), .XW(XW)) u_sobel (.clk, .xi(xb), .yi(yb), .din(blur), .gx_o(gx), .gy_o(gy), .mag_o(mag), .ax_o(ax), .ay_o(ay), .sx_o(sxs), .sy_o(sys_), .xo(xs), .yo(ys), .vo(vs));
  logic [10:0] nms; logic [1:0] dirn; logic [XW-1:0] xn, yn; logic vn;
  dirnms #(.W(W), .H(H), .WT(WT), .HT(HT), .XW(XW)) u_dirnms (.clk, .xi(xs), .yi(ys), .ax, .ay, .sx(sxs), .sy(sys_), .mag, .nms_o(nms), .dir_o(dirn), .xo(xn), .yo(yn), .vo(vn));
  logic act_n; assign act_n = (xn < W) && (yn < H);
  paper_top #(.W(W), .H(H), .IN_W(11)) u_paper (.clk, .rst, .start, .busy(), .done, .pix_ready(), .pix_valid(act_n), .pix_data(nms),
                                                  .t_hi, .t_lo, .class_valid, .class_out, .edge_count);
endmodule
