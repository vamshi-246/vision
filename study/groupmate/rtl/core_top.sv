// core_top -- the whole edge-detection pipeline, NO pins, NO clocking: this is what every testbench instantiates.
//
//   pix_data/sof --> ctrl_sync (tags) --> [gray in reg] --> gauss --> sobel --> dirnms (dir quant + NMS) --> classify
//                                                            \__ blur         \__ views aligned with delay_ram
//   APB3 slave (apb_regs): CTRL, THR_HI, THR_LO, STATUS, EDGE_CNT, FRAME_CNT, WEAK_CNT, HIST_SEL/DATA, ID, THR_ACT.
//
// The raster is WT x HT cycles per frame (default 800x525, active 640x480), one pixel per clock, never stalled
// (II = 1).  `sof` marks the raster origin.  Outputs o_gray/o_blur/o_cls are aligned to each other and carry the
// tag (o_x,o_y) of the pixel they belong to.  Total latency from a pixel on pix_data to its classification:
//   K = 3*(WT+1) + 19 cycles  (see doc/latency.md)  -> LAT_K below.
module core_top #(
  parameter int W = 640, parameter int H = 480, parameter int WT = 800, parameter int HT = 525,
  parameter int XW = 10
) (
  input  logic          clk,
  input  logic          rst,
  input  logic          sof,
  input  logic [7:0]    pix_data,
  // APB3 slave
  input  logic          psel, penable, pwrite,
  input  logic [7:0]    paddr,
  input  logic [31:0]   pwdata,
  output logic [31:0]   prdata,
  output logic          pready, pslverr,
  // aligned result streams
  output logic [7:0]    o_gray,
  output logic [7:0]    o_blur,
  output logic [1:0]    o_cls,
  output logic [XW-1:0] o_x, o_y,
  // status
  output logic          o_locked,
  output logic          o_frame_end,
  output logic          o_sync_err
);
  localparam int LAT_K    = 3 * (WT + 1) + 19;          // pixel in -> classification out, cycles
  localparam int LAT_BLUR = (WT + 1) + 5;               // pixel in -> blur(centre) out
  // ---- sync
  logic en;
  logic [XW-1:0] sx_, sy_;
  logic pix_ok, in_act, frame_start, frame_end, sync_err;
  ctrl_sync #(.W(W), .H(H), .WT(WT), .HT(HT), .XW(XW)) u_sync (
    .clk, .rst, .run_en(en), .sof, .locked(o_locked), .x(sx_), .y(sy_), .pix_ok, .in_act, .frame_start, .frame_end, .sync_err);
  assign o_frame_end = frame_end;
  assign o_sync_err  = sync_err;

  // ---- input register (blanking forced to 0 so garbage on the bus can never enter the line buffers)
  logic [7:0] din_q; logic [XW-1:0] xq, yq;
  // synthesis translate_off
  initial begin
    din_q = '0; xq = '0; yq = '0;
  end
  // synthesis translate_on
  always_ff @(posedge clk) begin din_q <= in_act ? pix_data : 8'd0; xq <= sx_; yq <= sy_; end

  // ---- stages
  logic [7:0] blur; logic [XW-1:0] xb, yb; logic vb;
  gauss #(.W(W), .H(H), .WT(WT), .HT(HT), .XW(XW)) u_gauss (.clk, .xi(xq), .yi(yq), .din(din_q), .dout(blur), .xo(xb), .yo(yb), .vo(vb));

  logic signed [10:0] gx, gy; logic [10:0] mag; logic [9:0] ax, ay; logic sxs, sys_; logic [XW-1:0] xs, ys; logic vs;
  sobel #(.W(W), .H(H), .WT(WT), .HT(HT), .XW(XW)) u_sobel (
    .clk, .xi(xb), .yi(yb), .din(blur), .gx_o(gx), .gy_o(gy), .mag_o(mag), .ax_o(ax), .ay_o(ay), .sx_o(sxs), .sy_o(sys_),
    .xo(xs), .yo(ys), .vo(vs));

  logic [10:0] nms; logic [1:0] dirn; logic [XW-1:0] xn, yn; logic vn;
  dirnms #(.W(W), .H(H), .WT(WT), .HT(HT), .XW(XW)) u_dirnms (
    .clk, .xi(xs), .yi(ys), .ax, .ay, .sx(sxs), .sy(sys_), .mag, .nms_o(nms), .dir_o(dirn), .xo(xn), .yo(yn), .vo(vn));

  logic [10:0] thr_hi, thr_lo, nms_c; logic [1:0] cls; logic [XW-1:0] xc, yc;
  classify #(.XW(XW)) u_cls (.clk, .nms, .thr_hi, .thr_lo, .xi(xn), .yi(yn), .cls, .nms_o(nms_c), .xo(xc), .yo(yc));

  apb_regs u_apb (.clk, .rst, .psel, .penable, .pwrite, .paddr, .pwdata, .prdata, .pready, .pslverr,
                  .locked(o_locked), .frame_end, .sync_err, .cls, .nms(nms_c), .en, .thr_hi_act(thr_hi), .thr_lo_act(thr_lo));

  // gray source for the view: masked bus value (same masking as the pipeline input), taken at pin time
  logic [7:0] pix_data_m;
  assign pix_data_m = in_act ? pix_data : 8'd0;
  // ---- view alignment: gray (pin time) delayed by K, blur (already LAT_BLUR late) delayed by K-LAT_BLUR
  logic [7:0] gray_al, blur_al;
  delay_ram #(.DW(8), .DELAY(LAT_K - 0)) u_dg (.clk, .din(pix_data_m), .dout(gray_al));
  delay_ram #(.DW(8), .DELAY(LAT_K - LAT_BLUR)) u_db (.clk, .din(blur), .dout(blur_al));
  assign o_gray = gray_al;
  assign o_blur = blur_al;
  assign o_cls  = cls;
  assign o_x = xc; assign o_y = yc;
endmodule
