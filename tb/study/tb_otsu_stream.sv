`timescale 1ns/1ps
`default_nettype none
// Streaming adaptive-Otsu (rtl/otsu_stream.sv inside rtl/study/edge_pipeline_otsu.sv) against the paper's whole-frame engine.
//  * The same image is streamed FRAMES times with HB idle clocks per line and VB idle clocks between frames.
//  * The NMS frame of frame 0 (zero border included) is captured from the core and given to paper_top (the paper's
//    reference RTL: frame buffer + histogram + log-domain Otsu + classifier); its T_hi is the reference.
//  * Checks: (1) thresholds never change while a frame is being classified; (2) the first adaptive T_hi equals the
//    paper engine's T_hi; (3) every classified pixel of the last frame equals the paper engine's class for that pixel;
//    (4) the frame in which the adaptive thresholds first apply (1 with blanking, 2 without).
// plusargs: +IMG=<gray hex file, W*H bytes>  +EXPECT_APPLY=<frame index>  (+EXPECT_NONE when the frame is too short)
module tb_otsu_stream;
  parameter integer W = 64, H = 48, FRAMES = 3, HB = 16, VB = 1000;
  localparam integer XW = $clog2(W), YW = $clog2(H);
  logic clk = 0, rst = 1; always #5 clk = ~clk;
  logic in_valid = 0, in_sof = 0, in_eol = 0; logic [7:0] in_gray = 0;
  logic [10:0] thr_lo = 64, thr_hi = 192;
  wire out_valid, out_sof, out_eol, adapt_valid; wire [XW-1:0] out_x; wire [YW-1:0] out_y; wire [1:0] out_cls;
  wire [10:0] thr_lo_used, thr_hi_used;
  edge_pipeline_otsu #(.IMG_W(W), .IMG_H(H)) dut (
    .clk, .rst, .in_valid, .in_sof, .in_eol, .in_gray, .thr_lo, .thr_hi, .clear_hist(1'b0), .hist_rd_addr(6'd0),
    .hist_rd_data(), .hist_nnz(), .hist_valid(), .out_valid, .out_sof, .out_eol, .out_x, .out_y,
    .smooth_valid(), .smooth_gray(), .out_cls, .adapt_en(1'b1), .thr_lo_used, .thr_hi_used, .adapt_valid);

  // paper reference engine on the captured NMS frame
  logic p_start = 0, p_busy, p_done, p_ready, p_valid = 0, p_cv; logic [10:0] p_data = 0;
  logic [7:0] p_thi, p_tlo; logic [1:0] p_cls; logic [31:0] p_edges;
  paper_top #(.W(W), .H(H), .IN_W(11)) ref_engine (.clk, .rst, .start(p_start), .busy(p_busy), .done(p_done), .pix_ready(p_ready),
    .pix_valid(p_valid), .pix_data(p_data), .t_hi(p_thi), .t_lo(p_tlo), .class_valid(p_cv), .class_out(p_cls), .edge_count(p_edges));

  logic [7:0] img [0:W*H-1];
  logic [10:0] nms0 [0:W*H-1];
  logic [1:0] pcls [0:W*H-1];
  integer pc = 0, frame_out = 0, apply_frame = -1, errors = 0, cls_cmp = 0, cls_bad = 0, f, x, y, i;
  integer expect_apply = 1; bit expect_none = 0; string imgf;
  logic [10:0] lo_at_start, hi_at_start, lo_d, hi_d; logic adapt_d;
  logic [1:0] dcls [0:W*H-1];
  // thresholds in effect when a pixel was classified (classify_hist registers the class one clock later)
  always @(posedge clk) begin lo_d <= thr_lo_used; hi_d <= thr_hi_used; adapt_d <= adapt_valid; end
  logic captured = 0;
  integer ovr = 0; logic ovr_d = 0;
  always @(posedge clk) begin ovr_d <= dut.u_otsu.overrun; if (dut.u_otsu.overrun && !ovr_d) ovr++; end

  // capture NMS of frame 0 (zero border by construction)
  always @(posedge clk) begin
    if (!captured && dut.n_win_valid) nms0[(dut.n_win_y + 2) * W + dut.n_win_x + 2] <= dut.nms_mag;
    if (!captured && dut.nms_eof) captured <= 1;
  end
  // paper classes, in raster order
  always @(posedge clk) if (p_cv) begin pcls[pc] <= p_cls; pc <= pc + 1; end

  // output monitor: per-frame threshold stability and class comparison
  always @(posedge clk) begin
    if (out_valid) begin
      if (out_sof) begin lo_at_start <= lo_d; hi_at_start <= hi_d; end
      else if (lo_d !== lo_at_start || hi_d !== hi_at_start) begin
        errors++; if (errors < 5) $display("ERROR thresholds changed inside frame %0d at (%0d,%0d)", frame_out, out_x, out_y);
      end
      if (out_sof && adapt_d && apply_frame < 0) apply_frame = frame_out;
      if (frame_out == FRAMES - 1) begin dcls[out_y * W + out_x] <= out_cls; cls_cmp++; end
      if (out_x == W - 4 && out_y == H - 4) frame_out++;
    end
  end

  initial begin
    if (!$value$plusargs("IMG=%s", imgf)) imgf = "build/otsu/img.hex";
    if ($value$plusargs("EXPECT_APPLY=%d", expect_apply)) ;
    if ($test$plusargs("EXPECT_NONE")) expect_none = 1;
    $readmemh(imgf, img);
    for (i = 0; i < W*H; i++) nms0[i] = 0;
    repeat (4) @(posedge clk); rst <= 0;
    repeat (300) @(posedge clk);                         // INIT clears the histogram banks
    fork
      begin
        for (f = 0; f < FRAMES; f++) begin
          for (y = 0; y < H; y++) begin
            for (x = 0; x < W; x++) begin
              in_valid <= 1; in_sof <= (x == 0 && y == 0); in_eol <= (x == W - 1); in_gray <= img[y*W + x];
              @(posedge clk);
            end
            in_valid <= 0; in_sof <= 0; in_eol <= 0;
            repeat (HB) @(posedge clk);
          end
          repeat (VB) @(posedge clk);
        end
        repeat (4*W + 100) @(posedge clk);
      end
      begin
        if (!expect_none) begin
          wait (captured); repeat (3) @(posedge clk);
          p_start <= 1; @(posedge clk); p_start <= 0;
          wait (p_ready);
          for (i = 0; i < W*H; i++) begin p_valid <= 1; p_data <= nms0[i]; @(posedge clk); end
          p_valid <= 0;
          wait (p_done);
        end
      end
    join
    repeat (10) @(posedge clk);
    if (!expect_none) for (y = 3; y <= H - 4; y++) for (x = 3; x <= W - 4; x++)
      if (dcls[y*W + x] !== pcls[y*W + x]) begin cls_bad++; if (cls_bad < 5) $display("CLASS MISMATCH (%0d,%0d) dut=%0d paper=%0d", x, y, dcls[y*W+x], pcls[y*W+x]); end
    if (expect_none) begin
      if (apply_frame == -1 && errors == 0 && frame_out == FRAMES && ovr > 0)
        $display("PASS otsu_stream (overrun case) %0dx%0d frames=%0d: overrun detected %0d times, no adaptive threshold applied, thresholds stable", W, H, FRAMES, ovr);
      else $display("FAIL otsu_stream overrun case apply=%0d errors=%0d frames=%0d", apply_frame, errors, frame_out);
    end else if (errors == 0 && cls_bad == 0 && cls_cmp == (W-6)*(H-6) && apply_frame == expect_apply && thr_hi_used == 11'(p_thi) && thr_lo_used == 11'(p_tlo))
      $display("PASS otsu_stream %0dx%0d frames=%0d HB=%0d VB=%0d t_hi=%0d t_lo=%0d paper_t_hi=%0d applied_from_frame=%0d classes_compared=%0d mismatches=0 paper_strong=%0d",
               W, H, FRAMES, HB, VB, thr_hi_used, thr_lo_used, p_thi, apply_frame, cls_cmp, p_edges);
    else
      $display("FAIL otsu_stream errors=%0d cls_bad=%0d cls_cmp=%0d apply_frame=%0d (expect %0d) t_hi=%0d paper=%0d frames_out=%0d",
               errors, cls_bad, cls_cmp, apply_frame, expect_apply, thr_hi_used, p_thi, frame_out);
    $finish;
  end
endmodule
`default_nettype wire
